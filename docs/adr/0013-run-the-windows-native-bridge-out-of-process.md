# Run the Windows native bridge out of process

- Status: accepted
- Date: 2026-10-03

## Context

Windows needs three things no Dart package provides, and ADR-0009 puts all three
behind one native bridge: continuous capture of a specific window by HWND,
including when it is occluded, through Windows Graphics Capture; synthetic text
input through `user32`/`kernel32`; and local Chinese OCR, which ADR-0009 keeps
native rather than reimplementing in Dart.

The existing Windows port already isolates the risky half. `main.py` is a parent
process that "only manages the interface", and `app/worker.py`'s `run(q, hwnd,
enabled, debug_on)` does capture, message-area detection and OCR in a **subprocess**
communicating over queues. The reason is stated in the file: one OCR pass costs
250–800ms, which would freeze a Qt main thread — and the worker keeps frames in
memory and never writes them to disk, downscaling a debug frame to a 1100px long
edge because a raw 2560-wide frame is 20MB across a queue.

Both WGC through a Rust extension and ONNX Runtime are C++ dependencies that can
fault. A capture session that dies mid-frame should not take the application's
credentials, memory store and settings window with it.

## Decision

**The Windows native bridge runs as a separate process. The Flutter side
communicates with it over IPC, and frames move through shared memory rather than
through copied channel payloads.**

1. **One bridge process carries all three capabilities** — capture, synthetic
   input and OCR — rather than one process per capability.
2. **Frames are shared, not copied.** The existing parent/child design already
   shows the cost of copying a full frame across a boundary; the Flutter side
   needs the same discipline, not a method channel carrying a 20MB buffer.
3. **The process boundary is the isolation boundary.** A fault in WGC or in the
   inference runtime restarts the bridge, and the parent reports a capture failure
   rather than dying.
4. **The bridge is a build artifact of the port**, packaged and signed alongside
   the application — not something fetched at runtime.

## Rejected alternatives

- **A single in-process Flutter plugin** doing capture, input and OCR, calling
  back into Dart. Lowest latency and the simplest packaging: one plugin, no IPC.
  Rejected because a fault in either C++ dependency becomes a fatal fault in the
  application, and the port's own history says the capture path is the one that
  misbehaves.
- **Hybrid: capture out of process, input and OCR in process.** Puts the riskiest
  dependency behind a boundary while keeping the rest cheap. Rejected because it
  buys a second set of native wiring and two protocols to maintain, for one of
  three capabilities.
- **`dart:ffi` directly into `user32`/`kernel32` for input synthesis**, leaving
  only capture native. Attractive for input — `package:win32` exists and
  `AttachThreadInput`-based focus stealing has to be written in whatever language
  anyway. Rejected as the *whole* answer because capture and OCR still need native
  code, so this splits the design without removing a boundary.
- **Run OCR as its own helper process**, leaving capture in process. Rejected: it
  splits one bridge into two and gives up the crash isolation exactly where it is
  most valuable.
- **Move the whole loop, including capture, into the Flutter process and accept
  the risk.** Rejected: it is a deliberate removal of a guard that exists today,
  in exchange for nothing the product needs.

## Consequences

- **The Windows port ships two binaries**, and the bridge needs its own build,
  signing and packaging step in the release pipeline.
- **The IPC protocol is part of the port's surface.** It has to be versioned
  against the Flutter side, which is a coupling the other two ports do not have.
- **Shared-memory frame transfer is new work.** The existing implementation copies
  every frame through a queue; a capture loop at the same cadence needs better than
  that, and the design must be settled before the Windows port starts rather than
  discovered during it.
- **The Windows port keeps a design that predates the migration**, which is worth
  noting for a reader who assumes the subprocess exists because of Flutter. It does
  not; it exists because OCR and capture are slow and the dependencies are native.
