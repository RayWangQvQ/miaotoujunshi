mod capture;
mod inject;
mod ocr;
mod protocol;
mod shared_frame;

use std::io::{self, BufRead, Write};
use std::path::PathBuf;

use anyhow::{Context, Result};
use capture::CaptureManager;
use ocr::OfflineOcr;
use protocol::{Request, Response};

const PROTOCOL_VERSION: u32 = 1;

fn main() {
    if let Err(error) = run() {
        eprintln!("{error:#}");
        std::process::exit(1);
    }
}

fn run() -> Result<()> {
    let options = Options::parse()?;
    if options.protocol != PROTOCOL_VERSION {
        anyhow::bail!(
            "protocol mismatch: app requested {}, bridge implements {}",
            options.protocol,
            PROTOCOL_VERSION
        );
    }

    let mut capture = CaptureManager::new();
    let mut ocr = OfflineOcr::new(options.model_dir)?;
    let stdin = io::stdin();
    let mut stdout = io::stdout().lock();

    for line in stdin.lock().lines() {
        let line = line.context("failed to read command")?;
        let response = match serde_json::from_str::<Request>(&line) {
            Ok(request) => {
                let id = request.id;
                match protocol::dispatch(request, &mut capture, &mut ocr) {
                    Ok(result) => Response::success(id, result),
                    Err(error) => Response::failure(id, format!("{error:#}")),
                }
            }
            Err(error) => Response::failure(0, format!("invalid request: {error}")),
        };
        serde_json::to_writer(&mut stdout, &response)?;
        stdout.write_all(b"\n")?;
        stdout.flush()?;
    }
    capture.stop();
    Ok(())
}

struct Options {
    protocol: u32,
    model_dir: PathBuf,
}

impl Options {
    fn parse() -> Result<Self> {
        let mut stdio = false;
        let mut protocol = None;
        let mut model_dir = std::env::var_os("RAPIDOCR_MODEL_DIR").map(PathBuf::from);
        for argument in std::env::args().skip(1) {
            if argument == "--stdio" {
                stdio = true;
            } else if let Some(value) = argument.strip_prefix("--protocol=") {
                protocol = Some(value.parse().context("invalid --protocol")?);
            } else if let Some(value) = argument.strip_prefix("--model-dir=") {
                model_dir = Some(PathBuf::from(value));
            } else {
                anyhow::bail!("unknown argument: {argument}");
            }
        }
        if !stdio {
            anyhow::bail!("the bridge must be started with --stdio");
        }
        let executable = std::env::current_exe().context("cannot locate bridge executable")?;
        Ok(Self {
            protocol: protocol.context("missing --protocol")?,
            model_dir: model_dir.unwrap_or_else(|| {
                executable
                    .parent()
                    .unwrap_or_else(|| std::path::Path::new("."))
                    .join("models")
            }),
        })
    }
}
