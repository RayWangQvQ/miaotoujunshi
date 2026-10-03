# jev_flutter — one application, three ports

The three platform ports are being replaced by one Flutter application built for
Android, Windows and macOS from a single codebase. The decisions behind that are
`docs/adr/0007` onwards; this file is how to build and test what is here today.

**Status: the skeleton.** There is a workspace, a contract and three build
targets. There is no capture, no OCR, no panel and no window — see *What is not
here yet* at the bottom for which ticket brings each.

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
| The Windows native bridge and implementations | #17–#19 |
| The Android overlay plugin and implementations | #21–#23 |
| A `tool/` directory and a `fixtures/` directory | #15, #19 — written together with the build step that calls them and the fixtures that use them, so that neither is scaffolding nothing invokes |
| The `flutter-*` CI jobs | the packaging ticket; until then this tree is built by hand |
