#!/usr/bin/env python3
"""Assert the attribution and data-use notes still describe what exists.

The three old platform ports each carried their own `LICENSE` and `NOTICE`, and
each was deleted when that port was promoted. Their attribution obligations were
folded into the root `NOTICE`, which means a documentation edit — or the next
port deletion — could quietly drop one. This script is the mechanical guard for
that, and for the two other halves of the same ticket: every dependency the
Flutter workspace actually pulls in has to be recorded in `NOTICE` together with
its licence, and the data-use notes have to describe the mechanisms this
repository ships rather than the packaging it used to ship.

What it checks, and why each one is checkable:

- the three upstreams are still named, with their copyright holders and the
  pinned macOS commit, and the notice still forbids implying endorsement;
- every external dependency declared in a `pubspec.yaml`, in the Windows bridge's
  `Cargo.toml` and in the Android plugin's Gradle block appears in `NOTICE` on a
  line that also carries a licence — so adding a dependency without recording its
  licence fails here, not in review;
- `PRIVACY.md` states the memory store's consent gate, pause flag and capacity
  bound, and the bounds it states are the ones the three implementations enforce;
- none of the two files still describes the old packaging.

Read-only and dependency-free: it parses the manifests with the standard library
rather than with PyYAML, because it runs in CI before anything is installed.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FLUTTER = ROOT / "integrations" / "jev_flutter"
NOTICE_PATH = ROOT / "NOTICE"
PRIVACY_PATH = ROOT / "PRIVACY.md"

ERRORS: list[str] = []

# The three upstreams whose obligations this repository carries. The URL tail is
# what `NOTICE` links; the holder is the name that must appear in the copyright
# column, and it is the one thing a rewrite cannot paraphrase away.
UPSTREAMS = (
    ("github.com/jev-chat/jev-chat-jarvis", "Finderchangchang"),
    ("github.com/jev-chat/jev-chat-windows", "rezoch340"),
    ("github.com/jev-chat/jev-chat-jarvis-mac", "eatmoreduck"),
)

# The macOS port was taken at a pinned commit, so the pin is part of the
# attribution and has to survive with it.
PINNED_MAC_COMMIT = "afb58cf53d098e314a1368d15e13ab5330015688"

# A licence string next to the component name. "Google ML Kit" covers the one
# proprietary component, which is recorded as proprietary rather than as an
# open-source licence.
LICENCE_TOKENS = (
    "MIT",
    "Apache-2.0",
    "BSD-3-Clause",
    "EPL-1.0",
    "Google ML Kit",
)

# Packaging and platform vocabulary that described the ports this repository
# replaced. Finding any of it in the current notes means a stale statement.
STALE_TOKENS = (
    "PyInstaller",
    "PySide6",
    "PyObjC",
    "GPLv3",
    "源码包",
    "替换验收",
)

# What `PRIVACY.md` has to promise about the memory store. The three words are
# the promise itself; the numbers are the bound, and they are compared against
# the implementations below rather than hard-coded here.
PRIVACY_PROMISES = ("未同意", "暂停", "容量上限")

MEMORY_BOUNDS = ("maxValueChars", "maxRows", "maxOperations")

# The capacity promise is one bullet in PRIVACY.md; the bounds have to be stated
# there, not merely appear somewhere in the file.
CAPACITY_MARKER = "容量上限"


def read(path: Path) -> str:
    if not path.exists():
        ERRORS.append(f"missing required file: {path.relative_to(ROOT)}")
        return ""
    return path.read_text(encoding="utf-8")


def section_keys(text: str, section: str) -> list[tuple[str, str]]:
    """Return the two-space-indented keys of a top-level YAML section, each with
    the kind of value it has.

    A minimal scan rather than a YAML parse: the manifests are flat enough that
    a real parser would only add a dependency this script is not allowed to
    have. A dependency is written either inline (`yaml: ^3.1.2`) or with its
    qualifier on the next line (`miaotou_capabilities:` / `path: ../...`), and
    the nested key is all a caller needs to tell the three kinds apart.
    """
    keys: list[tuple[str, str]] = []
    lines = text.splitlines()
    in_section = False
    for index, line in enumerate(lines):
        if re.match(r"^[A-Za-z_]", line):
            in_section = line.split(":", 1)[0].strip() == section
            continue
        if not in_section:
            continue
        match = re.match(r"^  ([A-Za-z0-9_]+):\s*(.*)$", line)
        if not match:
            continue
        name, value = match.group(1), match.group(2).strip()
        if value:
            keys.append((name, "version"))
            continue
        # Empty: the qualifier is the indented line directly below.
        nested = re.match(r"^    ([A-Za-z0-9_]+):", lines[index + 1] or "")
        keys.append((name, nested.group(1) if nested else "version"))
    return keys


def external_pub_dependencies() -> list[str]:
    """Every pub dependency that is not this repository's own code or the SDK."""
    found: list[str] = []
    manifests = [FLUTTER / "pubspec.yaml"]
    manifests += sorted(FLUTTER.glob("apps/*/pubspec.yaml"))
    manifests += sorted(FLUTTER.glob("packages/*/pubspec.yaml"))
    for manifest in manifests:
        text = read(manifest)
        for section in ("dependencies", "dev_dependencies"):
            for name, kind in section_keys(text, section):
                if kind == "path":
                    continue  # a workspace member: covered by the root LICENSE
                if name in {"flutter", "flutter_test"}:
                    continue  # the SDK itself, recorded as "Flutter SDK"
                found.append(name)
    return sorted(set(found))


def cargo_dependencies() -> list[str]:
    """Every direct dependency of the Windows native bridge."""
    cargo = FLUTTER / "packages/miaotou_capabilities_windows/native_bridge/Cargo.toml"
    text = read(cargo)
    found: list[str] = []
    in_dependencies = False
    for line in text.splitlines():
        stripped = line.strip()
        if stripped.startswith("["):
            in_dependencies = stripped == "[dependencies]"
            continue
        if in_dependencies and "=" in stripped and not stripped.startswith("#"):
            found.append(stripped.split("=", 1)[0].strip())
    return sorted(set(found))


def gradle_dependencies() -> list[str]:
    """Every Gradle artifact the Android capability plugin resolves.

    Anchored on the configuration name so `testImplementation(` is read as a
    test dependency and never as a shipped one, and so `classpath(` — the
    buildscript plugins — is not silently skipped.
    """
    found: list[str] = []
    for gradle in sorted(FLUTTER.glob("packages/*/android/build.gradle.kts")):
        text = read(gradle)
        for configuration, coordinates in re.findall(
            r"^\s*(\w*[Ii]mplementation|classpath)\(\"([^\"]+)\"\)",
            text,
            flags=re.MULTILINE,
        ):
            found.append(coordinates.split(":")[1])
    return sorted(set(found))


def mentions(text: str, name: str) -> bool:
    """True when `text` names the component as a whole token.

    Substring matching is not enough: `gradle` would otherwise be satisfied by
    the `kotlin-gradle-plugin` row, and `serde` by the `serde_json` one, so a
    dropped licence could go unnoticed.
    """
    pattern = rf"(?<![A-Za-z0-9_\-]){re.escape(name)}(?![A-Za-z0-9_\-])"
    return re.search(pattern, text) is not None


def recorded_with_licence(notice: str, name: str) -> bool:
    """True when `NOTICE` names the component on a line that also states a licence."""
    for line in notice.splitlines():
        if mentions(line, name) and any(token in line for token in LICENCE_TOKENS):
            return True
    return False


def validate_upstreams(notice: str) -> None:
    for url, holder in UPSTREAMS:
        if url not in notice:
            ERRORS.append(f"NOTICE no longer names the upstream {url}")
        if holder not in notice:
            ERRORS.append(f"NOTICE no longer carries the copyright holder {holder}")
    if PINNED_MAC_COMMIT not in notice:
        ERRORS.append(f"NOTICE no longer pins the macOS upstream at {PINNED_MAC_COMMIT}")
    if "endorsement" not in notice:
        ERRORS.append("NOTICE no longer states that upstream names must not imply endorsement")


def validate_dependencies(notice: str) -> None:
    if "Flutter SDK" not in notice:
        ERRORS.append("NOTICE does not record the Flutter SDK's licence")
    dependencies = (
        external_pub_dependencies() + cargo_dependencies() + gradle_dependencies()
    )
    for name in dependencies:
        if not mentions(notice, name):
            ERRORS.append(f"NOTICE does not record the dependency {name}")
        elif not recorded_with_licence(notice, name):
            ERRORS.append(f"NOTICE records {name} without a licence")


def memory_bounds() -> list[int]:
    """The capacity bounds the three ports' memory stores actually enforce."""
    bounds: set[int] = set()
    # One store per port. The domain package has a `memory.dart` too, but it
    # holds no bounds, so the glob is scoped to the platform packages.
    for path in sorted(FLUTTER.glob("packages/miaotou_capabilities_*/lib/src/memory.dart")):
        text = read(path)
        for key in MEMORY_BOUNDS:
            match = re.search(rf"{key}\s*=\s*(\d+)", text)
            if match:
                bounds.add(int(match.group(1)))
            else:
                ERRORS.append(f"{path.relative_to(ROOT)} no longer declares {key}")
    return sorted(bounds)


def validate_privacy(privacy: str) -> None:
    for promise in PRIVACY_PROMISES:
        if promise not in privacy:
            ERRORS.append(f"PRIVACY.md no longer promises {promise}")
    capacity = [line for line in privacy.splitlines() if CAPACITY_MARKER in line]
    if not capacity:
        ERRORS.append(f"PRIVACY.md has no line stating the {CAPACITY_MARKER}")
        return
    stated = "\n".join(capacity)
    for bound in memory_bounds():
        if not re.search(rf"\b{bound}\b", stated):
            ERRORS.append(
                f"PRIVACY.md's capacity line does not state the bound {bound} "
                f"the memory stores enforce"
            )


def validate_no_stale_statements(notice: str, privacy: str) -> None:
    """Neither file may describe packaging this repository replaced."""
    for name, text in (("NOTICE", notice), ("PRIVACY.md", privacy)):
        for token in STALE_TOKENS:
            if token in text:
                ERRORS.append(
                    f"{name} still mentions {token}, which describes packaging "
                    f"this repository replaced"
                )


def main() -> int:
    unexpected_args = sys.argv[1:]
    if unexpected_args:
        print(f"ERROR: unsupported arguments: {' '.join(unexpected_args)}")
        return 2

    notice = read(NOTICE_PATH)
    privacy = read(PRIVACY_PATH)

    validate_upstreams(notice)
    validate_dependencies(notice)
    validate_privacy(privacy)
    validate_no_stale_statements(notice, privacy)

    if ERRORS:
        for error in ERRORS:
            print(f"ERROR: {error}")
        return 1
    print("attribution and data-use notes validation passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
