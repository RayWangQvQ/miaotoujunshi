# Keep the skill payload byte-identical to upstream

- Status: accepted
- Date: 2026-10-02

## Context

ADR-0003 decision 5 chose plain files plus `check_upstream.py` over a submodule or
subtree, because the payload carried deliberate local patches. Its amendment then
hardened the rule to "no additions" and deleted the one local-only document, which
left the payload's whole delta at two modified files: `SKILL.md` and
`references/practical/实战话术编排器：从一句回复到后续分支.md`.

Reading that delta against the code showed both edits were app-layer opinions
wearing skill-layer clothes:

1. `SKILL.md` carried one added paragraph that named a "自然口吻" rule set existing
   nowhere but in the local patch, and (before the amendment) two routes pointing at
   a local-only file.
2. The 实战话术编排器 document had §3 replaced (upstream's five-item tone
   calibration, the local seven-rule natural-tone set), §4 amended, and the whole
   `## 常用话术库` section replaced by `## 场景示例：学取舍，不背句子` — thirteen
   upstream three-tier template groups swapped for thirteen situation examples.

Two defects surfaced from the same read:

1. **A silent behavioural regression.** `integrations/jev_mac/jev.py` truncates the
   strategy guide with `split("## 常用话术库", 1)[0]`. Renaming that heading made
   the split a no-op, so the strategy request had been receiving the entire examples
   section and the practice-mode section — directly contradicting the adjacent
   comment "without unrelated example replies".
2. **A test that stopped testing.** `tests/test_jev_strategy.py` asserted
   `assertNotIn("常用话术库", ...)`, which became vacuously true once that string no
   longer existed anywhere in the file.

Facts that constrain the fix:

- Upstream `shengjidaguai-china/goutoujunshi` is not a fork (`parent: none`) and this
  account has `pull` only, no `push`.
- Git history never held an upstream-pure copy: the patch predates the file's first
  commit here (`3262ae0`), so restoration has to read from the GitHub API.
- The macOS app already carried most of the tone rules independently — the `core.py`
  system prompt, `TONE_GUIDANCE` in `pipeline.py`, and its rewrite path — so part of
  the local patch was duplication rather than unique content.

## Decision

**The payload is a mirror, not a fork: every local opinion lives in the app layer.**

1. **`goutoujunshi/` must be byte-identical to upstream.** `check_upstream.py` reports
   zero drifted and zero local-only paths; `GLOSSARY.md` carries that as a boundary
   rule. Skill content this repository wants to change is proposed upstream, not
   patched in place.
2. **Both files are restored from upstream.** Restoring the heading restores
   `jev.py`'s truncation, so the regression fixes itself; the previously vacuous test
   regains force and gains a second assertion (`话术演练模式`) that locks the
   truncation rather than the renamed heading.
3. **The local content moves to the app layer** as
   `references/口吻与取舍.md` at the repository root — shared by all three ports,
   so no single `integrations/<port>/` directory can own it: the seven
   natural-tone rules, the "analysis for the user, candidates for the other
   person" framing, the amended 后续分支 wording, the substance of the deleted
   `SKILL.md` paragraph, and four of the thirteen examples — the four where
   upstream's self-invented memes cluster (tired, soft refusal, cancellation,
   "哈哈").
4. **`reference_paths()` returns absolute paths** so one request can draw from two
   layers: the payload strategy guide, this app's tone rules, one scene document.
   `jev.py` reads only the payload file, so the tone rules never reach the strategy
   model.
5. **The zero-delta policy is written down, not enforced in CI.** The assertion needs
   the GitHub API, and once the payload is a mirror the natural next step is a
   git-level reference, which retires `check_upstream.py` instead of extending it.
6. **Upstream is not asked to take the natural-tone rules**, accepting that standalone
   skill users lose that constraint. Revisit only if they ask.

## Rejected alternatives

- **Keep the intermediate "modify but never add" policy.** Two modified files are
  still a delta, so a git-level reference stays impossible — and both deltas were
  app-layer opinions, which the payload has no mandate to carry.
- **Load the payload in full and add one line to the app-layer file forbidding
  upstream's three-tier templates.** Rejected here: the templates are already
  addressed by the app prompt's own rules and the four counter-examples, and a blanket
  ban invites the model to reason about the rule instead of the reply. Accepted
  consequence: upstream's templates enter the reply context unchanged.
- **Truncate the payload in `core.py` too, at the same heading as `jev.py`.** This
  reproduces the old patch's net effect, but doubles a dependency on an upstream
  heading string and makes the removed content invisible behaviour.
- **Migrate all thirteen examples.** Roughly 2.5k characters enter every request,
  and most of the situations are already covered by rules the app layer states.
- **Inline the tone rules into the `core.py` system prompt instead of a file.**
  Example content would bloat a prompt that is already long, and Android and Windows
  each inline their own digest — a third inline copy deepens a divergence that is
  already recorded as a known fact.
- **Keep the `SKILL.md` paragraph as a self-contained rewrite.** Leaves one payload
  delta and keeps the zero-delta policy unenforceable.
- **Open a pull request upstream for the natural-tone rules.** No `push` access, and it
  would hand rule control to an external repository. Not pursued this round.

## Consequences

- **The reply model now receives upstream's `## 常用话术库` in full**, including the
  memes the old patch removed (补约账本／情绪客服／欠我好心情／批发价). This is
  accepted, not overlooked: if those surface in candidates, one line in the app-layer
  file is the cheap remedy. It is not a silent loss — this ADR is the record.
- **Standalone skill users lose the natural-tone paragraph** from `SKILL.md`; only
  upstream's "mark what cannot be verified" fallback remains. Accepted by decision 6.
- `reference_paths()` now returns three paths from two roots; `tests/test_jev_mac.py`
  asserts the file name at each position instead of the old two-path shape.
- `jev.py`'s truncation depends on an upstream heading string. A future upstream
  rename now fails a test instead of silently changing what the strategy model sees.
- Android and Windows are untouched: neither reads the payload, both inline their own
  digest.
- The payload's delta returning to zero **reopens ADR-0003 decision 5's rejected
  option**: a read-only git-level reference (submodule or subtree) is now viable in
  principle. Not adopted here, and `check_upstream.py` is not yet retired.
- The root-level `references/` directory is the **first shared app-layer location**:
  it belongs to no single port, so it is registered in the root allowlist
  (`scripts/validate_layout.py`) as an app-layer root exception and added to
  `scripts/package_mac.py`'s `DIRS`. Placing it under `integrations/jev_mac/` would
  have been a silent platform bias; keeping it out of the packaged directories
  would have left the packaged app unable to resolve `TONE_REFERENCE`.
- The macOS zip therefore carries the upstream payload, the app-layer tone rules
  and the three ports side by side, which is the intended end state.
- **Correction (same day):** decision 3 first put the file under
  `integrations/jev_mac/references/`. That was wrong — the rules are shared by all
  three ports, and two of them apply the same rules today as inlined digests. The
  file moved to the root `references/` directory; the wiring state of each port is
  deliberately not recorded in the file, because it changes as the ports are
  unified and a stale claim there has already cost this repository once.
