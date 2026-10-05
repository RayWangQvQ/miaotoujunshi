# Migrate the three ports to one Flutter codebase

Date: 2026-10-03 · Scope: the three ports under `integrations/` → one Flutter codebase, three target platforms

This plan supersedes the pre-decision design draft. It is the input to the `to-spec` / `to-tickets`
stage, so it is deliberately written in a shape that can be cut into tickets.

Decision records (durable, authoritative): [`docs/adr/0007`](../adr/0007-one-flutter-codebase-for-all-three-ports.md)
through [`docs/adr/0014`](../adr/0014-declare-a-port-replaced-only-after-device-acceptance.md).
Vocabulary: `GLOSSARY.md`, section "Flutter migration layer (target state)".

---

## 0. One-page conclusion

Collapse the three ports (Kotlin / Python+PySide6 / Python+PyObjC, 16,096 lines in total) into one
Flutter codebase under `integrations/jev_flutter/`. Platform capability narrows to **ten Dart
interfaces**, which all three port implementation packages must answer for; the business and UI
layers merge into one. macOS pilots first, Windows follows, Android last, and each port is tagged
and deleted as soon as it passes acceptance.

**The driver is deduplication and unified iteration** — the only reason the feasibility study
endorsed. This plan therefore commits to no schedule; it defines shape, order and acceptance
criteria only.

---

## 1. Non-negotiable constraints

| # | Constraint | Source | Consequence for this plan |
| --- | --- | --- | --- |
| C1 | Shared material is read as files at runtime, included as whole directories, and a missing file is an error — never a fallback | ADR-0005 / ADR-0006 | **Not through Flutter assets** (asset directory declarations do not recurse), see §7 |
| C2 | Chat text never lands on disk and is never uploaded | `PRIVACY.md` | Captured frames and OCR text stay in memory only; fixtures must be synthetic (ADR-0011) |
| C3 | Injection writes a draft and never sends | `PRIVACY.md` + all three ports | There is **no** `send` in the `TextInject` contract, and no commit may add one |
| C4 | Each port carries its own upstream licence and attribution obligations | root `NOTICE`, each port's `LICENSE`/`NOTICE` | Translating into Dart is still a derivative work; the obligations move with the code |
| C5 | Android's `AccessibilityService` stays in Kotlin | Platform fact | Flutter cannot host a system-bound service |
| C6 | The repository root entry allowlist is hard-validated | `scripts/validate_layout.py` | This plan **adds no root entry** |
| C7 | **Never released; there are no existing users** | Confirmed 2026-10-03 | **No upgrade migration, no backward compatibility, no legacy data reads**; the storage format is ours to choose |
| C8 | Platform existence must not become a silent branch | ADR-0009 | Where a capability does not apply, the implementation throws; it must not return a null, an empty collection or a default |

---

## 2. Decision summary

| # | Decision | ADR |
| --- | --- | --- |
| 1 | One Flutter codebase for all three ports, Android keeps a Kotlin system layer | [0007](../adr/0007-one-flutter-codebase-for-all-three-ports.md) |
| 2 | Shared material **does not go through Flutter assets**; each platform copies the directory at build time, Dart reads it through `SharedPayload` | [0008](../adr/0008-keep-the-shared-payload-out-of-flutter-assets.md) |
| 3 | Ten capability interfaces in one interface package with three implementation packages; the platform owns *when*, the domain owns *what* | [0009](../adr/0009-capability-contract-as-the-only-cross-port-boundary.md) |
| 4 | The memory store reimplements only the subset actually in use, keeping consent/pause/undo and the capacity cap | [0010](../adr/0010-reimplement-only-the-used-memory-store-subset.md) |
| 5 | Perception calibration is pinned by **synthetic fixtures** in CI; a one-off double-run comparison covers the migration window | [0011](../adr/0011-pin-the-perception-calibration-with-synthetic-fixtures.md) |
| 6 | Only the bubble and the panel get their own window; everything else is a route in the main window | [0012](../adr/0012-only-the-bubble-and-panel-are-their-own-window.md) |
| 7 | The Windows native bridge (capture + input + OCR) runs out of process | [0013](../adr/0013-run-the-windows-native-bridge-out-of-process.md) |
| 8 | A port is replaced only when all three acceptance conditions hold; then it is tagged and deleted, and each port runs its own gate experiment | [0014](../adr/0014-declare-a-port-replaced-only-after-device-acceptance.md) |

---

## 3. Repository placement and project structure

**Placement: `integrations/jev_flutter/`.** `integrations` is already registered as the `app` layer,
so a new directory there needs **zero changes to `validate_layout.py`** and no fifth layer name.

```
integrations/jev_flutter/
  pubspec.yaml                     # workspace root; name: _ , publish_to: none
  analysis_options.yaml
  apps/miaotou_app/                # the single Flutter app, three targets
    pubspec.yaml                   # resolution: workspace
    lib/                           # assembly, routing, window orchestration, UI
    android/  macos/  windows/     # native runner + retained Kotlin/Swift/C++
  packages/
    miaotou_domain/                # pure Dart: judging, prompt, scoring, trend/CSV, profile, knowledge logic
    miaotou_capabilities/          # the ten interfaces (pure Dart, no plugin)
    miaotou_capabilities_android/
    miaotou_capabilities_macos/
    miaotou_capabilities_windows/
  fixtures/                        # synthetic material + expected output (ADR-0011)
  tool/
    sync_shared_payload.dart       # build-time shared-material sync
```

- Dart 3.13+ / Flutter stable 3.47+. Official **pub workspaces** (root `workspace:` plus
  `resolution: workspace` in each package); the `packages/*` glob needs Dart 3.11+, which is
  satisfied. **No Melos.**
- Dependency direction: `apps/miaotou_app → miaotou_capabilities_<platform> → miaotou_capabilities`;
  `miaotou_domain` has no platform dependency at all.
- Because `miaotou_domain` has no platform dependency, the whole of its logic is testable with
  `dart test` in milliseconds.

> Trap: `validate_layout.py` reads root entries from `git ls-files`. A new project must be `git add`ed
> before the script runs, or a green local result is falsely green.

---

## 4. The capability contract (the core deliverable)

**Ten interfaces, one interface package, three implementation packages.** Every method must be
answered for on every port: implement it, or throw.

```dart
// miaotou_capabilities

// —— platform group ——
final class CaptureFrame {
  final Uint8List pixels;      // memory only, never on disk (C2)
  final int width, height;
  final double scaleX, scaleY; // bitmap / captured region (Android captures a window, not the screen)
  final int originX, originY;  // the captured region's origin on screen
}
sealed class CaptureOutcome {}
final class CaptureOk extends CaptureOutcome { final CaptureFrame frame; }
final class CaptureFailed extends CaptureOutcome { final int code; final String message; }

abstract interface class ScreenCapture {
  Future<CaptureOutcome> capture({String? targetWindowId});
  /// Returns null when nothing is found; never a fallback window.
  Future<String?> findTargetWindow();
}

/// Android only (accessibility node tree); both desktop ports throw UnsupportedError explicitly.
abstract interface class UiTreeReader {
  Future<ChatUiSnapshot> readActiveChat();
}

abstract interface class Ocr {
  /// The caller supplies the language order.
  Future<List<OcrLine>> recognize(CaptureFrame frame, {required List<String> languages});
}

/// Inject only, never send (C3). There is no send, and none may be added.
abstract interface class TextInject {
  /// The result must carry a "verified landing" boolean; "I sent it, it should have arrived" is not acceptable.
  Future<InjectResult> inject(String text, {required InjectTarget target});
}

abstract interface class FloatingPanel {
  Future<void> show({required PanelPlacement placement});
  Future<void> hide();
  Future<void> hideForCapture();      // must be called before a capture
  Future<void> restoreAfterCapture();
  Future<void> setFocusable(bool value);  // the review page needs an IME
  Stream<PanelEvent> get events;
}

// —— material group ——
abstract interface class SharedPayload {
  /// Keys are repository-root-relative paths, the same convention as payload-map.json.
  Future<Uint8List> read(String repoRelativePath);
  Future<List<String>> list(String repoRelativeDir);
}

// —— storage group ——
abstract interface class Preferences { /* preferences */ }
abstract interface class SecretStore { /* credentials: macOS Keychain / Windows Credential Manager / Android Keystore fallback */ }
abstract interface class KnowledgeStore { /* knowledge base (Android-only before the union) */ }
abstract interface class MemoryStore { /* memory store, see ADR-0010 */ }
```

### 4.1 Boundary: the platform owns timing, the domain owns decisions

Retained **inside the platform implementations** (all measured assets, not migrated):

| Item | Source |
| --- | --- |
| Screenshot 1s rate limit + 1→30s exponential backoff + 3s watchdog | `capture/ocr/ScreenCapture.kt:182-199` |
| Hide the panel for 120ms before a capture so the compositor drops its frame | `overlay/OverlayController.kt:559` |
| "Stick to the window chosen last time" instead of re-selecting each frame | Windows `app/capture.py`, mac `vendor/perception.py` |
| Review-focus retry 20×50ms, HTTP backoff ×3 | `ChatCaptureService.kt:857`, `jev/HttpJson.kt:44` |
| Un-minimise without stealing focus | Windows `app/capture.py:48-51` (`IsIconic`→`ShowWindow(4)`+`SetWindowPos(SWP_NOACTIVATE)`) |

Moving into the **domain layer**: on receiving a snapshot → judge → draft → score candidates →
trend/CSV → assemble the prompt → profile and knowledge logic.

### 4.2 Key trade-offs

| Trade-off | Decision | Reason |
| --- | --- | --- |
| Is the window id handed back and reused? | The caller holds it and passes it back | WeChat 4.x exposes several equally sized windows; re-selection makes the target jump |
| `UiTreeReader` on the desktop ports | Throw explicitly | An explicit statement beats a silently empty snapshot (C8) |
| Does `TextInject` expose read-back verification? | Not as a member, but the result must carry "verified landing" | The three ports verify in three different ways; exposing it would leak platform detail |
| Windows local OCR | **Inside the native bridge** (Rust/C++ over ONNX Runtime, reusing RapidOCR's models and post-processing) | OCR is a platform-native capability on all three ports already; DBNet post-processing needs contour detection and a perspective crop with no Dart equivalent; folding it into the existing WGC bridge avoids a second runtime |
| Unified speaker token | `me` / `other` | Done on the old stacks before the freeze, see §10 M1 |

---

## 5. Per-port implementation inventory and hand-written surface

`✅ reused/off-the-shelf` `⚠️ must be written` `⛔ not applicable on this platform`

| Capability | Android | macOS | Windows |
| --- | --- | --- | --- |
| `ScreenCapture` | ✅ keep Kotlin (`takeScreenshotOfWindow` API34+ / `takeScreenshot` API30+) | ⚠️ **must be rewritten**: `CGWindowListCreateImage` is obsoleted in macOS 15, move to **ScreenCaptureKit** (`SCScreenshotManager.captureImage` + `SCContentFilter(desktopIndependentWindow:)`) | ⚠️ hand-write a native bridge wrapping `windows-capture` **2.0** (the existing code uses the 1.x API and needs rewriting) |
| `UiTreeReader` | ✅ keep Kotlin (`ChatAppAdapter`, 510 lines, a measured asset) | ⛔ | ⛔ |
| `Ocr` | ✅ keep Kotlin: ML Kit `text-recognition-chinese` (bundled model) | ✅ Apple Vision (thin hand-written Swift plugin; community packages are poorly maintained) | ⚠️ ONNX Runtime + RapidOCR pre/post-processing inside the native bridge |
| `TextInject` | ✅ Kotlin `ACTION_SET_TEXT`/`ACTION_PASTE` + read-back | ✅ `AXUIElementSetAttributeValue` + `AXValue` read-back (`dart:ffi`). Keep `MIN_INPUT_AREA = 10000.0` | ⚠️ user32/kernel32 inside the native bridge: `AttachThreadInput`→`SetForegroundWindow`, `SetCursorPos`+mouse events, clipboard, `Ctrl+End`/`Ctrl+V`. Keep all four race guards |
| `FloatingPanel` | ⚠️ **hand-write a Kotlin plugin** (`flutter_overlay_window` has been unmaintained for 15 months): `TYPE_APPLICATION_OVERLAY` + dynamic flag switching + edge snapping + position persistence; the Flutter content renders in a **second engine** (`FlutterEngineGroup`) | ⚠️ `MainFlutterWindow` → `NSPanel` + `.nonactivatingPanel` + `.floating` + `canJoinAllSpaces` | ✅ `window_manager`: frameless + always-on-top |
| `SharedPayload` | ✅ **reuse the existing Gradle `Sync` task + AGP recursive packaging unchanged** | ⚠️ read real files under `Contents/Resources/` | ⚠️ read real files under `_internal/` next to the executable |
| Storage quartet | ⚠️ `Preferences` can reuse `SharedPreferences`; `SecretStore` is new work (today it uses private storage in `Prefs.kt`) | ✅ Keychain (the `/usr/bin/security` route already exists in `credentials.py`); `Preferences` reuses `settings.local.json` | ⚠️ today it uses the registry (`HKCU\Environment`); needs a proper credential store |

**All the hand-written surface lands on Windows and macOS capture**; Android needs no new platform
code at all beyond the self-written plugin.

### 5.1 Android specifics

- **Retained Kotlin, ~1718 lines**: `ChatCaptureService`(881) + `ChatAppAdapter`(510) +
  `ScreenCapture`(214) + `MlKitOcr`(113).
- **New**: roughly 150–250 lines of MethodChannel/EventChannel exits plus a `FlutterView` host, plus
  the self-written overlay plugin (estimated 300–500 lines).
- **The data flow is a push, not a pull**: `ChatCaptureService` is driven by `TYPE_WINDOW_CONTENT_CHANGED`.

  ```
  EventChannel  miaotou/ingest   (Kotlin → Dart): onSnapshot / onConversation / onCaptureError
  MethodChannel miaotou/control  (Dart → Kotlin): bindConversation / setOverlayFlag / hideForCapture / restore
  ```

- **The ADR-0002 guardrails**: `ConversationRef(pkg, title?)` — either part may be missing and
  **missing is legal**; the header **must not fall back to a bare package name**; the read-only state
  is derived (the analysed conversation ≠ the current conversation), and **the decision belongs to
  `ChatCaptureService` while the panel only renders**. This is the rule most likely to be simplified
  away during a Dart rewrite.

### 5.2 macOS specifics (the pilot port)

- **Capture must move to ScreenCaptureKit** — this has nothing to do with Flutter; the current
  implementation is already on a deprecated path.
- **New risk**: macOS 15+ re-prompts for screen-recording permission roughly monthly, and the app
  cannot answer for the user. Mitigations are the system picker, an MDM profile, or asking Apple for
  an entitlement.
- Retained as-is: the layout constants and folded-row merging in `vendor/perception.py`(586), and
  `MIN_INPUT_AREA` in `vendor/fill.py`(336).
- The relationship between `NSApplicationActivationPolicyRegular` and "does not steal focus" has to be
  confirmed in gate experiment B.

---

## 6. Desktop window model and state ownership

**Only the bubble and the panel get their own window; everything else (settings / detail / K-line /
knowledge base) is a route in the main window.**

```
┌─ main window (hideable, but resident) ────────┐
│  capture loop · OCR · LLM client · credentials │
│  · shared payload                              │
│  · read-only derivation (ADR-0002's owner)     │
│  settings / detail / K-line / knowledge = routes│
└──────────────┬────────────────────────────────┘
               │ snapshot down / commands up (the only cross-isolate contract)
        bubble + panel window (second engine)
        holds transient presentation state only: drag landing, expanded/collapsed
```

- **The main window is the only capability holder**, and closing it is not quitting; otherwise closing
  the main window would take the capture loop and the credentials with it while the panel stays on screen.
- **The read-only state is derived in the main window** and the panel only renders it — the desktop
  counterpart of ADR-0002 (on Android the owner is `ChatCaptureService`).
- **The cost must be stated plainly**: detail and K-line are no longer separate windows you can drag
  next to the chat. That is a user-visible product change.
- Fallback: if panel-snapshot serialisation turns out to be unacceptable in practice, fold the panel
  into a main-window overlay as well — that is a product decision, not a technical limit.

---

## 7. Loading the shared material

| Platform | Implementation | Reuses the existing pipeline? |
| --- | --- | --- |
| Android | The existing `copySharedMaterial` (`Sync`, not `Copy`) + AGP recursive packaging; Dart asks `AssetManager` through a MethodChannel | ✅ Reused as-is, not one line changed |
| macOS | Read real files under `.app/Contents/Resources/` | ✅ Keeps "read files at runtime" literally |
| Windows | Read real files next to the executable | ✅ Same |

The guard moves with it: the counterpart of the existing
`tests/test_jev_mac.py::test_packaged_mac_tree_contains_every_runtime_file` is —
**every key ever requested from `SharedPayload.read()` must really exist in the packaged artifact.**
Otherwise a missing file degrades from "the build fails" into "the user only finds out after clicking
the button".

---

## 8. Testing and fixtures

| Category | Today | After the migration |
| --- | --- | --- |
| Pure logic | `tests/*.py`, 108 cases (9 of 12 files cover mac) | **Rewritten as `dart test`**, running against `miaotou_domain` |
| Android JVM unit tests | 5 classes (196 lines) | **All retained**; the code under test is still Kotlin |
| Perception calibration | None (constants and comments only) | **New synthetic fixtures** (rendered images and node trees with fake nicknames and fake copy, plus expected output), committed and run in CI |
| Migration-window comparison | — | Dart and Python run the same fixtures side by side, **one-off**; the script is deleted with the migration |
| widget / integration | None | New (panel rendering, settings page) |

**The key distinction** (written into ADR-0011): a fixture pins the behaviour of **one implementation
across time**; a conformance test is the thing ADR-0005 rejected — "are three implementations
identical at one instant". The former does not reopen the latter.

**Fixtures must be synthetic**: a chat screenshot is chat text, and committing one would contradict
`PRIVACY.md` outright. The cost is that synthetic material cannot cover the real client's rendering
quirks — **device acceptance remains mandatory**.

---

## 9. Packaging / CI / licensing / privacy

**CI** (new jobs in `platform-build.yml`):

| job | runner | artifact |
| --- | --- | --- |
| `flutter-android` | ubuntu-latest | `miaotoujunshi-android-debug.apk` |
| `flutter-windows` | windows-latest | `miaotoujunshi-windows-preview.zip` |
| `flutter-macos` | macos-latest | `miaotoujunshi-mac.zip` (signed + notarised `.app`) |

- Use `subosito/flutter-action`; pub dependencies **must** be fetched online — no `--offline`.
- Add `integrations/jev_flutter/**` to the `paths` filter; the old port paths stay until each port is
  deleted (dual-track).
- Keep the existing artifact naming. The mac CI artifact name (`miaotoujunshi-mac-source`) differs from
  the inner zip name; `-source` stops being true once a real `.app` is produced, so **fix it during
  that port's promotion**.
- The release job's note that "the macOS artifact is a source package and needs Python and uv" has to
  be rewritten — that is one of the main benefits of this migration.

**Distribution and self-update**: all three ports **unify on "check GitHub Releases + notify"**, with
no automatic replacement. macOS ships a signed, notarised `.app`; Windows ships a zip; Android ships
an APK.

**Licensing**: new third-party components (Flutter SDK BSD-3 plus each pub dependency, onnxruntime MIT,
the RapidOCR model licence) **go into `integrations/jev_flutter/NOTICE` line by line**; the three
upstream obligations move across, so the new NOTICE must cover three upstreams plus the Flutter
ecosystem. **Payoff**: the Windows package no longer bundles `PySide6-Fluent-Widgets`, so **the GPLv3
constraint on the release package disappears with it**.

**PRIVACY.md**: rewrite the platform detail in the "reading and requests" section (Keychain / Android
accessibility and private storage / Windows Credential Manager), and restate that **the memory store's
consent, pause and capacity cap are now promised by this repository** (ADR-0010); delete stale lines
such as "the Windows installer has not yet been verified on real hardware".

---

## 10. Sequence and milestones

### M0 Gate experiments (B only for now)

| # | Experiment | What it answers | If it fails |
| --- | --- | --- | --- |
| **B** | macOS: start a Flutter panel in an `NSPanel` with `.nonactivatingPanel`; verify "tapping the panel does not steal WeChat's focus" and "the Chinese IME works inside the panel" | Whether a desktop floating window plus IME can work at all | Change the pilot port, or abandon the migration |
| A | Android: the self-written plugin puts an `rgba(255,255,255,0.6)` panel over WeChat | Whether translucency and z-order can work | Android does not migrate |
| C | Windows: a minimal native bridge wrapping `windows-capture` 2.0, capturing an occluded window continuously | Whether the hand-written surface is deliverable | Windows' schedule is out of control |

A runs before Android starts; C runs before Windows starts. **B is currently the only experiment on
the critical path.**

### Milestones

| Stage | Content | Exit condition |
| --- | --- | --- |
| **M0** | Gate experiment B | Passes |
| **M1** | **On the old stacks**, unify the speaker token to `me`/`other` (the last functional change before the freeze) | 108 cases green + one device-acceptance rerun |
| **M2** | Repository skeleton: `integrations/jev_flutter/` + pub workspace + the ten interfaces + the `SharedPayload` invariant test | `flutter test` / `dart test` / `validate_layout.py` all green |
| **M3** | macOS end to end: ScreenCaptureKit capture → Vision OCR → domain → panel → AX injection | The full acceptance flow, equivalent to the old port, completed on a real device |
| **M4** | `miaotou_domain` complete + double-run comparison against the Python implementations | Same verdicts on the same fixtures |
| **M5** | macOS promoted → tag → delete `integrations/jev_mac` and its CI job | All three conditions hold (§10.1) |
| **M6** | Gate experiment C → Windows promoted (native bridge: WGC + input + OCR) | `integrations/jev_windows` deleted; GPLv3 constraint lifted |
| **M7** | Gate experiment A → Android promoted (retained Kotlin + self-written overlay plugin) | `integrations/jev_android` deleted |
| **M8** | Wrap-up: retire the Python tests and the comparison script, clean up the dual-track CI, fix the mac artifact name | — |

**Why this order**: macOS has the largest packaging payoff and the smallest capability surface (even
though capture must be rewritten); Windows carries the heaviest hand-written surface, so it goes in the
middle; Android needs no new platform code, but its overlay is the highest risk — and **its real
blocker today is "it cannot capture WeChat's chat area"** — which is unrelated to the UI framework, so moving
to Flutter does not advance it.

### 10.1 Promotion criteria (all three must hold)

1. The new port completes, on a real device, the acceptance flow described in the old port's `README.md`;
2. The synthetic fixtures are all green;
3. Every capability that belongs to that port in the union baseline **works** — including features the
   port never had.

Satisfying them means: tag the git revision → delete the directory → remove that port's CI job, `paths`
filter entry and README section in the same change. **The double-run comparison must finish before that
port is deleted.**

---

## 11. Risk register

| # | Risk | Impact | Trigger | Mitigation |
| --- | --- | --- | --- | --- |
| R1 | A translucent Android overlay does not work under Flutter | Android cannot migrate | Experiment A fails | Retry with transparent rendering mode; if it still fails, migrate only the two desktop ports and leave Android on Kotlin |
| R2 | macOS capture loses permission behaviour or accuracy after the ScreenCaptureKit move | The pilot fails | Experiment B + device acceptance | Keep the original layout constants and algorithm structure; evaluate the permission-prompt problem separately |
| R3 | Perception calibration loses accuracy when redone | Recognition rate regresses | Device acceptance fails repeatedly | Compare fixture by fixture; **any change that touches it needs its own ticket** |
| R4 | The Windows native bridge's hand-written surface overruns (WGC + input + OCR) | Schedule overrun | Experiment C results | Split the milestones finer; OCR can temporarily fall back to the cloud path (the tension with C2 has to be reconfirmed) |
| R5 | Dual-track maintenance during the migration | Cost stacks instead of replacing | Two CIs, two sets of bugs | The old ports take blocking-level fixes only; promote and delete, never defer to the end |
| R6 | A licensing obligation is missed | Compliance risk | The new NOTICE does not cover an upstream or the Flutter ecosystem | Compare line by line against the root `NOTICE` and the three ports' `NOTICE` |
| R7 | Synthetic fixtures cannot cover the real client's rendering | Falsely green | WeChat/QQ redesigns | Fixtures are a regression net only; device acceptance stays a promotion condition |
| R8 | Panel snapshot serialisation across isolates costs too much | Desktop experience regresses | Measured latency | Take ADR-0012's fallback: fold the panel into a main-window overlay |

---

## 12. Explicitly out of scope (non-goals)

- **iOS**: the system forbids cross-app screen reading and driving another app's text field, so the
  core path cannot exist. This is unrelated to Flutter — a Swift rewrite could not do it either.
- **Automatic update (downloading and replacing itself)**: all three ports unify on "check + notify".
- **Migrating existing user data**: never released, no users (C7).
- **Cross-port contract conformance assertions**: ADR-0005's "no mechanical validation" decision is not
  reopened.
- **Driving Kotlin/Swift/C++ to zero**: the platform capability layer always exists; the goal is only
  to make it the one place that must differ per port.

---

## 13. Items to settle before implementation — all four settled

Every item below was open when this plan was written. All four have since been
decided by the port that needed them, and the decision is recorded beside the item
so a reader can tell settled from pending without re-reading the commit history.

1. **The concrete design of Windows shared-memory frame transfer** — the current implementation copies
   every frame through a queue (a 2560-wide raw frame is about 20 MB; debug frames are capped at ≤1100).
   The Flutter side needs shared memory, and the design must be settled before Windows starts.
   *Settled by the Windows bridge (#17): frames cross the process boundary through
   shared memory instead of a queue copy, inside the same out-of-process bridge as
   capture and synthetic input.*
2. **The method set of the self-written Android overlay plugin** — once aligned with the
   `FloatingPanel` interface, it still needs the flag combinations, edge-snap parameters and position
   persistence keys defined.
   *Settled by #21: the plugin answers for `FloatingPanel` directly — runtime focus
   flags, persisted edge snapping, and the ball's position kept separate from the
   keyboard-safe expanded geometry. The shared placement and edging logic moved into
   `miaotou_capabilities`, so macOS no longer carries a private copy.*
3. **How to handle the macOS screen-recording permission prompt** — the system picker, an MDM profile,
   or an entitlement request to Apple: pick one or accept the prompt.
   *Settled by [ADR-0016](../adr/0016-ask-for-screen-recording-permission-and-accept-the-re-prompt.md):
   accept the re-prompt and ask for the permission from inside the app. A missing
   grant preflights into a coded failure, never an empty result.*
4. **Old-port tag naming** (suggested: `legacy/<port>-final`).
   *Settled as `archive/jev-<port>-<language>-final` — `archive/jev-mac-python-final`,
   `archive/jev-windows-python-final`, `archive/jev-android-kotlin-final`, all three
   pushed to the remote. `archive/` reads as "this is history" rather than "still
   supported somewhere", and the language is part of the name because what was
   archived is an implementation, not the platform: the platform outlives it.*

---

## Appendix: ADR index

| ADR | Title |
| --- | --- |
| [0007](../adr/0007-one-flutter-codebase-for-all-three-ports.md) | Build all three ports from one Flutter codebase |
| [0008](../adr/0008-keep-the-shared-payload-out-of-flutter-assets.md) | Keep the shared payload out of Flutter assets |
| [0009](../adr/0009-capability-contract-as-the-only-cross-port-boundary.md) | Make the capability contract the only cross-port boundary |
| [0010](../adr/0010-reimplement-only-the-used-memory-store-subset.md) | Reimplement only the memory-store subset the app uses |
| [0011](../adr/0011-pin-the-perception-calibration-with-synthetic-fixtures.md) | Pin the perception calibration with synthetic fixtures |
| [0012](../adr/0012-only-the-bubble-and-panel-are-their-own-window.md) | Give only the bubble and the panel their own window |
| [0013](../adr/0013-run-the-windows-native-bridge-out-of-process.md) | Run the Windows native bridge out of process |
| [0014](../adr/0014-declare-a-port-replaced-only-after-device-acceptance.md) | Declare a port replaced only after device acceptance passes |
| [0015](../adr/0015-unify-the-speaker-token-and-leave-the-model-vocabulary-at-the-boundary.md) | Unify the speaker token and leave the model vocabulary at the boundary |
| [0016](../adr/0016-ask-for-screen-recording-permission-and-accept-the-re-prompt.md) | Ask for screen-recording permission from the app and accept the re-prompt |
