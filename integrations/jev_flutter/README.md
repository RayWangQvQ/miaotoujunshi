# jev_flutter — one application, three ports

The three platform ports are being replaced by one Flutter application built for
Android, Windows and macOS from a single codebase. The decisions behind that are
`docs/adr/0007` onwards; this file is how to build and test what is here today.

**Status: macOS promoted; Windows bridge and panel implemented.** The shared
workspace and contract are live, the macOS port is the promoted implementation,
and Windows has its process-isolated capture/OCR/input bridge plus a second-engine
frameless floating panel. General storage, release packaging and all Android
native capabilities are still pending — see *What is not here yet* below.

## Layout

```
integrations/jev_flutter/
  pubspec.yaml                  the workspace root; declares every member
  analysis_options.yaml         one lint configuration for the whole tree
  apps/miaotou_app/             the single Flutter application
    lib/main.dart               start-up: pick a capability set, run the app
    lib/src/capability_registry.dart   the only file that asks what OS this is
    lib/src/capability_report.dart     what this port can do, asked not assumed
    android/ macos/ windows/    the three runners
  packages/
    miaotou_capabilities/       the ten interfaces. Pure Dart, no platform
    miaotou_capabilities_<platform>/   one per port; every member answered for
    miaotou_domain/            pure Dart; platform-free business logic (#7–#10)
```

Dependency direction is `apps/miaotou_app → miaotou_capabilities_<platform> →
miaotou_capabilities`, and `miaotou_domain` depends on the contract and on no
platform package at all. `packages/miaotou_domain/test/dependency_direction_test.dart`
is what keeps the second half of that true.

## Building and testing

Flutter stable 3.47 or newer (Dart 3.13 or newer) is required; the workspace uses
pub workspaces, so the `packages/*` glob needs Dart 3.11+.

```sh
# from integrations/jev_flutter
flutter pub get

# every package's tests, plus the application's widget tests
(cd packages/miaotou_capabilities        && dart test)
(cd packages/miaotou_capabilities_android && dart test)
(cd packages/miaotou_capabilities_macos   && dart test)
(cd packages/miaotou_capabilities_windows && dart test)
(cd packages/miaotou_domain              && dart test)
(cd apps/miaotou_app                     && flutter test)

# one analysis pass over the whole workspace
flutter analyze

# the three targets
(cd apps/miaotou_app && flutter build apk --debug)      # Android
(cd apps/miaotou_app && flutter build macos --debug)    # macOS
(cd apps/miaotou_app && flutter build windows --release) # Windows, on Windows
```

A Windows build cannot be produced on macOS or Linux; that leg is only ever
exercised on a Windows host.

### Windows floating panel

At startup the Windows runner creates the 56px floating ball in a second Flutter
engine. The window is frameless, always on top, omitted from the taskbar and
marked `WS_EX_NOACTIVATE` until the user enters an editable draft. Dragging snaps
the window to the nearest display edge and stores its last bounds in
`%LOCALAPPDATA%\妙投军师\panel-placement.json`.

The panel isolate receives only serialized `PanelFrame` snapshots and sends only
`PanelCommand` values through `desktop_multi_window`; capabilities and session
state remain in the primary engine. A real Windows host is required to validate
focus handoff and system IME behavior.

### Building the Windows bridge

The Windows package's capture, OCR and text injection run in a separate Rust
process (`packages/miaotou_capabilities_windows/native_bridge`) so a WGC or ONNX
Runtime fault cannot terminate Flutter. On Windows with the Rust MSVC toolchain:

```powershell
cd packages/miaotou_capabilities_windows/native_bridge
cargo build --release
$env:MIAOTOU_WINDOWS_BRIDGE = (Resolve-Path target/release/miaotou_bridge.exe)
$env:RAPIDOCR_MODEL_DIR = "C:\path\to\ppocrv5-ch-mobile-models"
```

The command pipe carries newline-delimited JSON metadata only. Frames cross the
process boundary through named shared memory. OCR uses the local
`ppocrv5-ch-mobile` RapidOCR model set with crate downloads disabled; the bridge
never fetches a model or sends pixels to a network service. #19 owns copying the
bridge and model files beside the packaged application.

Because the application is handed its capabilities rather than looking for them
(`lib/main.dart` does the one lookup, in `capability_registry.dart`), the whole
of it runs in a widget test against the in-memory implementation — see
`apps/miaotou_app/test/capability_report_test.dart`. No device, no window server
and no chat application are involved.

## The shared payload does not travel through Flutter assets

`goutoujunshi/` and `miaotoujunshi/` are read from disk at runtime on all three
ports, and each platform's build copies the tree **whole**. A Flutter `assets:`
entry would not do: an asset directory entry includes only the files directly in
it, so `miaotoujunshi/references/data/*.json` would silently not ship, and adding
a payload file would then need a matching `pubspec.yaml` edit (ADR-0008).

Nothing in `pubspec.yaml` will tell you where the payload comes from — that is the
intended cost of the decision. The answer is this ADR, each platform's build step,
and `packages/miaotou_capabilities/test/shared_payload_invariant_test.dart`, which
fails if anyone declares the payload as an asset.

## What is not here yet

| Missing | Ticket |
| --- | --- |
| The domain: judging, prompts, scoring, trend data | #7, #8 |
| Knowledge base logic and the memory store | #9 |
| Anti-injection filter, scenario selection, update check | #10 |
| The design system and the main-window routing shell | #11 |
| Panel content and the read-only derivation | #12 |
| The macOS implementations | #14, #15 |
| Windows general storage and packaged bridge/models | #19 |
| The Android overlay plugin and implementations | #21–#23 |
| A `tool/` directory and a `fixtures/` directory | #15, #19 — written together with the build step that calls them and the fixtures that use them, so that neither is scaffolding nothing invokes |
| The `flutter-*` CI jobs | the packaging ticket; until then this tree is built by hand |
