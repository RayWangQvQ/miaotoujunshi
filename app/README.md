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
package over one shared module of the code they all use (ADR-0009's 2026-10-07
amendment), Windows has its process-isolated capture/OCR/input bridge plus a
second-engine frameless floating panel, and Android pushes accessibility
snapshots through its retained Kotlin service and keeps its documents in
app-private Android storage. Two items remain tracked separately: verified
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
    miaotou_capabilities/       the eleven interfaces. Pure Dart, no platform
    miaotou_capabilities_<platform>/   one per build target; every member answered for
    miaotou_capabilities_shared/   the modules all three ports use. Pure Dart, no dart:io
    miaotou_domain/            pure Dart; platform-free business logic (#7–#10)
```

Dependency direction is `apps/miaotou_app → miaotou_capabilities_<platform> →
miaotou_capabilities_shared → miaotou_capabilities`, and `miaotou_domain` depends
on the contract and on no platform package at all.
`packages/miaotou_domain/test/dependency_direction_test.dart` is what keeps the
second half of that true, and
`packages/miaotou_capabilities_shared/test/dependency_direction_test.dart` keeps
the shared module platform-free — it is what lets that package's whole suite run
under `dart test` on any machine.

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
# exactly how `flutter.yml` decides, and running all seven with `dart test` fails
# the three platform packages with `switch` exhaustiveness errors inside the
# framework, which looks like a code fault and is not one.
(cd packages/miaotou_capabilities        && dart test)
(cd packages/miaotou_capabilities_shared && dart test)
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
the window to the nearest display edge and reports where it landed as a
`PanelDragged` event; the application is what remembers it, as one
`panel.placement` key in `Preferences` (ADR-0020 decision 4). No port keeps a
store of its own beside its window.

The panel isolate receives only serialized `PanelFrame` and `PanelAppearance`
values and sends only `PanelCommand` values through `desktop_multi_window`;
capabilities and session state remain in the primary engine. A real Windows host
is required to validate focus handoff and system IME behavior.

### The panel's opacity is a setting

The main window's settings page carries a 悬浮面板 slider (40–100%, default 80).
It changes the fill alpha of the panel's one shared colour token,
`cardTheme.color` — the ball, the frame and every candidate card are drawn from
it — and never a native window alpha, which would dim the panel's text and
collide with the `0f`/`1f` the Android port uses to take the panel out of its own
screenshot. The value crosses on a second down-stream beside the frame, and a
drag previews it through `PanelSession` while the release writes it.

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

The same plugin exposes one storage channel. Documents — preferences, knowledge
and memory — cross the shared module's `TextDocuments` seam, so their bytes are
written atomically into app-private files by the same code on all three ports;
credentials are AES-GCM encrypted with an Android Keystore key, which stays in
Kotlin because the Keystore is the device's. The payload is read through
`AssetManager`.

### The two Android permissions are stated, and their pages are one tap away

无障碍权限 and 悬浮窗权限 both have to be granted in the system settings before
this application can read a conversation or draw a card, and neither of them is a
setting the application can apply itself. So they are the first thing on the
settings page: each is a row stating its real state with a 去开启 button that opens
its own system page, and a third row explains 自启动 + 省电无限制 in prose, because
no portable API reads it (ADR-0021; ADR-0016 owes macOS the equivalent surface for
its own two grants).

The state is three-valued rather than a boolean, and the middle value is the one
users actually get stuck in: 无障碍 has two separate facts behind it — the switch
in the system settings, and whether the platform has actually bound the service —
so 「已勾选，但服务未运行」 is a state the app can be in while the switch on screen
says on. It is re-read when the section is built and again whenever the app comes
back to the foreground, because leaving for a system page is the only way either
value ever changes.

`Permissions` is the contract's eleventh interface and the only one that both
reads state and opens a system page; it deliberately has no `request`, since
Android's pages report nothing back. macOS and Windows refuse both members
permanently through `UnsupportedError` and the section says so in one line instead
of drawing two rows that will never change.

### A refusal from the contract is about the port, not about the session

`UiTreeReader` is the member Android answers and the two desktop ports refuse
outright: they read pixels and recover the words through OCR, so there is no node
tree to ask for and never will be. The refusal is an `UnsupportedError` raised by
the implementation, which is exactly what ADR-0009 asks for — a member that
cannot answer says so, rather than returning an empty list nobody can tell from a
real one.

The runtime is the other half and it was missing. `start()` subscribed to
`snapshots` unconditionally, the getter throws synchronously on macOS, and the
exception therefore left `main()` before `runApp` — the process came up owning no
window, which the tool reports as a lost device rather than as a crash. `_readTree()`
and `_subscribeToPushedReads()` are the two doors that close it: a typed refusal
becomes "this port has no tree", while anything else still throws, because a
defect has to stay as visible as a platform fact is quiet (ADR-0023).

Two things follow. On these ports a capture is the way in rather than a fallback,
and an analysis reads the batch the panel already holds instead of re-reading a
tree that is not there — the rule ADR-0022 set for a reviewed batch, arrived at
from the other end.

### A capture is reviewed before it is analysed

A whole-frame capture cannot say what the recogniser thought of its own work — ML
Kit's Chinese recogniser reports no per-line score — so every line of a capture
carries `[OCR待核对]`, and the domain refuses a batch whose every line is doubtful.
That rule is right and it stays. What was missing was the other half: the panel
showed those lines as read-only text under a note asking the user to check the
sides, and there was nothing to check them with (ADR-0022).

So a capture now lands in a review state, and so does any other batch the panel
holds. Each line gets 我 / 对方 / 未定 and a text field, with 并到上一行 and 删除 for
the two ways a whole-frame read gets the shape wrong; the side is pre-filled from
ADR-0019's geometry guess, the note above it is the sentence that says what to
check, and the bottom row becomes 取消 · 识别一次 · 确认. Confirming is what the
gate was waiting for, and the analysis stays the next thing the user asks for. A
standing 核对 button brings the form back once a batch has been confirmed, so a
wrong character noticed afterwards does not cost a second photograph.

Two consequences worth knowing. `PanelFrame.transcript` means "the lines behind the
batch on the panel" rather than "what the last capture read", so a tree read is now
visible before an analysis is asked for. And an analysis reads the batch the user
confirmed rather than re-reading the tree, because re-reading would answer about an
unreviewed copy of it and throw the confirmation away.

A third, from ADR-0024: a confirmed batch is quoted to the model **without** the
per-line `[OCR待核对]`. The source is still a screenshot and the recogniser's score
still travels on the captured lines, but after a person has typed a line the engine
is quoting that person — and leaving the doubt on told the model a batch the user
had just vouched for was unvouched-for, which is answered with no drafts at all. A
verdict with no drafts is a conclusion the domain reaches on purpose
(`RankingStatus.notNeeded`), so the panel keeps the batch on screen when it happens
and leaves the judgement one tap away in 详细分析.

On Android the overlay grows for the review — a ratio of the screen, never shorter
than the ordinary expanded height — because a 380dp window with no `adjustResize` is
a form edited through a keyboard. The desktop windows are 420×620 and keep their
size.

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
own capability package over the shared module. Two items are still open and are
tracked in GitHub Issues rather than here:

| Open | Ticket |
| --- | --- |
| Verified Android one-tap fill | #29 |
| Copying the Windows bridge and its RapidOCR models beside the packaged application | #19 |
