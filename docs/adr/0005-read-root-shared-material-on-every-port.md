# Read the shared app-layer material from the repository root on every port

- Status: accepted
- Date: 2026-10-02

## Context

ADR-0004 decision 3 created the root-level `references/` directory as the first shared
app-layer location, on the grounds that the tone and trade-off rules belong to no single
port. Its correction note deliberately refused to record each port's wiring state, because
that state changes. The refusal was right; the state it hid is the defect this ADR fixes:
**only macOS reads anything from the repository root.**

- macOS resolves `ROOT = parents[2]` and reads the payload, `references/口吻与取舍.md` and
  `examples/relationship_cases/` at runtime (`integrations/jev_mac/core.py:13-17`, `:89-100`;
  `integrations/jev_mac/trend.py:15-16`).
- Windows and Android read no root file at all. Each carries an inlined digest:
  `core/goutou.py`, `core/questions.py`, `core/draft.py`, `core/trend.py` on Windows;
  `core/GoutouGuidance.kt`, `jev/JevQuestions.kt`, `jev/ReplyClient.kt`, `core/TrendData.kt`
  on Android.

A read-only sweep found three further instances of the same class:

1. `integrations/jev_mac/demo_kline.json` (the illustrative candles) sits inside a
   single-port directory while the identical values are hardcoded in Windows
   `core/trend.py:19-31` and Android `core/TrendData.kt:11-22` — the exact placement
   `GLOSSARY.md` forbids.
2. `STRATEGIES` exists three times: `integrations/jev_mac/core.py:18`,
   `integrations/jev_windows/core/deepseek_strategy.py:16`,
   `integrations/jev_android/app/src/main/java/com/jev/probe/jev/DeepSeekStrategyClient.kt:14`.
3. The Jev seven-question judge set is duplicated verbatim between Windows
   (`core/questions.py:5-204`) and Android (`jev/JevQuestions.kt:43-167`), while macOS lacks
   it entirely: `integrations/jev_mac/jev.py:90-99` sends a single `reply_strategy` question
   where the other two send the judge set. Its wording comes from upstream's judging kernel,
   which `NOTICE` already attributes to Finderchangchang.

The ports also disagree on values, not only on location: Windows exposes no tone or length
control at all, Android hardcodes a 40-character candidate cap, and macOS offers `40/70/100`
with three tones (`integrations/jev_mac/experience.py:10-11`,
`integrations/jev_mac/pipeline.py:9-13`).

## Decision

**Everything the three ports share lives at the repository root and is read as a file at
runtime. No port keeps an inlined copy.**

1. Root `references/` keeps model-facing prose. A new `references/data/` holds machine-read
   JSON, split by topic: `judge-questions.json` (the upstream-derived question set plus the
   action → next-step wording), `boundaries.json` (the no-contact terms and the stop
   condition), `relationship-enums.json` (stages, goal → scene, profile fields),
   `reply-preferences.json` (tones, tone guidance, lengths, candidate count),
   `trend-rules.json` (the CSV contract and its limits), `strategy-criteria.json` (the
   strategy vocabulary with both the TypeSafe English criteria and the DeepSeek Chinese
   ones), `payload-map.json` (which payload file belongs to which scene).
2. `integrations/jev_mac/demo_kline.json` moves to `examples/relationship_cases/`, so the
   case bundle — manifest, CSVs, illustrative candles — stays in one directory.
3. Windows adds the root files it reads to `integrations/jev_windows/jev.spec`'s `datas`.
   Android copies them into a generated `assets/` tree with a Gradle task and reads them
   through `AssetManager`. macOS needs no packaging change. Both non-mac ports also read the
   payload's `SKILL.md`, as macOS does. The payload's per-scene knowledge files are not part
   of this: only macOS offers an analysis-scene selector, so only macOS can name a scene.
   Windows and Android never had that content inlined, and still do not read it.
4. macOS gains the seven-question judge set inside its existing TypeSafe request:
   `integrations/jev_mac/jev.py:79-100` already assembles the payload, so the set joins the
   same `questions` object. Its answers feed the reply prompt as evidence; the macOS output
   UI does not change. A malformed judge answer is dropped, never fatal: the set informs the
   draft, so it must not cost the user the strategy decision.
5. Values are unified on macOS's sets — `40/70/100` and `稳健/会撩/直接` — **as data only**.
   Each port keeps the controls it already exposes; Windows gains no new UI.
6. A missing root file is a hard error. The inlined copies are deleted, not kept as fallback.
7. The guard is documentation: a `GLOSSARY.md` boundary rule, this ADR, and a wiring-state
   section in each port's `README.md`. No conformance test is added. The one mechanical aid
   is the CI trigger: `.github/workflows/platform-build.yml` now also runs on `references/**`
   and `examples/**`, so a change to the shared material rebuilds all three packages.

Android keeps one port-local addition: `JevQuestions.BACKGROUND_NOTE` is appended to every
question because only Android sends a `background` field. It is an adaptation, not a copy of
shared wording, so it stays where it is.

## Rejected alternatives

- **Build-time code generation** (a script turns the root files into Kotlin/Python
  constants). Single source of truth, but the artifact remains an inlined string and needs
  its own staleness guard — strictly more machinery than reading the file.
- **Windows reads a file, Android uses code generation.** Avoids the Android asset
  pipeline, but leaves two mechanisms for one concept and two places for the next
  contributor to look.
- **Keep the inlined copies as a fallback when a file is missing.** The copies would have to
  be maintained either way, so the divergence this ADR exists to remove would survive.
- **A cross-port conformance test** asserting every port's constants match the root file.
  The repository owner chose a documentation-only guard instead; the cost is under
  Consequences.
- **A dedicated root `shared/` directory** holding all cross-port material. Clearer
  semantics, but it moves `goutoujunshi/` — whose path is load-bearing for the payload and
  the upstream drift check — and adds a root allowlist entry plus a second vocabulary for
  the same idea.
- **A single `shared.json`** instead of per-topic files. One file is touched by every
  change, so every review carries unrelated noise.
- **Bring the seven-question set in as macOS-owned content rather than a root file.** It is
  upstream-derived, so its root-level home has to keep that attribution visible instead of
  absorbing it into this repository's own material.
- **Leave the seven-question set port-local.** Both ports would keep a verbatim copy of the
  same upstream wording, which is the defect being fixed.
- **Make all three ports expose tone and length controls.** Correct as product design, but
  it is a feature change rather than a de-duplication, and it drags two settings stores
  with it.

## Consequences

- **No mechanical guard.** A forgotten `datas` entry or a missing asset surfaces only after
  packaging. The failure mode is a hard error at first analysis rather than a wrong answer,
  which is what decision 6 buys. Accepted knowingly.
- **The Android APK grows** by the payload and the shared JSON, in exchange for three
  hand-maintained copies of the same rules.
- **Each port's `README.md` wiring claim can go stale**, which this repository has already
  paid for once (ADR-0004's correction note). The claim therefore states only which root
  paths that port reads, not how the reader is implemented.
- `scripts/validate_layout.py`'s `examples` entry still names
  `integrations/jev_mac/trend.py` as the runtime consumer; it is now all three ports and is
  updated in the same change.
- ADR-0004's consequence "Android and Windows are untouched: neither reads the payload, both
  inline their own digest" is superseded by this ADR. Its zero-delta payload policy is not:
  the ports read the payload, they still do not modify it.
- `references/data/payload-map.json` has one consumer today, macOS, because only macOS names
  a scene. It stays root-level data anyway: the selection is data rather than code, and it is
  the file a scene selector on another port would read.
- macOS behaviour changes in one visible way: the strategy request now carries the judge
  question set, so a TypeSafe decision costs more tokens than before.
- Windows and Android prompts grow by the shared tone document and `SKILL.md`, which is the
  same context macOS already paid for. Their candidate output, controls and screens are
  unchanged.
- Android's unit tests needed one more dependency (`org.json:json`): the JVM stubs in
  `android.jar` cannot parse the shared JSON that `core.SharedMaterial` reads. The device
  still uses the platform implementation.
- Where Windows and Android disagreed on wording, the fuller text won: the DeepSeek Chinese
  criteria and the action → next-step lines now carry the Windows phrasing, which keeps the
  constraining clauses Android's shorter version drops. Same principle as decision 5.
