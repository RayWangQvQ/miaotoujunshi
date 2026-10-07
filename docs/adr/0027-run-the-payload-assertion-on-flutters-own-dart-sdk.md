# Run the payload assertion on Flutter's own Dart SDK

- Status: accepted
- Date: 2026-10-07

## Context

ADR-0008 replaced a runtime allowlist with a build-time assertion: every key the
material interface can request must be present in the packaged tree, or the
package step fails. That assertion became a script, and all three platform builds
run it — macOS from the payload sync build phase, Windows from the packaging step,
Android from the Gradle task that fills `assets/`.

Its interpreter was Python 3, and nothing else in this product asks for Python. No
artifact contains it (ADR-0010 decision 5), and no Dart, Swift, Kotlin or Rust code
calls it. It was Python because the guard it replaced was a Python test in the
pre-migration tree, and the language was never decided — it was inherited.

That inheritance has a cost with no counterpart. A second toolchain has to be
installed before a package can be built; the Windows packaging step *requires* it
(`find_package(Python3 REQUIRED COMPONENTS Interpreter)`), so a machine without it
cannot produce a Windows package at all; and it is the one build input no version
file in this repository pins.

Meanwhile the SDK that every one of those three builds is already running on is
Dart: the application is Dart, the SDK ships with Flutter, and each build is
started by the Flutter tool.

Two properties have to survive whatever changes here: the key set stays **derived**
from the domain layer's own constants and from `payload-map.json`, never
transcribed (ADR-0008; ADR-0006's four disagreeing member lists are why); and a
missing key fails the **build**, not a button press.

## Decision

**The payload assertion is a Dart script, run by the Dart SDK that ships with
Flutter. Python 3 stops being a build input.**

1. **The script moves to `app/apps/miaotou_app/tool/validate_payload_keys.dart`**,
   from `macos/Runner/`, where it sat beside one of its three callers. It is the
   application's build tool, and the new location is inside the analysis root —
   `app/analysis_options.yaml` excludes `apps/*/macos/**`, so the old location was
   the one hand-written file in the workspace that `flutter analyze` never read.
2. **Behaviour is unchanged, and that is the specification.** The key derivation
   is the same two sources; the exit codes are the same (`0` pass, `1` missing
   keys, `2` usage or a tree that cannot be judged); the messages the build logs
   and the payload tests match are the same strings.
3. **Each build resolves the SDK from the Flutter it is already running**, rather
   than naming a global one:
   - macOS: `${FLUTTER_ROOT}/bin/cache/dart-sdk/bin/dart`. Flutter writes
     `FLUTTER_ROOT` into the generated xcconfig, and the Xcode phase inherits it.
   - Windows: the same VM under `FLUTTER_ROOT`, read from
     `windows/flutter/ephemeral/generated_config.cmake` — the file Flutter writes
     for this build and the one `windows/flutter/CMakeLists.txt` includes.
     **`FLUTTER_ROOT` is not in the top-level `CMakeLists.txt`'s scope**, because
     a subdirectory's variables do not travel up to its parent, so the file is
     included there too rather than the variable being guessed at. A
     `find_program(dart)` fallback covers a configure that ran without it.
   - Android: `flutter.sdk` from `local.properties`, which is where Flutter's own
     Gradle plugin reads it from — so the task works when Gradle is started by
     Android Studio, where the Flutter SDK is not on `PATH`.
   - All three honour a `DART` override, the escape hatch `PYTHON` used to be.
4. **The VM, not the launcher beside it.** `bin/dart` is a shell script on POSIX
   and a `.bat` on Windows, and a process cannot be started from either. Every
   platform names `bin/cache/dart-sdk/bin/dart` instead.
5. **A missing interpreter is an error, not a skip.** The assertion is the whole
   reason the phase exists; a build that could not run it must fail with a message
   that says so, because a phase that quietly stopped asserting is exactly the
   failure mode ADR-0008 removes — reported as a green build.

Python 3 remains the language of the repository's own validation scripts under
`scripts/`, which run in CI or by hand and are part of no artifact. This ADR does
not move them: they are repository governance, not a build input, and nothing in a
package depends on them.

## Rejected alternatives

- **Keep Python and install it in CI.** It is not CI's requirement to satisfy. The
  Windows packaging step requires it on a contributor's machine too, and this is
  what the change removes — one interpreter, for one script, on every machine that
  packages.
- **Reimplement the assertion inside the domain package and call it through
  `dart run <package>`.** It would be library code with unit tests rather than a
  script. Rejected because the build phase would then need a resolved package
  config and a `pub get` before it could assert anything, trading a build-phase
  dependency on the pub workspace for coverage the payload tests already provide
  by running the script for real over a real mirror.
- **Reimplement it in shell with `jq`.** One fewer language, one more install —
  `jq` is not on macOS by default — and the derivation would parse Dart constants
  and JSON with `sed`, which is how a guard stops matching what it reads.
- **Leave the file beside the macOS sync script.** Windows and Android would keep
  reaching into `macos/Runner/` for a file that has nothing to do with macOS, and
  it would stay outside the analysis root (see decision 1).
- **Move the assertion to CI only.** ADR-0008 requires the *package step* to fail,
  and a CI-only check re-creates the failure mode it was written to remove for
  anyone who packages by hand.

## Consequences

- **A machine that can build a package needs the Flutter SDK and nothing else.**
  `find_package(Python3 REQUIRED …)` is gone from the Windows packaging step, and
  the `NOTICE` paragraph that described Python as a build-time tool is rewritten to
  say what is now true.
- **The assertion is analysed and linted** by `flutter analyze` with the rest of
  the workspace — a gain the Python file never had, and the reason its header can
  now be held to the same style as the code it guards.
- **Two builds must resolve a toolchain where they used to name a global one.**
  Both failures are loud and say which variable is missing; neither falls back to
  asserting nothing.
- **The payload tests had to learn the same lesson.** They hand the phase a
  `FLUTTER_ROOT` discovered from the SDK that is running the suite, because the
  phase's environment is deliberately minimal and cannot find one by itself.
- **Three path literals moved together**: the assertion's `_WORKSPACE`, the macOS
  phase's `$SRCROOT/../tool/…`, and the Gradle and CMake references to it.
  ADR-0017's note that two build scripts hold the path as a literal stands; the
  path changed, the cost did not.
- **The mutation harness is realigned rather than reduced.** Its SRCROOT mutation
  now drops the `../tool/` step, and the payload-map mutation targets the Dart
  constant, so both guards are still *seen* to go red.
