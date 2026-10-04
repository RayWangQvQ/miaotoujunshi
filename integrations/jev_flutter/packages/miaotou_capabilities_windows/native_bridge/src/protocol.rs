use anyhow::{Context, Result};
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};

use crate::capture::CaptureManager;
use crate::inject;
use crate::ocr::OfflineOcr;

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Request {
    pub id: u64,
    pub method: String,
    #[serde(default)]
    pub arguments: Value,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Response {
    id: u64,
    ok: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    result: Option<Value>,
    #[serde(skip_serializing_if = "Option::is_none")]
    error: Option<String>,
}

impl Response {
    pub fn success(id: u64, result: Value) -> Self {
        Self {
            id,
            ok: true,
            result: Some(result),
            error: None,
        }
    }

    pub fn failure(id: u64, error: String) -> Self {
        Self {
            id,
            ok: false,
            result: None,
            error: Some(error),
        }
    }
}

pub fn dispatch(
    request: Request,
    capture: &mut CaptureManager,
    ocr: &mut OfflineOcr,
) -> Result<Value> {
    match request.method.as_str() {
        "window.findTarget" => Ok(json!({
            "windowId": capture.find_target_window()?,
        })),
        "capture.latest" => {
            let target = optional_string(&request.arguments, "windowId")?;
            capture.latest(target.as_deref())
        }
        "ocr.recognize" => {
            let generation = required_u64(&request.arguments, "generation")?;
            let languages = request
                .arguments
                .get("languages")
                .and_then(Value::as_array)
                .context("languages must be an array")?
                .iter()
                .map(|value| {
                    value
                        .as_str()
                        .map(str::to_owned)
                        .context("language must be a string")
                })
                .collect::<Result<Vec<_>>>()?;
            let frame = capture.frame(generation)?;
            ocr.recognize(&frame, &languages)
        }
        "input.inject" => {
            let window_id = required_string(&request.arguments, "windowId")?;
            let text = required_string(&request.arguments, "text")?;
            inject::inject(&window_id, &text)
        }
        method => anyhow::bail!("unknown method {method}"),
    }
}

fn optional_string(value: &Value, key: &str) -> Result<Option<String>> {
    match value.get(key) {
        None | Some(Value::Null) => Ok(None),
        Some(Value::String(value)) => Ok(Some(value.clone())),
        Some(_) => anyhow::bail!("{key} must be a string or null"),
    }
}

fn required_string(value: &Value, key: &str) -> Result<String> {
    value
        .get(key)
        .and_then(Value::as_str)
        .map(str::to_owned)
        .with_context(|| format!("{key} must be a string"))
}

fn required_u64(value: &Value, key: &str) -> Result<u64> {
    value
        .get(key)
        .and_then(Value::as_u64)
        .with_context(|| format!("{key} must be an unsigned integer"))
}
