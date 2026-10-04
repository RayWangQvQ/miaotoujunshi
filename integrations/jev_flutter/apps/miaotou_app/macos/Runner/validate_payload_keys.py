#!/usr/bin/env python3
"""Assert every payload key the app can request is present in a built tree.

The shared payload reaches a packaged application by being copied **whole**, and
this script is what makes the copy trustworthy. It answers one question:

    is every key the material interface can ask for actually inside the tree?

ADR-0008 states the failure this replaces: the old macOS guard compared an
allowlist against the files the runtime read, so a new payload file was invisible
until a user pressed a button. The failure mode degraded from "the package step
fails" to "the user presses a button and nothing happens", and this is the
replacement for it.

## Why the key set is derived, never transcribed
--------------------------------------------------------------------------------

The keys are read from two places, neither of which is a hand-written list:

* the domain layer's own constants, parsed out of the Dart source — the
  alternative is a second copy of a path, and a second copy is exactly how
  `references/` and `examples/` ended up with four disagreeing member lists in
  ADR-0006;
* `payload-map.json` itself, which is the single source for scene-to-file
  selection (ADR-0006 decision 4).

Transcribing either into this script would reintroduce the drift the derivation
removes, so a guard test asserts the derivation is what runs.

## Usage
    validate_payload_keys.py <repository-root> <packaged-root>

`packaged-root` is the directory the payload tree was copied into — for macOS,
`.app/Contents/Resources`. Exits non-zero and prints one line per missing key.
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path


# The Dart constants that are payload keys, as `const String name = 'value';`.
# The expression is anchored on the declaration so a mention of the name in a
# doc comment or a call site cannot be mistaken for the declaration itself.
_CONST_DECLARATION = re.compile(
    r"^const\s+String\s+(?P<name>\w*Path|\w*Dir)\s*=\s*'(?P<value>[^']+)'\s*;",
    re.MULTILINE,
)

# The files whose declarations are keys. Every one of them is a constant the
# domain reads the payload through; a file not listed here contributes no keys,
# and the guard test asserts the list is complete against what the domain reads.
# Relative to the **pub workspace root**, not the repository root: that is where
# the Dart sources live, and `findRepositoryRoot`-style walking up from the build
# directory would have to know how deep the app sits inside the repository.
_WORKSPACE = "integrations/jev_flutter"

_DOMAIN_SOURCES = (
    f"{_WORKSPACE}/packages/miaotou_domain/lib/src/shared_material.dart",
    f"{_WORKSPACE}/packages/miaotou_domain/lib/src/relationship.dart",
    f"{_WORKSPACE}/packages/miaotou_domain/lib/src/trend.dart",
)

# `payload-map.json` holds the scene selection. Its own values are keys; the
# `_provenance` member is prose about the file and is not one.
_MAP_STRING_KEYS = ("strategy_guide", "shared_tone_document", "entry_document")
_MAP_MAP_KEYS = ("scene_knowledge",)

PAYLOAD_MAP = "miaotoujunshi/references/data/payload-map.json"

# `SharedPayload.read` answers bytes and `SharedPayload.list` answers names, so a
# key is either a file or a directory and the assertion has to know which.
#
# The name is the only thing that tells them apart: `caseBundleDir` points at
# `…/examples/relationship_cases`, whose last path segment says nothing about it.
# Matching the *value* would classify every one of these keys as a file, and a
# file key asserted with `is_dir()` would pass on an empty folder — which is the
# failure this whole script exists to make impossible.
_KEY_IS_DIRECTORY = re.compile(r"Dir$")


class Failure(Exception):
    """The tree cannot be judged at all, as opposed to judged and found short."""


def domain_constant_keys(repository: Path) -> dict[str, bool]:
    """The payload keys the domain layer declares as constants, and their kind.

    Parsed from the Dart source rather than listed here, so that adding a payload
    key to the domain is picked up by the next build with no edit to this file.
    That is the whole difference between this and the allowlist ADR-0008 retired.

    A source file that yields no key is a **failure**, not an empty result: it
    means the pattern above stopped matching the Dart it reads, and a script that
    silently asserts nothing is worse than no script, because the build goes green
    over a guard that is no longer running.
    """
    keys: dict[str, bool] = {}
    for relative in _DOMAIN_SOURCES:
        source = repository / relative
        if not source.is_file():
            raise Failure(f"missing domain source: {relative}")
        text = source.read_text(encoding="utf-8")
        found = {
            match.group("value"): bool(_KEY_IS_DIRECTORY.search(match.group("name")))
            for match in _CONST_DECLARATION.finditer(text)
        }
        if not found:
            raise Failure(
                f"{relative} declares no payload-path constants; the pattern in "
                f"validate_payload_keys.py no longer matches the Dart it reads, "
                f"so this script would silently assert nothing"
            )
        keys.update(found)
    return keys


def payload_map_keys(repository: Path) -> set[str]:
    """Every path `payload-map.json` names.

    Read from the file rather than from a transcription of it, which is what
    makes a scene added to the payload ship without a build edit — and, here, be
    *asserted* without a build edit too.
    """
    path = repository / PAYLOAD_MAP
    if not path.is_file():
        raise Failure(f"missing {PAYLOAD_MAP}")
    document = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(document, dict):
        raise Failure(f"{PAYLOAD_MAP} does not hold a JSON object")

    keys: set[str] = set()
    for name in _MAP_STRING_KEYS:
        value = document.get(name)
        if value is None:
            raise Failure(f"{PAYLOAD_MAP} has no {name!r}")
        if not isinstance(value, str):
            raise Failure(f"{PAYLOAD_MAP}: {name!r} is not a string")
        keys.add(value)

    for name in _MAP_MAP_KEYS:
        section = document.get(name)
        if section is None:
            raise Failure(f"{PAYLOAD_MAP} has no {name!r}")
        if not isinstance(section, dict):
            raise Failure(f"{PAYLOAD_MAP}: {name!r} is not an object")
        # A scene with no document would be a scene that analyses against nothing,
        # and an empty value here would be a key of '' that every tree "has".
        for scene, value in section.items():
            if not isinstance(value, str) or not value:
                raise Failure(f"{PAYLOAD_MAP}: scene {scene!r} names no document")
            keys.add(value)
    return keys


def required_keys(repository: Path) -> dict[str, bool]:
    """Every key the material interface can request, mapped to "is a directory".

    A dict rather than a set because the directory keys have to be checked
    differently, and returning a bare set would push that choice onto the caller.
    """
    keys = dict(domain_constant_keys(repository))
    # The map's own values are all documents, so a collision with a `Dir` constant
    # is a contradiction rather than a merge — say so instead of picking one.
    for value in payload_map_keys(repository):
        if value in keys and keys[value]:
            raise Failure(
                f"{value} is declared as a directory constant and named by "
                f"{PAYLOAD_MAP} as a document"
            )
        keys[value] = False
    return keys


def missing_keys(repository: Path, packaged: Path) -> list[str]:
    """The required keys with nothing at that path under [packaged]."""
    if not packaged.is_dir():
        raise Failure(f"not a directory: {packaged}")
    missing: list[str] = []
    for key, is_directory in sorted(required_keys(repository).items()):
        present = (packaged / key).is_dir() if is_directory else (packaged / key).is_file()
        if not present:
            missing.append(key)
    return missing


def main(argv: list[str]) -> int:
    if len(argv) != 3:
        print(__doc__, file=sys.stderr)
        return 2
    repository = Path(argv[1]).resolve()
    packaged = Path(argv[2]).resolve()
    try:
        missing = missing_keys(repository, packaged)
    except Failure as error:
        print(f"payload assertion failed: {error}", file=sys.stderr)
        return 2
    if missing:
        print(
            f"payload assertion failed: {len(missing)} key(s) the app can request "
            f"are not in the packaged tree:",
            file=sys.stderr,
        )
        for key in missing:
            print(f"  missing: {key}", file=sys.stderr)
        return 1
    print(f"payload assertion passed: {len(required_keys(repository))} keys present")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
