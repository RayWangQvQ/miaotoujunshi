# app — one application, three build targets

One Flutter application built for Android, Windows and macOS from a single
codebase. The decisions behind the migration are `docs/adr/0007` onwards, and
`docs/plans/0001-flutter-migration.md` records the plan it was executed under;
this file is how to build and test what is here today. The directory is called
`app/` because it *is* the app layer, which is the layer name the root allowlist
registers for it (`docs/adr/0017`).

**Status: all three build targets are promoted.** Each port replaced its old
implementation and was deleted in the same change that tagged it — macOS
(`#16`), Windows, Android (`#24`) — under
`archive/jev-<port>-<language>-final`. The shared workspace and the capability
contract are live: macOS, Windows and Android each carry their own capability
package, Windows has its process-isolated capture/OCR/input bridge plus a
second-engine frameless floating panel, and Android pushes accessibility
snapshots through its retained Kotlin service and persists its four stores
through app-private Android storage. Two items remain tracked separately: verified
Android one-tap fill (#29) and packaging the Windows bridge and its models with
the artifact (#19).

## Layout

```
app/
  pubspec.yaml                  the workspace root; declares every member
  analysis_options.yaml         one lint configuration for the whole tree
  apps/miaotou_app/             the single Flutter application
    lib/main.dart               start-up: pick a capability set, run the app
    lib/src/capability_registry.dart   the only file that asks what OS this is
    lib/src/capability_report.dart     what this build target can do, asked not assumed
    android/ macos/ windows/    the three runners
  packages/
    miaotou_capabilities/       the ten interfaces. Pure Dart, no platform
    miaotou_capabilities_<platform>/   one per build target; every member answered for
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
# from app
flutter pub get

# every package's tests, plus the application's widget tests.
# **Which tool runs a package is read from its pubspec, not from this list.** A
# package that depends on the Flutter SDK is a Flutter package: `dart test` runs
# on a VM with no `dart:ui`, so a widget test cannot even be loaded there. That is
# exactly how `flutter.yml` decides, and running all six with `dart test` fails
# the three platform packages with `switch` exhaustiveness errors inside the
# framework, which looks like a code fault and is not one.
(cd packages/miaotou_capabilities        && dart test)
(cd packages/miaotou_domain              && dart test)
(cd packages/miaotou_capabilities_android && flutter test)
(cd packages/miaotou_capabilities_macos   && flutter test)
(cd packages/miaotou_capabilities_windows && flutter test)
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

### Android retained Kotlin bridge

Android remains event-driven. The Kotlin `AccessibilityService` is woken by
window-content changes and pushes snapshots, conversation changes and capture
errors over `miaotou/ingest`; Dart sends binding, overlay, capture, OCR and
verified draft-injection commands over `miaotou/control`. The measured adapter,
screenshot and ML Kit sources live directly in the Android capability plugin, so
capture pacing and per-app node paths remain in retained Kotlin rather than being
rewritten in Dart.

Conversation read-only state is computed by the service and sent as presentation
state. Either identity half may be absent, and Kotlin supplies the display label
so the panel never falls back to rendering a raw package name.

The same plugin exposes one storage channel. Preferences use private
`SharedPreferences`; credentials are AES-GCM encrypted with an Android Keystore
key; knowledge and memory documents use atomic app-private file writes. The
payload is read through `AssetManager`.

## The shared payload does not travel through Flutter assets

`goutoujunshi/` and `miaotoujunshi/` are read from disk at runtime on all three
build targets, and each platform's build copies the tree **whole**. A Flutter `assets:`
entry would not do: an asset directory entry includes only the files directly in
it, so `miaotoujunshi/references/data/*.json` would silently not ship, and adding
a payload file would then need a matching `pubspec.yaml` edit (ADR-0008).

Nothing in `pubspec.yaml` will tell you where the payload comes from — that is the
intended cost of the decision. The answer is this ADR, each platform's build step,
and `packages/miaotou_capabilities/test/shared_payload_invariant_test.dart`, which
fails if anyone declares the payload as an asset.

On Android, the retained `copySharedMaterial` shape is a Gradle `Sync` task wired
into every assets merge. The Flutter domain reads documents below
`goutoujunshi/references/`, so this task expands the old Android port's SKILL-only
copy to the whole upstream tree. The same payload-key validator used by the desktop
packages runs before that merge, so an APK build fails when any runtime key is
missing.

## What remains

The migration is finished, so the backlog table this section used to carry is
gone: the domain (judging, prompts, scoring, trend data), the knowledge base and
memory store, the anti-injection filter, scenario selection, the update check,
the design system, the main-window routing shell and the panel content all live
under `packages/` and `apps/miaotou_app/` today, and each build target carries its
own capability package. Two items are still open and are tracked in GitHub Issues
rather than here:

| Open | Ticket |
| --- | --- |
| Verified Android one-tap fill | #29 |
| Copying the Windows bridge and its RapidOCR models beside the packaged application | #19 |
