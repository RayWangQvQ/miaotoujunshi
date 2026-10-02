# Consolidate the skill payload into `goutoujunshi/`

- Status: accepted
- Date: 2026-10-02

## Context

The repository is one app project wrapped around an upstream skill. The app layer
already had its own directory (`integrations/`), but the skill payload did not:
`SKILL.md`, `references/`, `agents/`, `assets/` and `scripts/memory_store.py` sat
at the repository root next to app artifacts (`tests/`, `documentation/`) and
repository governance files (`README.md`, `NOTICE`, `GLOSSARY.md`, `docs/`).

Three symptoms showed the boundary was missing rather than merely untidy:

1. `GLOSSARY.md`, `README.md`, `NOTICE` and ADR-0001 each carried their own
   hand-copied list of "Skill layer" members. The four lists disagreed with each
   other and all four were wrong: each listed `examples/` (whose runtime consumer
   is `integrations/jev_mac/trend.py`, an app) and each omitted `assets/` and
   `scripts/memory_store.py`. A hand-copied list has no way to decide a new file.
2. `scripts/` mixed three unrelated layers: upstream-sourced scripts
   (`memory_store.py`, `validate_skill.py`), repository governance
   (`check_upstream.py`) and app packaging (`package_mac.py`).
3. `documentation/` collided with an upstream directory of the same name. Upstream
   has seven development documents there; this repository has app screenshots
   there, and none of upstream's seven were imported — so the name meant two
   different things depending on which repository you were reading.

Measured against upstream `shengjidaguai-china/goutoujunshi`: 52 overlapping
paths, 45 byte-identical, 5 modified locally (`SKILL.md`, one `references/`
document, `README.md`, `.gitignore`, one workflow), and one local-only
`references/` document. Upstream's `LICENSE` is byte-identical to this
repository's root `LICENSE` (`Copyright (c) 2026 powerycy`), so the payload is a
same-author fork, not third-party vendored code — there is no attribution
obligation on it, and `vendor/` would have misdescribed it.

## Decision

**Give the skill layer its own directory and make membership mechanically
decidable.**

1. **`goutoujunshi/` at the repository root holds the skill payload.** Every
   tracked path keeps its upstream-relative name, so the local copy is always
   `goutoujunshi/<same relative path>`. No per-file mapping table is needed, and
   `validate_skill.py`'s own `ROOT = parents[1]` resolves to the payload
   directory without modification.
2. **Membership criterion:** the file has a same-named counterpart upstream and is
   not one of upstream's repository governance files. Upstream's `README.md`,
   `README_EN.md`, `LICENSE`, `LICENSE.zh-CN.md`, `CHANGELOG.md`,
   `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md`, `SECURITY.md`, `.gitignore`,
   `.github/*` and its `documentation/` are **not** imported. Files this
   repository writes itself stay out of the directory.
3. **A root-entry allowlist carries the layer annotation.**
   `scripts/validate_layout.py` registers every permitted root entry with the
   layer it belongs to (`skill`, `app`, `governance`) and the reason it sits at the
   root. An unregistered entry fails the build. This replaces the four
   hand-copied lists.
4. **The app layer does not move.** `tests/`, `documentation/`, `examples/` and
   `PRIVACY.md` are app-layer content that stays at the root; each is registered
   in the allowlist as an app-layer root-level exception with its reason.
5. **Sync stays plain files plus `check_upstream.py`,** with its comparison range
   extended to cover the whole payload. No git subtree, no submodule: the payload
   carries deliberate local patches, so a read-only upstream reference would drop
   them and a subtree merge would fight them.
6. **The macOS source zip keeps the repository layout,** so
   `goutoujunshi/...` appears inside the archive. `integrations/jev_mac/core.py`
   locates the payload with `parents[2]`, so repository and package layouts have to
   agree.

## Rejected alternatives

- **Rename `integrations/` to `apps/`.** Clearer word, but it rewrites CI, test
  `sys.path` entries, packaging and docs for readability alone, and drops the
  "upstream port" meaning that `integrations/` carries.
- **Two top-level trees, `skill/` plus `apps/`, root left to governance only.**
  Cleanest on paper. Rejected because it discards the repository-root-is-the-skill
  distribution surface, and because every `parents[2]` path, the upstream path
  comparison and the packaging manifest would need a prefix map.
- **Name the directory `vendor/`.** Would misdescribe a same-author fork with
  deliberate local patches as read-only third-party code.
- **git subtree or submodule.** See decision 5.
- **Flatten the payload back into the zip root during packaging.** Would need a
  second path-resolution branch in `core.py` for the packaged case.
- **Mirror upstream's governance files into `goutoujunshi/`.** Would put two
  `README.md` and two `LICENSE` files in the repository with different contents and
  no way for a reader to tell which one is in force.

## Consequences

- `validate_skill.py` now needs `--runtime`. With its root inside the payload
  directory, the repository-level `README.md` and `LICENSE` it otherwise requires
  are not there. The flag already existed for exactly this distinction. The four
  call sites (two workflows, `README.md`, `integrations/jev_mac/README.md`) pass
  it.
- Moving `validate_skill.py` shrinks three of its checks, and this is **accepted
  as a known loss**: its two `ROOT.rglob` scans (markdown links, template
  placeholders) now cover `goutoujunshi/` only, and its
  `git ls-files -- research 恋爱知识库` check is vacuous because that path is not
  under the new root. The repository therefore has no repository-wide markdown-link
  or placeholder check. Restoring them belongs in a repository-level script, not in
  the payload's.
- `integrations/jev_mac/core.py` exports `SKILL_ROOT` instead of reusing `ROOT`;
  `trend.py` keeps its own `ROOT` for `examples/`. The two constants look similar
  but point at different levels, which is why they are no longer both named `ROOT`.
- Three app files read the payload at runtime and were updated:
  `integrations/jev_mac/core.py`, `deepseek_strategy.py` and `jev.py`, plus
  `memory_bridge.py` for `memory_store.py`.
- **Not addressed here:** the same skill rules exist in three forms — the macOS
  app reads the payload files, while Android (`GoutouGuidance.kt`) and Windows
  (`core/goutou.py`) inline the same rules as hardcoded constants. Only the macOS
  form is affected by this layout change. Recorded as a known fact, not a decision.
- ADR-0001's layer table lists skill-layer paths that this change supersedes. Its
  decision ("rename only the app layer") still stands and is not amended here; only
  its path list is stale.
