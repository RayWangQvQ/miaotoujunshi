#!/bin/sh
# Sync the shared payload into the bundle, then assert every key is there.
#
# Wired into the Runner target as a `PBXShellScriptBuildPhase` in
# `Runner.xcodeproj/project.pbxproj`, which is the only place on this platform
# where "before the build finishes" is a thing that can fail.
#
# ## Why a build phase and not a Flutter asset
#
# ADR-0008, in full: Flutter's asset directory entry includes only the files
# *directly* inside it, so `assets: - miaotoujunshi/` would not ship
# `miaotoujunshi/references/data/*.json`, and adding a payload file would need a
# matching `pubspec.yaml` edit. That is the exact failure ADR-0005 and ADR-0006
# were written to remove.
#
# ## Why `rsync --delete` and not `cp -R`
#
# ADR-0006 records the accident: `Copy` leaves files in the destination that the
# source no longer has, and a local build then shipped **both** the old and the
# new payload trees at once — 34 shared files where there should have been 17. A
# clean CI checkout would never have shown it, which is what made it worth fixing
# rather than documenting. `--delete` makes the destination a mirror of the
# source, so a renamed payload file cannot leave its predecessor behind to be read
# in preference to it.
#
# ## Why the assertion runs here
#
# AC4 says "asserted at build time", and this is the only place that phrase can
# be true. A runtime check would fail when a user pressed a button, which is the
# failure mode ADR-0008's consequences section says this guard replaces.
#
# ## What this script does NOT do
#
# It does not decide *which* keys matter. That set is derived, in
# `validate_payload_keys.py`, from the domain layer's own constants and from
# `payload-map.json`. Transcribing it here would be the second hand-copied member
# list the whole arrangement exists to eliminate — and a new payload file would
# then need this file edited, which is the invariant being protected.

# ## Why there is no default for `SRCROOT`
#
# `SRCROOT` is required, and its absence is an error. It is set by Xcode on every
# build — the phase in `project.pbxproj` runs `"$SRCROOT/Runner/sync_shared_payload.sh"`,
# so the variable is what the build has already resolved this script's own
# location to — and a guess would be a *different* value from the one the build
# uses, on the one path where being wrong fails every build.
#
# That is not hypothetical. This script used to fall back to
# `$(cd "$(dirname "$0")" && pwd)`, which is `…/macos/Runner` where `SRCROOT` is
# `…/macos`. The fallback made a hand-run succeed — the manual invocation took a
# branch the build never took, printed `payload assertion passed`, and proved
# nothing about the build. The bug it hid was a wrong path to the assertion
# script, so **every** `flutter build macos` died at this phase with
# `can't open file …/macos/validate_payload_keys.py`, while hand-running the same
# script said everything was fine.
#
# So the rule here is the one `native.dart` argues for and `payload.dart` keeps:
# a value that cannot be right must not be guessed, because a guess is
# indistinguishable from an answer at the call site and the call site is a build.

set -eu

# `SRCROOT` is the macOS project directory: `…/apps/miaotou_app/macos`. The two
# scripts of this phase live one level down, in `Runner/`, which is why every
# reference to the other one below spells that `Runner/` step out.
if [ -z "${SRCROOT:-}" ]; then
  echo "error: SRCROOT is not set, so this script does not know where it is." >&2
  echo "       Xcode sets it for every build. To run this by hand, pass the" >&2
  echo "       macOS project directory explicitly:" >&2
  echo "         SRCROOT=\$PWD CODESIGNING_FOLDER_PATH=/path/to/Runner.app \\" >&2
  echo "           sh Runner/sync_shared_payload.sh" >&2
  exit 2
fi

# The repository root. Four levels up from `apps/miaotou_app/macos`, and walked
# rather than hard-coded as `../../../..` so a moved checkout does not silently
# sync the wrong tree — or, worse, an empty one.
#
# The walk is kept, unlike the `SRCROOT` fallback above, and the difference is the
# point: it does not *assume* a value, it **finds and verifies** one. It stops
# only at a directory that holds both payload trees, so a directory that is not
# the repository root cannot be mistaken for it, and a checkout that has moved
# needs no edit. `MIAOTOU_REPO_ROOT` overrides it for a build that vendors the
# payload from somewhere else.
REPO_ROOT="${MIAOTOU_REPO_ROOT:-}"
if [ -z "$REPO_ROOT" ]; then
  PROBE="$SRCROOT"
  while [ "$PROBE" != "/" ]; do
    if [ -d "$PROBE/miaotoujunshi" ] && [ -d "$PROBE/goutoujunshi" ]; then
      REPO_ROOT="$PROBE"
      break
    fi
    PROBE=$(dirname "$PROBE")
  done
fi
if [ -z "$REPO_ROOT" ]; then
  echo "error: cannot find the repository root above $SRCROOT." >&2
  echo "       set MIAOTOU_REPO_ROOT to the checkout that holds miaotoujunshi/." >&2
  exit 2
fi

# Where the payload goes. `CODESIGNING_FOLDER_PATH` is the `.app` bundle Xcode is
# building, and the tree lands beside `Info.plist` where `Bundle.main.resourcePath`
# points. The Dart side reads it from there; see `StoragePaths.resourceRoot()`.
#
# Both spellings are Xcode's. `CODESIGNING_FOLDER_PATH` is the modern one and the
# only one a current build sets; the `BUILT_PRODUCTS_DIR`/`PRODUCT_NAME` pair is
# what older configurations used, and either alone leaves the other half of the
# path undefined. Guessing between them is not an option: an unset pair would
# expand to `/Contents/Resources`, and `mkdir -p` would happily create a
# directory at the filesystem root and then report success having shipped no
# payload at all.
APP_BUNDLE="${CODESIGNING_FOLDER_PATH:-}"
if [ -z "$APP_BUNDLE" ]; then
  if [ -n "${BUILT_PRODUCTS_DIR:-}" ] && [ -n "${PRODUCT_NAME:-}" ]; then
    APP_BUNDLE="$BUILT_PRODUCTS_DIR/$PRODUCT_NAME.app"
  else
    echo "error: neither CODESIGNING_FOLDER_PATH nor BUILT_PRODUCTS_DIR/PRODUCT_NAME" >&2
    echo "       is set, so there is no .app bundle to copy the payload into." >&2
    echo "       Xcode sets CODESIGNING_FOLDER_PATH; to run this by hand, pass the" >&2
    echo "       bundle to copy into:" >&2
    echo "         CODESIGNING_FOLDER_PATH=/path/to/Runner.app" >&2
    exit 2
  fi
fi
RESOURCES="$APP_BUNDLE/Contents/Resources"

for tree in miaotoujunshi goutoujunshi; do
  if [ ! -d "$REPO_ROOT/$tree" ]; then
    echo "error: $REPO_ROOT/$tree does not exist; the payload cannot be synced." >&2
    exit 2
  fi
  mkdir -p "$RESOURCES/$tree"
  # --delete: a mirror, not a merge. See the header.
  rsync -a --delete "$REPO_ROOT/$tree/" "$RESOURCES/$tree/"
done

# The assertion. Its own output goes to stderr on failure so it appears in the
# build log above the noise, and its non-zero exit fails the build phase.
#
# `$SRCROOT` is `…/apps/miaotou_app/macos` and this script is in `…/macos/Runner`,
# so the assertion — which sits beside this file — is one `Runner/` down. The
# `Runner/` step is written out rather than folded into a variable because a
# variable holding half a path is how the wrong one survived a manual run: the
# earlier `"$SRCROOT/validate_payload_keys.py"` resolved to a file that does not
# exist, and every build failed here while hand-running the script passed.
python3 "$SRCROOT/Runner/validate_payload_keys.py" "$REPO_ROOT" "$RESOURCES"
