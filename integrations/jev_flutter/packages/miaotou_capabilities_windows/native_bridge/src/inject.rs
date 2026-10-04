use anyhow::{Context, Result};
use serde_json::{Value, json};
use windows::Win32::Foundation::HWND;
use windows::Win32::System::Com::{
    CLSCTX_INPROC_SERVER, COINIT_APARTMENTTHREADED, CoCreateInstance, CoInitializeEx,
};
use windows::Win32::System::Variant::VARIANT;
use windows::Win32::UI::Accessibility::{
    CUIAutomation, IUIAutomation, IUIAutomationElement, IUIAutomationValuePattern,
    TreeScope_Descendants, UIA_ControlTypePropertyId, UIA_EditControlTypeId, UIA_ValuePatternId,
};
use windows::core::{BSTR, Interface};
use windows_capture::window::Window;

pub fn inject(window_id: &str, text: &str) -> Result<Value> {
    let raw = window_id
        .parse::<usize>()
        .context("windowId is not an HWND")?;
    validate_target(raw)?;
    unsafe {
        let _ = CoInitializeEx(None, COINIT_APARTMENTTHREADED).ok();
        let automation: IUIAutomation =
            CoCreateInstance(&CUIAutomation, None, CLSCTX_INPROC_SERVER)?;
        let root = automation.ElementFromHandle(HWND(raw as *mut _))?;
        let condition = automation.CreatePropertyCondition(
            UIA_ControlTypePropertyId,
            &VARIANT::from(UIA_EditControlTypeId.0),
        )?;
        let elements = root.FindAll(TreeScope_Descendants, &condition)?;
        let length = elements.Length()?;
        let mut chosen: Option<IUIAutomationElement> = None;
        let mut chosen_bottom = i32::MIN;
        for index in 0..length {
            let element = elements.GetElement(index)?;
            if element.CurrentIsEnabled()?.as_bool() && !element.CurrentIsOffscreen()?.as_bool() {
                let rectangle = element.CurrentBoundingRectangle()?;
                if rectangle.bottom > chosen_bottom {
                    chosen_bottom = rectangle.bottom;
                    chosen = Some(element);
                }
            }
        }
        let Some(element) = chosen else {
            return Ok(json!({
                "verified": false,
                "reason": "没有找到可写入的聊天输入框",
            }));
        };
        let pattern = element.GetCurrentPattern(UIA_ValuePatternId)?;
        let value: IUIAutomationValuePattern = pattern.cast()?;
        if value.CurrentIsReadOnly()?.as_bool() {
            return Ok(json!({
                "verified": false,
                "reason": "聊天输入框是只读的",
            }));
        }
        validate_target(raw)?;
        value.SetValue(&BSTR::from(text))?;
        let observed = value.CurrentValue()?.to_string();
        Ok(json!({
            "verified": observed == text,
            "observedText": observed,
            "reason": if observed == text {
                Value::Null
            } else {
                Value::String("写入后的文本与草稿不一致".to_owned())
            },
        }))
    }
}

fn validate_target(raw: usize) -> Result<()> {
    let window = Window::from_raw_hwnd(raw as *mut _);
    if !window.is_valid() {
        anyhow::bail!("target window is no longer a visible top-level window");
    }
    let process = window.process_name()?.to_lowercase();
    if process != "weixin.exe" && process != "wechat.exe" {
        anyhow::bail!("target window no longer belongs to WeChat");
    }
    Ok(())
}
