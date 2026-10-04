use std::collections::VecDeque;
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, Ordering};
use std::thread::{self, JoinHandle};
use std::time::{Duration, Instant};

use anyhow::{Context as _, Result};
use parking_lot::{Condvar, Mutex};
use serde_json::{Value, json};
use windows::Win32::UI::HiDpi::GetDpiForWindow;
use windows_capture::capture::{Context, GraphicsCaptureApiHandler};
use windows_capture::frame::Frame;
use windows_capture::graphics_capture_api::InternalCaptureControl;
use windows_capture::settings::{
    ColorFormat, CursorCaptureSettings, DirtyRegionSettings, DrawBorderSettings,
    MinimumUpdateIntervalSettings, SecondaryWindowSettings, Settings,
};
use windows_capture::window::Window;

use crate::shared_frame::SharedFrame;

const FRAME_WAIT: Duration = Duration::from_millis(2500);
const RETAINED_GENERATIONS: usize = 4;

#[derive(Clone)]
pub struct CapturedFrame {
    pub generation: u64,
    pub pixels: Arc<Vec<u8>>,
    pub width: u32,
    pub height: u32,
    pub scale: f64,
    pub origin_x: f64,
    pub origin_y: f64,
}

#[derive(Default)]
struct Latest {
    frame: Option<CapturedFrame>,
    next_generation: u64,
    closed: bool,
    error: Option<String>,
}

struct SharedState {
    latest: Mutex<Latest>,
    changed: Condvar,
    stop: AtomicBool,
}

pub struct CaptureManager {
    target: Option<String>,
    state: Option<Arc<SharedState>>,
    thread: Option<JoinHandle<()>>,
    shared: VecDeque<(u64, SharedFrame)>,
    published: VecDeque<CapturedFrame>,
}

impl CaptureManager {
    pub fn new() -> Self {
        Self {
            target: None,
            state: None,
            thread: None,
            shared: VecDeque::new(),
            published: VecDeque::new(),
        }
    }

    pub fn find_target_window(&self) -> Result<Option<String>> {
        let windows = Window::enumerate()?;
        let mut first = None;
        for window in windows {
            let process = window.process_name().unwrap_or_default().to_lowercase();
            if process != "weixin.exe" && process != "wechat.exe" {
                continue;
            }
            let id = (window.as_raw_hwnd() as usize).to_string();
            if window.title().unwrap_or_default() == "微信" {
                return Ok(Some(id));
            }
            first.get_or_insert(id);
        }
        Ok(first)
    }

    pub fn latest(&mut self, target: Option<&str>) -> Result<Value> {
        let target = match target {
            Some(target) => target.to_owned(),
            None => self
                .find_target_window()?
                .context("no visible WeChat window found")?,
        };
        if self.target.as_deref() != Some(&target) {
            self.start(&target)?;
        }
        let state = self.state.as_ref().context("capture did not start")?;
        let deadline = Instant::now() + FRAME_WAIT;
        let mut latest = state.latest.lock();
        loop {
            if let Some(error) = latest.error.take() {
                return Ok(json!({
                    "captured": false,
                    "code": 2,
                    "message": error,
                }));
            }
            if let Some(frame) = latest.frame.clone() {
                drop(latest);
                return self.publish(frame);
            }
            if latest.closed {
                return Ok(json!({
                    "captured": false,
                    "code": 3,
                    "message": "目标窗口已关闭",
                }));
            }
            let now = Instant::now();
            if now >= deadline {
                return Ok(json!({
                    "captured": false,
                    "code": 4,
                    "message": "等待 WGC 帧超时",
                }));
            }
            state.changed.wait_for(&mut latest, deadline - now);
        }
    }

    pub fn frame(&self, generation: u64) -> Result<CapturedFrame> {
        if let Some(frame) = self
            .published
            .iter()
            .find(|frame| frame.generation == generation)
        {
            return Ok(frame.clone());
        }
        let state = self.state.as_ref().context("capture is not running")?;
        let latest = state.latest.lock();
        let frame = latest.frame.clone().context("no captured frame")?;
        if frame.generation != generation {
            anyhow::bail!(
                "frame generation {generation} expired; latest is {}",
                frame.generation
            );
        }
        Ok(frame)
    }

    fn publish(&mut self, frame: CapturedFrame) -> Result<Value> {
        let mapping = SharedFrame::create(frame.generation, &frame.pixels)?;
        let mapping_name = mapping.name.clone();
        self.shared.push_back((frame.generation, mapping));
        self.published.push_back(frame.clone());
        while self.shared.len() > RETAINED_GENERATIONS {
            self.shared.pop_front();
        }
        while self.published.len() > RETAINED_GENERATIONS {
            self.published.pop_front();
        }
        Ok(json!({
            "captured": true,
            "generation": frame.generation,
            "mapping": mapping_name,
            "byteLength": frame.pixels.len(),
            "width": frame.width,
            "height": frame.height,
            "scaleX": frame.scale,
            "scaleY": frame.scale,
            "originX": frame.origin_x,
            "originY": frame.origin_y,
        }))
    }

    fn start(&mut self, target: &str) -> Result<()> {
        self.stop();
        let raw = target.parse::<usize>().context("windowId is not an HWND")?;
        let window = Window::from_raw_hwnd(raw as *mut _);
        if !window.is_valid() {
            anyhow::bail!("windowId is not a visible top-level window");
        }
        let rectangle = window.rect()?;
        let dpi = unsafe { GetDpiForWindow(windows::Win32::Foundation::HWND(raw as *mut _)) };
        let scale = if dpi == 0 { 1.0 } else { f64::from(dpi) / 96.0 };
        let state = Arc::new(SharedState {
            latest: Mutex::new(Latest::default()),
            changed: Condvar::new(),
            stop: AtomicBool::new(false),
        });
        let flags = CaptureFlags {
            state: Arc::clone(&state),
            scale,
            origin_x: f64::from(rectangle.left) / scale,
            origin_y: f64::from(rectangle.top) / scale,
        };
        let thread = thread::Builder::new()
            .name("miaotou-wgc".to_owned())
            .spawn(move || {
                let settings = Settings::new(
                    window,
                    CursorCaptureSettings::WithoutCursor,
                    DrawBorderSettings::Default,
                    SecondaryWindowSettings::Exclude,
                    MinimumUpdateIntervalSettings::Custom(Duration::from_millis(50)),
                    DirtyRegionSettings::Default,
                    ColorFormat::Bgra8,
                    flags.clone(),
                );
                if let Err(error) = WgcCapture::start(settings) {
                    let mut latest = flags.state.latest.lock();
                    latest.error = Some(format!("WGC stopped: {error}"));
                    flags.state.changed.notify_all();
                }
            })?;
        self.target = Some(target.to_owned());
        self.state = Some(state);
        self.thread = Some(thread);
        Ok(())
    }

    pub fn stop(&mut self) {
        if let Some(state) = self.state.take() {
            state.stop.store(true, Ordering::Release);
        }
        if let Some(thread) = self.thread.take() {
            let _ = thread.join();
        }
        self.target = None;
        self.shared.clear();
        self.published.clear();
    }
}

impl Drop for CaptureManager {
    fn drop(&mut self) {
        self.stop();
    }
}

#[derive(Clone)]
struct CaptureFlags {
    state: Arc<SharedState>,
    scale: f64,
    origin_x: f64,
    origin_y: f64,
}

struct WgcCapture {
    flags: CaptureFlags,
    packed: Vec<u8>,
}

impl GraphicsCaptureApiHandler for WgcCapture {
    type Flags = CaptureFlags;
    type Error = Box<dyn std::error::Error + Send + Sync>;

    fn new(context: Context<Self::Flags>) -> Result<Self, Self::Error> {
        Ok(Self {
            flags: context.flags,
            packed: Vec::new(),
        })
    }

    fn on_frame_arrived(
        &mut self,
        frame: &mut Frame,
        control: InternalCaptureControl,
    ) -> Result<(), Self::Error> {
        if self.flags.state.stop.load(Ordering::Acquire) {
            control.stop();
            return Ok(());
        }
        let width = frame.width();
        let height = frame.height();
        let buffer = frame.buffer()?;
        let pixels = buffer.as_nopadding_buffer(&mut self.packed);
        if pixels.iter().all(|byte| *byte == 0) {
            return Ok(());
        }
        let mut latest = self.flags.state.latest.lock();
        latest.next_generation += 1;
        latest.frame = Some(CapturedFrame {
            generation: latest.next_generation,
            pixels: Arc::new(pixels.to_vec()),
            width,
            height,
            scale: self.flags.scale,
            origin_x: self.flags.origin_x,
            origin_y: self.flags.origin_y,
        });
        self.flags.state.changed.notify_all();
        Ok(())
    }

    fn on_closed(&mut self) -> Result<(), Self::Error> {
        let mut latest = self.flags.state.latest.lock();
        latest.closed = true;
        self.flags.state.changed.notify_all();
        Ok(())
    }
}
