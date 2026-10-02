#!/usr/bin/env python3
"""Compare the vendored goutoujunshi skill content against its upstream repository.

The skill files (SKILL.md and references/) were copied into this repository once
and are tracked here as ordinary files; there is no submodule or subtree linking
them back upstream. This script is the manual replacement for that missing link:
it tells you what has drifted so you can decide what to merge by hand.

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
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
UPSTREAM_REPO = "shengjidaguai-china/goutoujunshi"
UPSTREAM_BRANCH = "main"
API = f"https://api.github.com/repos/{UPSTREAM_REPO}"

# Paths whose content is inherited from upstream and therefore worth comparing.
TRACKED_DIRS = ("references",)
TRACKED_FILES = ("SKILL.md",)


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
    found = [name for name in TRACKED_FILES if (ROOT / name).is_file()]
    for directory in TRACKED_DIRS:
        base = ROOT / directory
        if base.is_dir():
            found += [
                str(path.relative_to(ROOT))
                for path in sorted(base.rglob("*.md"))
            ]
    return found


def compare() -> tuple[list[str], list[str], list[str], list[str]]:
    """Return (identical, drifted, upstream_only, local_only) relative paths."""
    upstream = upstream_tree()
    identical: list[str] = []
    drifted: list[str] = []
    local_only: list[str] = []

    for relative in local_paths():
        sha = upstream.get(relative)
        if sha is None:
            local_only.append(relative)
        elif git_blob_sha(ROOT / relative) == sha:
            identical.append(relative)
        else:
            drifted.append(relative)

    tracked = set(local_paths())
    upstream_only = [
        path
        for path in upstream
        if path.startswith(TRACKED_DIRS) and path.endswith(".md") and path not in tracked
    ]
    return identical, drifted, sorted(upstream_only), local_only


def show_diff(relative: str) -> int:
    encoded = urllib.parse.quote(relative)
    payload = _get(f"{API}/contents/{encoded}?ref={UPSTREAM_BRANCH}")
    upstream_lines = base64.b64decode(payload["content"]).decode("utf-8").splitlines()
    local_lines = (ROOT / relative).read_text(encoding="utf-8").splitlines()
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
        identical, drifted, upstream_only, local_only = compare()
    except urllib.error.URLError as error:
        print(f"ERROR: cannot reach GitHub: {error}")
        return 2

    print(f"upstream: {UPSTREAM_REPO}@{UPSTREAM_BRANCH}")
    print()
    print(f"identical to upstream : {len(identical)}")
    print(f"drifted (both changed): {len(drifted)}")
    print(f"only upstream has     : {len(upstream_only)}")
    print(f"only this repo has    : {len(local_only)}")

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
