# Unify the speaker token, and leave the model's vocabulary at the boundary

- Status: accepted
- Date: 2026-10-03

## Context

The shared payload states the speaker vocabulary once.
`miaotoujunshi/references/data/trend-rules.json:4` holds `"senders": ["me", "other"]`, and
`miaotoujunshi/examples/relationship_cases/manifest.json:4` maps those same two keys to
"用户" and "对象". Both desktop ports' CSV and trend paths already honour it and validate
against it: Windows `core/trend.py` checks the shared `SENDERS` set and reports
`sender（me／other）`, and macOS `trend.py` raises `sender 只接受 me／other；请先确认双方身份`.
Android speaks `me`/`other` from the accessibility adapter through to the judge request.

Everywhere else the three ports disagree. Windows' main path says `her` — `main.py`,
`core/goutou.py`, `core/draft.py`, `core/questions.py`, `core/experience.py`,
`app/ocr.py`, `app/review.py`, `app/overlay.py`, `app/debugwin.py`, `app/cloud_ocr.py`.
macOS' says `them` — `core.py`, `vendor/perception.py`. Each port converts at its own
edges, which is why a new shared file that assumes one spelling would read wrong on the
other two without failing anything.

Scoping the change surfaced three things the ticket did not anticipate.

1. **`them` is not only an internal token; it is asked of a third party.** macOS'
   cloud-OCR system prompt requests `side（me/them/unknown）`, states that the right side
   is `me` and the left is `them`, and gives `{"side":"them","text":"你好"}` as the worked
   example (`integrations/jev_mac/cloud_ocr.py:118-127`). Windows parses the same
   vocabulary back — `app/cloud_ocr.py:24` accepts `("me", "them")` — and converts
   afterwards. The token is not this repository's to rename unilaterally.

2. **The ports do not agree on how many speakers exist.** Windows produces a third value,
   `gray`, for text that does not sit on a bubble, and `app/ocr.py:97` keeps it out of the
   message stream, where it survives only in the debug overlay. macOS produces `unknown`
   for text that cannot be anchored to one side (`vendor/perception.py:405`), and that
   value **does** reach the message stream — `core.py:106` renders it as 说话人待确认.
   Android has no third value at all: `ChatAppAdapter` decides by horizontal position and
   always commits to one side.

3. **macOS' token lives inside vendored code.** `integrations/jev_mac/vendor/` is
   third-party MIT code — `vendor/LICENSE`, Copyright (c) 2026 eatmoreduck — holding
   `perception.py` and `fill.py`, including the docstring's probed facts about WeChat 4.1's
   window layout and the calibrated side-anchoring thresholds that rest on them.

## Decision

**One token between the application's own parts: `me`/`other`. One token at the model
boundary: `them`/`unknown`. Vendored code is not edited; the conversion stays on this
repository's side of the line.**

1. **Every boundary between the app's own components speaks `me`/`other`.** Windows' `her`
   and macOS' `them` are renamed — including the display maps, the manual-entry parsers, the
   OCR classifiers and the debug overlays, because a half-renamed port is worse than either
   consistent state.
2. **The cloud-OCR prompt keeps asking for `them`/`unknown`, and each port converts
   immediately after parsing.** The prompt addresses a model that has a prior for those
   words. Rewriting it would change speaker-attribution accuracy, which is a separate thing
   to measure and re-accept, not a rename.
3. **A third value survives wherever a port genuinely produces one.** `me`/`other` is the
   shared two-value contract; a port-local "cannot tell" is permitted and must never be
   silently folded into either side, because folding it invents an attribution the port did
   not make. macOS' `unknown` therefore stays `unknown` inside macOS.
4. **`vendor/perception.py` is not modified.** The conversion from its `them` to this
   repository's `other` happens at the call site, so the vendored directory keeps meaning
   "third-party code as received".
5. **Android changes nothing.** It is already `me`/`other` and already has no third value.

## Rejected alternatives

- **Rename the model's vocabulary in the same change.** Would leave exactly one vocabulary
  in the system. Rejected because it trades a measurable property for tidiness: `them` is an
  ordinary English word the model reads reliably, `other` is not, and re-establishing the
  accuracy of speaker attribution is an experiment with its own pass/fail.
- **Split the prompt question into its own ticket.** Keeps this ticket to mechanical
  renames, and the risk is genuinely separable. Rejected because the answer here is to
  *not* change the prompt, so a separate ticket would have nothing to do; the boundary rule
  is what needs recording, and it belongs with the vocabulary it constrains.
- **Convert only in the CSV path, as today.** That is the status quo, and it is precisely
  what makes a new shared file read wrong on two ports. Rejected because the divergence this
  ticket exists to remove would remain.
- **Edit `vendor/perception.py` directly.** MIT permits modification with the notice
  retained, and one edited return statement is smaller than an adapter. Rejected because the
  directory's whole value is that it is unchanged third-party code: after an edit, the
  module's own probed facts and this repository's adaptations become indistinguishable, and
  the next person comparing against upstream has to diff to find out which is which.
- **Give Android a third value, for symmetry with the desktop ports.** Rejected because
  Android cannot honestly produce one: it infers the speaker from bubble geometry with no
  confidence signal, and a fabricated `unknown` would be a third value that never fires.
- **Make `gray` and `unknown` the same token while renaming.** Rejected as a behaviour
  change smuggled into a rename: Windows' `gray` is filtered out of the message stream and
  macOS' `unknown` is not, so giving them one name would hide a real difference.

## Consequences

- **The vocabulary is now stated in two places and both must stay consistent.**
  `trend-rules.json` and `manifest.json` hold the shared two-value contract; the cloud-OCR
  prompt holds the model's three-value one. This ADR is the only thing linking them, and
  there is no mechanical guard — the same documentation-only stance as ADR-0005.
- **Exactly three conversion sites exist**, and nothing else has a reason to see `them`:
  Windows `app/cloud_ocr.py`, macOS `cloud_ocr.py`, and the macOS perception call site.
- **macOS' `unknown` reaches the judge prompt as `unknown`.** The shared contract's two
  `senders` do not describe it, so a consumer that assumes two values will meet a third.
  This is a pre-existing condition, now documented rather than latent.
- **Windows' `gray` and macOS' `unknown` remain two names for one idea**, with different
  downstream behaviour. Unifying them is a separate question and is not implied here.
- **The Python suite covers the rename only incidentally.** Windows' in-file assertions
  (`core/draft.py:248-251`) and `check_ui.py` fixtures spell `her` literally, so they move
  with the change; the 108 cases plus a device-acceptance rerun per port remain the evidence
  that nothing else broke. No test asserts the vocabulary itself.
- **This is the last functional change made on the frozen ports.** ADR-0007 freezes them
  until their replacements are accepted, and ADR-0014 declares a port replaced only after
  device acceptance — so each port's rename is verified before that port stops being built.
- **A future shared file may assume `me`/`other`.** That is the point of the decision:
  until this change, it could not, on two of the three ports.
