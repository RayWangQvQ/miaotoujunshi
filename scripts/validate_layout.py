#!/usr/bin/env python3
"""Assert the repository root carries only registered, layer-annotated entries.

The root used to mix skill payload, app artifacts and repository governance, so
nothing stopped a new file from landing there without a home. This script is the
hard gate for that: every entry at the repository root must be registered below
together with the layer it belongs to. An unregistered entry fails the build.

Layer names reuse the vocabulary already established in GLOSSARY.md: the skill
layer and the app layer, plus the governance files that belong to neither. Do
not invent new layer names here.

Read-only and dependency-free.
"""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
ERRORS: list[str] = []

SKILL = "skill"
APP = "app"
GOVERNANCE = "governance"

# Directory holding the skill payload; the layer boundary itself.
SKILL_DIR = "goutoujunshi"

# Every entry allowed at the repository root: name -> (layer, why it sits here).
# Adding a file to the root means registering it here in the same commit.
ALLOWED: dict[str, tuple[str, str]] = {
    # Skill layer: the upstream-sourced payload lives in its own directory, which
    # is the whole point of the boundary. See docs/adr/0003.
    SKILL_DIR: (SKILL, "skill payload directory; the directory is the boundary"),
    # App layer. `integrations/` holds the three ports; the rest are app-layer
    # content that has to sit at the root for a concrete reason. Do not count
    # them here: this dict is the count.
    "integrations": (APP, "the three platform ports"),
    "references": (
        APP,
        "shared app-layer material (prose plus data/) read at runtime by all "
        "three ports; it belongs to no single port, so no integrations/<port>/ "
        "directory can hold it",
    ),
    "tests": (APP, "tests for the app integrations"),
    "documentation": (APP, "app screenshots and design notes"),
    "examples": (
        APP,
        "app-layer demo fixtures; the runtime consumer is every port's trend "
        "reader, not the skill",
    ),
    "PRIVACY.md": (APP, "app data-use notes; root placement is a GitHub convention"),
    # Governance: neither skill nor app.
    "scripts": (GOVERNANCE, "repository-level tooling"),
    "docs": (GOVERNANCE, "ADRs and agent working notes"),
    ".github": (GOVERNANCE, "CI workflows"),
    ".vscode": (
        GOVERNANCE,
        "editor, task and debug configurations; committed so the Android debug "
        "channel and its device resolver travel with the code",
    ),
    ".gitignore": (GOVERNANCE, "git ignore rules"),
    "AGENTS.md": (GOVERNANCE, "agent instructions"),
    "GLOSSARY.md": (GOVERNANCE, "domain glossary"),
    "LICENSE": (GOVERNANCE, "licence for the code written in this repository"),
    "NOTICE": (GOVERNANCE, "provenance, attribution and licence layering"),
    "README.md": (GOVERNANCE, "repository overview"),
}

# Used only when the working tree is not a git checkout (for example a source
# zip): directories that are ignored by .gitignore and never committed. A
# tracked root directory must appear in ALLOWED instead of being listed here.
IGNORED = {".venv", "dist", ".workbuddy", "__pycache__", "build"}


def root_entries() -> list[str]:
    """Return the top-level names that actually land in the repository."""
    if (ROOT / ".git").exists():
        listed = subprocess.run(
            ["git", "-c", "core.quotepath=false", "ls-files"],
            cwd=ROOT,
            check=False,
            capture_output=True,
            text=True,
        ).stdout.splitlines()
        return sorted({line.split("/", 1)[0] for line in listed if line})
    return sorted(entry.name for entry in ROOT.iterdir() if entry.name not in IGNORED)


def validate_root_entries() -> None:
    for name in root_entries():
        if name not in ALLOWED:
            ERRORS.append(
                f"unregistered entry at the repository root: {name} "
                f"({_where_it_belongs(name)})"
            )


def _where_it_belongs(name: str) -> str:
    """Point at the right home for names that are unmistakably layered."""
    stem = name.split(".", 1)[0].lower()
    if stem in {"skill", "references", "reference", "agents", "agent", "assets", "asset"}:
        return f"skill layer: move it under {SKILL_DIR}"
    return "register it here with the layer it belongs to and why it sits at the root"


def main() -> int:
    unexpected_args = sys.argv[1:]
    if unexpected_args:
        print(f"ERROR: unsupported arguments: {' '.join(unexpected_args)}")
        return 2

    validate_root_entries()
    if ERRORS:
        for error in ERRORS:
            print(f"ERROR: {error}")
        return 1
    print(f"layout validation passed ({len(ALLOWED)} registered root entries)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
