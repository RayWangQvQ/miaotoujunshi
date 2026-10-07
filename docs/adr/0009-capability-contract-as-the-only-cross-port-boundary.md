# Make the capability contract the only cross-port boundary

- Status: accepted
- Date: 2026-10-03

## Context

The three ports implement the platform layer three times with no shared
abstraction: macOS drives Quartz, Apple Vision and the Accessibility API; Windows
drives Win32, Windows Graphics Capture and RapidOCR; Android rides an
`AccessibilityService`. ADR-0007 collapses the business and UI layers into one
Dart codebase, which turns that platform layer into the only place the ports can
still differ. Without an explicit boundary, the difference reappears as
`if (Platform.isAndroid)` branches inside the domain.

Three measured properties have to survive the boundary, and each one is a reason a
naive interface fails:

1. **Android is event-driven; the desktop ports poll.** `ChatCaptureService` is
   woken by `TYPE_WINDOW_CONTENT_CHANGED` and pushes snapshots; macOS and Windows
   ask for a frame.
2. **Capture timing is a proven asset, not an implementation detail.** `ScreenCapture`
   carries a 1s rate limit, a 1→30s exponential backoff with a 6-attempt streak cap
   and a 3s watchdog; the Android panel hides itself for 120ms before a screenshot
   so the compositor drops its frame; macOS sticks to the window it chose instead of
   re-selecting each frame.
3. **The screenshot is not the screen.** Android captures a window, so a returned
   frame needs the mapping back to screen coordinates.

## Decision

**The platform layer is expressed once as a Dart interface set; the three
implementation packages are the only code that differs per platform.**

1. **Ten interfaces, one interface package, three implementation packages.** The
   platform group is `ScreenCapture`, `UiTreeReader`, `Ocr`, `TextInject` and
   `FloatingPanel`; the material group is `SharedPayload` (ADR-0008); the storage
   group is `Preferences`, `SecretStore`, `KnowledgeStore` and `MemoryStore`.
   `miaotou_capabilities` holds the interfaces, `miaotou_capabilities_<platform>`
   holds the implementations, and `miaotou_domain` depends on neither platform
   package. **Amended (2026-10-06, [ADR-0021](0021-carry-the-android-permissions-in-the-contract-and-open-their-system-pages.md)):**
   there are eleven. `Permissions` (`read()` / `openSettings(kind)`) joins the
   platform group, Android implements it, and both desktop ports refuse it — which
   is this decision's rule about declaring support, applied to a capability only
   one port has.
   **Amended (2026-10-07):** the three implementation packages are no longer the
   only implementation code. `miaotou_capabilities_shared` holds the modules all
   three ports use, and every port package depends on it:
   `miaotou_capabilities_<platform> → miaotou_capabilities_shared →
   miaotou_capabilities`. It sits *behind* the ports rather than beside them, so
   this is not a fourth port and no new cross-port seam appears — the domain still
   sees the contract and nothing else, and the interface package is still the only
   boundary above the ports. What it replaces is the platform-free **body** of four
   of the eleven interfaces — `Preferences`, `KnowledgeStore`, `MemoryStore` and
   `SharedPayload`, which had been written three times each and had drifted apart in
   record shape, validation and refusal wording — plus the capture schedule the two
   desktop ports had duplicated as two classes under two names. It reaches the
   platform through two small interfaces the port still implements: `TextDocuments`
   (one named document's bytes) and `PayloadTree` (the packaged payload). Where the
   bytes live, how a key joins a path, and how a write is made atomic stay on the
   port, because those are the parts that genuinely differ. The membership test is
   **"do all three ports use this?"**, not "is this platform-free?" — a package
   defined by "platform-free" would have to explain why `miaotou_domain` is not in
   it, and it would wrongly admit `perception.dart` (macOS's own calibration,
   ADR-0011 decision 6) and `EdgeSnap` / `PanelPositionMemory` (the contract's own
   value types).
2. **Support is declared, never implied.** A port that cannot implement a member
   throws. No implementation returns an empty buffer, an empty list, an
   `UnsupportedError`-swallowing null, or an inlined fallback. `UiTreeReader` on
   both desktop ports is exactly this case: it exists only where accessibility
   nodes exist.
3. **The platform owns *when*, the domain owns *what*.** Capture timing stays in
   the implementation — the rate limit, backoff, watchdog, the panel hide/restore
   around a screenshot and the chosen target window. The domain consumes a
   snapshot stream and produces the advice; it decides nothing about pacing.
4. **Geometry travels with the frame** (`scaleX`, `scaleY`, origin) so the domain
   can map a position in a window bitmap back to the screen, and the target window
   handle is held by the caller across frames rather than re-resolved each time —
   WeChat 4.x exposes several equally sized windows and re-selection makes the
   target jump.
5. **`TextInject` has no send path and must report verified landing.** The
   interface offers injection only, and its result carries a boolean that is true
   only after the implementation has read the text back by its own platform means
   (Android reads the node's text, macOS reads `AXValue`, Windows reads the node's
   text). Read-back verification is deliberately not a separate interface member:
   the three platforms verify in three different ways, and exposing it would leak
   those differences into the contract.
6. **`Ocr` takes the language list from the caller** and returns lines, hiding the
   model differences between ML Kit, Apple Vision and RapidOCR. On Windows the OCR
   runs **inside the native bridge** — Rust or C++ over ONNX Runtime, reusing
   RapidOCR's models and post-processing — not in Dart. DBNet post-processing needs
   contour detection and a perspective crop with no Dart equivalent, and rewriting
   it in `typed_data` for frames up to the 4000px detection limit would invalidate
   the accuracy work it exists to preserve. Putting it in the same native bridge as
   Windows Graphics Capture also avoids a second runtime.
7. **`FloatingPanel` carries window semantics only.** Placement, visibility, the
   hide-for-capture pair, focusable toggling, and an event stream for drag landing,
   taps and read-only flips. Rendering belongs to the UI layer, and the read-only
   derivation stays where ADR-0002 put it rather than becoming a Dart
   responsibility.

## Rejected alternatives

- **Two interface packages, platform and storage.** Desktop needs no
  `UiTreeReader`, so a single package makes every desktop implementation package
  carry explicit unsupported members. Split anyway, on the grounds that the
  storage group behaves near-identically on all three platforms — rejected because
  it adds a package and a dependency edge to remove about five declarations, and
  because `SecretStore` is genuinely per-platform on all three.
- **One package per capability.** Finest granularity and the easiest to replace in
  isolation, at the cost of ten interface packages and thirty implementation
  packages in one workspace.
- **Keep the capture loop inside each platform implementation**, as today.
  Smallest change and the best timing fidelity, but the domain would hold none of
  the orchestration and the deduplication that drives this migration would not
  reach the main path.
- **Move the whole loop, including throttling, into Dart.** The cleanest
  deduplication and the only variant testable with `dart test`, but it rewrites the
  rate limiter, the backoff and the watchdog — measured assets — and it puts a
  channel round-trip between "hide the panel" and "take the screenshot".
- **Reimplement RapidOCR's post-processing in Dart over `flutter_onnxruntime`.**
  Keeps OCR logic in one language and testable without a device. Rejected on the
  accuracy and performance risk above; the models are reused either way, and the
  Windows bridge exists regardless.
- **Expose read-back verification as a contract member.** Honest about what
  actually happens, but it makes every port describe a platform mechanism instead
  of a result.
- **Add a `send` member behind a flag.** Forbidden by `PRIVACY.md`; the absence is
  the design.

## Consequences

- **The compiler now forces each port to state support for every member.** A new
  capability cannot be added without all three ports answering for it — the
  property the three-stack layout has no equivalent for.
- **The desktop implementation packages contain deliberate `UnsupportedError`
  members**, flagged by a rule in `GLOSSARY.md` so a future reader does not
  "fix" them into silent empty returns.
- **`miaotou_domain` needs in-memory implementations of all ten interfaces to be
  testable**, which is a small amount of test scaffolding but the reason the domain
  is worth keeping platform-free.
- **Windows becomes the largest hand-written surface.** Capture, synthetic input
  and now OCR all live in one native bridge, and it is the port most likely to
  overrun.
- **The interface set is one document change away from being wrong.** A member the
  domain needs but no port can implement, or a port detail that only one port can
  honour, shows up as an awkward `UnsupportedError`. That pressure is intended:
  the contract is supposed to make platform differences loud.
- **Decision 3's line is now drawn inside the runtime, and it holds.** The runtime's
  state machine moved into `miaotou_domain` as `ConversationEngine`: what the panel
  is showing, whether a second round is refused or deferred, whether an event with
  no words ends a review, whether a refusal carries a way out. The pacing did **not**
  move with it — the rate limit, the backoff, the watchdog, the panel hide/restore
  around a screenshot and the chosen target window are all still in the
  implementations, and the rejected alternative above is still rejected. What the
  move showed is that "the domain owns *what*" was never only about snapshots and
  advice: 识别中 and 分析中 are things the panel shows, and the runtime had been
  answering for them from the application side. The shape that keeps the two apart
  mechanically is the effect list — the engine asks for a read, a capture or an
  injection and awaits none of them, so a decision cannot quietly turn into a timing
  decision. It is also what makes every transition reachable from `dart test` with
  nothing attached.
- **The shared module is `dart:io`-free, and that is enforced rather than
  intended.** Nothing under `packages/miaotou_capabilities_shared/lib` imports
  `dart:io`, `dart:ffi` or Flutter —
  `test/dependency_direction_test.dart` fails if anything does — so every module in
  it reaches the platform through `TextDocuments` or `PayloadTree` and the whole
  behaviour suite runs under `dart test` on any machine, with no device, no channel
  and no temporary directory. A module that needs a path is a module that does not
  belong there, and one that needs pixels or a node tree is one the port keeps.
- **Android's preferences left `SharedPreferences`.** The three documents
  (preferences, knowledge, memory) now cross one app-private document layer with the
  same atomic write on all three ports, the channel's four `preferences.*` members
  and the plugin's `SharedPreferences` instance are gone, and credentials stay in
  Kotlin where the Keystore is. The device answers only the two questions it is the
  only one that can: where a document name resolves to, and how bytes reach it
  atomically.
- **`undo` no longer crosses a restart on macOS and Windows.** The last-write stack
  was a document key on those two ports and a field on Android; the contract's own
  wording ("rolls back every write made **since this store was opened**") is the
  in-memory reading, so all three keep it in memory now. No user-facing behaviour is
  lost — the only caller in `lib/` is the support probe table — and a document
  written by an older build keeps its `undo` key as dead data that nothing reads and
  nothing refreshes.
