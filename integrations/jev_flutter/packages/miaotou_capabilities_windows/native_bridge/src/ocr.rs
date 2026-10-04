use std::path::PathBuf;

use anyhow::{Context, Result};
use image::{ImageBuffer, Rgb, RgbImage};
use rapidocr_core::RapidOcr;
use rapidocr_core::config::PipelineConfig;
use rapidocr_core::model::{ModelCache, model_set_by_name};
use serde_json::{Value, json};

use crate::capture::CapturedFrame;

pub struct OfflineOcr {
    model_dir: PathBuf,
    engine: Option<RapidOcr>,
}

impl OfflineOcr {
    pub fn new(model_dir: PathBuf) -> Result<Self> {
        Ok(Self {
            model_dir,
            engine: None,
        })
    }

    pub fn recognize(&mut self, frame: &CapturedFrame, languages: &[String]) -> Result<Value> {
        validate_languages(languages)?;
        let image = bgra_to_rgb(frame)?;
        let output = self.engine()?.run_image(&image)?;
        let lines = output
            .lines
            .into_iter()
            .map(|line| {
                let left = line
                    .bbox
                    .points
                    .iter()
                    .map(|point| point[0])
                    .fold(f32::INFINITY, f32::min);
                let top = line
                    .bbox
                    .points
                    .iter()
                    .map(|point| point[1])
                    .fold(f32::INFINITY, f32::min);
                let right = line
                    .bbox
                    .points
                    .iter()
                    .map(|point| point[0])
                    .fold(f32::NEG_INFINITY, f32::max);
                let bottom = line
                    .bbox
                    .points
                    .iter()
                    .map(|point| point[1])
                    .fold(f32::NEG_INFINITY, f32::max);
                json!({
                    "text": line.text,
                    "confidence": line.score,
                    "left": left,
                    "top": top,
                    "right": right,
                    "bottom": bottom,
                })
            })
            .collect::<Vec<_>>();
        Ok(json!({ "lines": lines }))
    }

    fn engine(&mut self) -> Result<&mut RapidOcr> {
        if self.engine.is_none() {
            let model_set = model_set_by_name("ppocrv5-ch-mobile")
                .context("the RapidOCR Chinese model set is not registered")?;
            let cache = ModelCache::new(&self.model_dir);
            let mut config = cache
                .config_for(model_set)
                .with_pipeline(PipelineConfig::without_cls());
            config.max_side_len = 4000;
            config.inference.intra_threads = 4;
            self.engine = Some(RapidOcr::from_config(config).with_context(|| {
                format!(
                    "cannot load offline RapidOCR models from {}",
                    self.model_dir.display()
                )
            })?);
        }

        Ok(self.engine.as_mut().expect("engine was initialized"))
    }
}

fn validate_languages(languages: &[String]) -> Result<()> {
    if languages.is_empty() {
        anyhow::bail!("at least one OCR language is required");
    }
    let unsupported = languages
        .iter()
        .filter(|language| !matches!(language.as_str(), "zh" | "zh-Hans" | "en"))
        .cloned()
        .collect::<Vec<_>>();
    if !unsupported.is_empty() {
        anyhow::bail!(
            "ppocrv5-ch-mobile does not support requested languages: {}",
            unsupported.join(", ")
        );
    }
    Ok(())
}

fn bgra_to_rgb(frame: &CapturedFrame) -> Result<RgbImage> {
    let expected = usize::try_from(frame.width)?
        .checked_mul(usize::try_from(frame.height)?)
        .and_then(|pixels| pixels.checked_mul(4))
        .context("frame dimensions overflow")?;
    if frame.pixels.len() != expected {
        anyhow::bail!(
            "frame has {} bytes, expected {expected}",
            frame.pixels.len()
        );
    }
    let mut rgb = Vec::with_capacity(expected / 4 * 3);
    for pixel in frame.pixels.chunks_exact(4) {
        rgb.extend_from_slice(&[pixel[2], pixel[1], pixel[0]]);
    }
    ImageBuffer::<Rgb<u8>, Vec<u8>>::from_raw(frame.width, frame.height, rgb)
        .context("could not construct RGB frame")
}
