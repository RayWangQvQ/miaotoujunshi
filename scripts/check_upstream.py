#!/usr/bin/env python3
"""Compare the vendored goutoujunshi skill content against its upstream repository.

The skill payload was copied into this repository once and is tracked here as
ordinary files under ``goutoujunshi/``; there is no submodule or subtree linking
it back upstream. This script is the manual replacement for that missing link:
it tells you what has drifted so you can decide what to merge by hand.

Every tracked path keeps its upstream-relative name, so the local copy is always
``goutoujunshi/<same relative path>`` and no per-file mapping table is needed.

Read-only and dependency-free. It never writes, fetches nothing but the public
GitHub tree, and works without a token (unauthenticated rate limit is enough for
a single tree request).

Usage:
    python3 scripts/check_upstream.py                 # summary
    python3 scripts/check_upstream.py --diff <path>   # show one file's diff
"""

from __future__ import annotations

import argparse
import base64
import difflib
import hashlib
import json
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path, PurePosixPath

ROOT = Path(__file__).resolve().parents[1]
UPSTREAM_REPO = "shengjidaguai-china/goutoujunshi"
UPSTREAM_BRANCH = "main"
API = f"https://api.github.com/repos/{UPSTREAM_REPO}"

# The skill payload directory; tracked paths below are relative to it and to the
# upstream repository root alike.
SKILL_DIR = "goutoujunshi"
SKILL_BASE = ROOT / SKILL_DIR

# Paths whose content is inherited from upstream and therefore worth comparing.
TRACKED_DIRS = ("references",)
TRACKED_FILES = (
    "SKILL.md",
    "agents/openai.yaml",
    "assets/reference-library-135.png",
    "scripts/memory_store.py",
    "scripts/validate_skill.py",
)

# Directories watched for new upstream content: the tracked directories plus the
# parent directories of the tracked single files.
WATCHED_DIRS = TRACKED_DIRS + tuple(
    sorted({str(PurePosixPath(name).parent) for name in TRACKED_FILES if "/" in name})
)


def _get(url: str) -> dict:
    request = urllib.request.Request(url, headers={"User-Agent": "goutoujunshi-jev-chat"})
    with urllib.request.urlopen(request, timeout=30) as response:
        return json.load(response)


def git_blob_sha(path: Path) -> str:
    """Return the git object id for a file, matching what the API reports."""
    data = path.read_bytes()
    digest = hashlib.sha1()
    digest.update(b"blob %d\0" % len(data))
    digest.update(data)
    return digest.hexdigest()


def upstream_tree() -> dict[str, str]:
    """Fetch the whole upstream tree in one request: path -> blob sha."""
    tree = _get(f"{API}/git/trees/{UPSTREAM_BRANCH}?recursive=1")
    if tree.get("truncated"):
        print("warning: upstream tree was truncated; comparison may be incomplete")
    return {
        item["path"]: item["sha"]
        for item in tree.get("tree", [])
        if item["type"] == "blob"
    }


def local_paths() -> list[str]:
    found = list(TRACKED_FILES)
    for directory in TRACKED_DIRS:
        base = SKILL_BASE / directory
        if base.is_dir():
            found += [
                str(path.relative_to(SKILL_BASE))
                for path in sorted(base.rglob("*.md"))
            ]
    return found


def compare() -> tuple[list[str], list[str], list[str], list[str], list[str]]:
    """Return (identical, drifted, upstream_only, local_only, missing) paths.

    ``missing`` lists tracked paths that the local skill directory should carry
    but does not: without it the report stays silent when a tracked file is
    deleted, because absent files simply drop out of ``local_paths``.
    """
    upstream = upstream_tree()
    identical: list[str] = []
    drifted: list[str] = []
    local_only: list[str] = []
    missing: list[str] = []

    tracked_paths = local_paths()
    for relative in tracked_paths:
        local = SKILL_BASE / relative
        sha = upstream.get(relative)
        if not local.is_file():
            missing.append(relative)
        elif sha is None:
            local_only.append(relative)
        elif git_blob_sha(local) == sha:
            identical.append(relative)
        else:
            drifted.append(relative)

    tracked = set(tracked_paths)
    upstream_only = [
        path
        for path in upstream
        if path.split("/", 1)[0] in WATCHED_DIRS and path not in tracked
    ]
    return identical, drifted, sorted(upstream_only), local_only, missing


def show_diff(relative: str) -> int:
    encoded = urllib.parse.quote(relative)
    payload = _get(f"{API}/contents/{encoded}?ref={UPSTREAM_BRANCH}")
    upstream_lines = base64.b64decode(payload["content"]).decode("utf-8").splitlines()
    local_lines = (SKILL_BASE / relative).read_text(encoding="utf-8").splitlines()
    sys.stdout.write(
        "\n".join(
            difflib.unified_diff(
                upstream_lines, local_lines, "upstream/" + relative, "local/" + relative, lineterm=""
            )
        )
        + "\n"
    )
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--diff", metavar="PATH", help="show the diff for one tracked path")
    args = parser.parse_args()

    if args.diff:
        try:
            return show_diff(args.diff)
        except urllib.error.HTTPError as error:
            print(f"ERROR: upstream has no such path ({error.code}): {args.diff}")
            return 2

    try:
        identical, drifted, upstream_only, local_only, missing = compare()
    except urllib.error.URLError as error:
        print(f"ERROR: cannot reach GitHub: {error}")
        return 2

    print(f"upstream: {UPSTREAM_REPO}@{UPSTREAM_BRANCH}")
    print(f"local   : {SKILL_DIR}/")
    print()
    print(f"identical to upstream : {len(identical)}")
    print(f"drifted (both changed): {len(drifted)}")
    print(f"only upstream has     : {len(upstream_only)}")
    print(f"only this repo has    : {len(local_only)}")
    print(f"tracked but missing   : {len(missing)}")

    if missing:
        print("\n[missing] tracked content the skill directory should carry:")
        for path in missing:
            print(f"  ! {SKILL_DIR}/{path}")
    if drifted:
        print("\n[drifted] review each one before merging; local edits may be intentional:")
        for path in drifted:
            print(f"  ~ {path}")
    if upstream_only:
        print("\n[upstream only] new upstream content not present here:")
        for path in upstream_only:
            print(f"  - {path}")
    if local_only:
        print("\n[local only] this repo's own additions (not expected upstream):")
        for path in local_only:
            print(f"  + {path}")

    print("\nNothing was modified. Inspect a file with: --diff <path>")
    return 0


if __name__ == "__main__":
    sys.exit(main())
