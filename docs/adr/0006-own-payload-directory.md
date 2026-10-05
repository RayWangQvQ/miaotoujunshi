# Give this repository's own payload its own directory

- Status: accepted
- Date: 2026-10-03

## Context

ADR-0003 gave the upstream skill payload a directory of its own (`goutoujunshi/`)
and left everything else at the repository root. The app layer's own shared
material — the tone rules, the structured data and the demo cases the three ports
read at runtime — therefore sat in two root-level directories, `references/` and
`examples/`, beside app artifacts (`integrations/`, `tests/`, `documentation/`) and
repository governance.

Three symptoms showed the boundary was missing rather than merely untidy:

1. The root allowlist could not say "app layer, but not app implementation":
   `references/` and `examples/` were registered as app-layer root-level exceptions,
   each justified by a paragraph of prose.
2. The two directories held the same kind of thing — files all three ports read at
   runtime — while `integrations/` held something else (three ports). Nothing in the
   layout said so, and before ADR-0003 four hand-copied member lists had already
   disagreed about `examples/`.
3. `references/data/payload-map.json` was dead. ADR-0005 recorded it as having one
   consumer (macOS), but macOS hard-coded the same scene map in `core.py`, and the
   paths in the file were relative to the payload root while the one path a port
   actually needed was relative to the repository root — two bases in one table with
   no reader to arbitrate.

## Decision

**This repository's own payload gets its own top-level directory, on the same member
rule as the upstream one.**

1. **`miaotoujunshi/` at the repository root holds it:** `references/knowledge/`
   (prose for the model), `references/data/` (structured data for the code) and
   `examples/` (the demo case bundle). The upstream payload keeps `goutoujunshi/`
   untouched and byte-identical (ADR-0004).
2. **Member rule:** a file belongs here when the three ports read it at runtime and
   it is not part of the upstream payload. The rule decides `references/` and
   `examples/`; it excludes `integrations/`, `tests/`, `documentation/` and
   `PRIVACY.md`, which stay in the app layer at the root.
3. **A second payload layer, `miaotoujunshi-skill`, is registered in
   `scripts/validate_layout.py`,** and that script's "do not invent new layer names
   here" line is superseded: it was written when exactly one payload directory
   existed.
4. **Payload paths are repository-root relative.** `payload-map.json` becomes the
   single source for the scene-to-payload selection, including the shared tone
   document; macOS reads it instead of the map it used to hard-code. `DATA_ROOT`
   stays a constant because it is what locates that file.
5. **Every port names three roots** — `REPO_ROOT`, `GOUTOU_SKILL_ROOT` and
   `MIAOTOU_SKILL_ROOT` — and builds material paths from them, so a later move
   changes constants rather than strings. This also retires the two same-named
   `ROOT` constants macOS carried for the same directory.
6. **Packaging takes the whole `miaotoujunshi/` tree.** `jev.spec`'s `datas` and
   `scripts/package_mac.py`'s `DIRS` name the directory rather than its children, so
   a file added to the own payload cannot be forgotten in one port only — the
   residual risk ADR-0005 accepted.
7. **Android assets keep repository-relative paths.** The copy task targets
   `miaotoujunshi/`, preserving the invariant that the path inside `assets/` is the
   path in the repository. It is a `Sync`, not a `Copy`: `Copy` leaves files in the
   destination that the source no longer has, which is how this move shipped both the
   old and the new trees in a locally built APK.

## Rejected alternatives

- **Move the whole app layer into the new directory.** `integrations/`, `tests/` and
  `documentation/` would join it, leaving two content trees plus governance. Cleanest
  on paper, but it rewrites every test `sys.path`, both packaging manifests and the
  CI triggers for tidiness alone, and it is not needed to state the member rule.
  **Partly superseded by [ADR-0017](0017-retire-the-integrations-wrapper.md):** the app
  layer did move, to `app/`, once the three ports were gone. `documentation/` was folded
  into `docs/` rather than joining it, and the member rule is unchanged.
- **Move only `references/`, leave `examples/` at the root.** The member rule would
  then need a named exception for a directory that satisfies it, which is how the
  hand-copied lists drifted in the first place.
- **Put the own payload inside `goutoujunshi/`.** The payload may differ from
  upstream by modifications, never by additions (ADR-0003, ADR-0004). Local material
  inside it would break `check_upstream.py`'s "only this repo has" line.
- **Rename the upstream payload directory to `miaotoujunshi/` and drop the
  distinction.** `goutoujunshi` is the identity standalone skill users installed;
  ADR-0001 froze it, and the two payloads answer to different owners.
- **Name the directory `app/`.** Shorter and free of the repository-name collision,
  but it drops the correspondence with the technical identifier prefix
  (`applicationId`, PyInstaller `NAME`, artifact and zip prefixes) that GLOSSARY.md
  already defines.
- **Register the new directory as another app-layer root exception.** Leaves the
  material indistinguishable from app implementation in the allowlist, which is the
  problem this ADR exists to fix.

## Consequences

- **Accepted costs:**
  - The repository is named `miaotoujunshi` and now contains a directory of the same
    name, so paths read `miaotoujunshi/miaotoujunshi/references/...` and the GitHub
    tree URL repeats itself.
  - `PRIVACY.md` is the one app-layer file that stays at the root although the member
    rule would move it: GitHub only auto-detects it at the root, and the app
    hard-codes that URL in two places.
  - The guardrail stays documentation-only. No test asserts that `miaotoujunshi/`
    holds exactly the runtime-read material — the same accepted cost as ADR-0005.
- **Superseded:** ADR-0003 decision 4 ("the app layer does not move") and its rejected
  alternative "two top-level trees, `skill/` plus `apps/`". ADR-0003's other decisions
  (payload directory, member criterion, allowlist, no subtree, package layout) stand.
- **Amended:** ADR-0005's recorded claim that `payload-map.json` had one consumer was
  not true when written — macOS hard-coded the map. Decision 4 makes it true; the
  claim is no longer an inaccuracy but a description of the wiring.
- The three ports' runtime paths changed; nothing user-visible did. macOS output,
  Windows prompts and the Android panel are unchanged.
- **Fixed on the way:** the Android assets task became a `Sync`. Moving the payload
  with a `Copy` left the previous `references/` and `examples/` trees in
  `build/sharedAssets/`, so a local build produced an APK carrying 34 shared files —
  both trees. A clean CI checkout would not have shown it, which is what made it worth
  fixing rather than documenting.
- `check_upstream.py` needs no change: its `TRACKED_DIRS = ("references",)` is
  relative to the payload root, so moving the root-level `references/` does not touch
  the drift check.
