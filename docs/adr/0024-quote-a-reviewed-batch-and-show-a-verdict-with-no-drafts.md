# Quote a reviewed batch without the per-line doubt, and keep it on the panel when the verdict has no drafts

- Status: accepted
- Date: 2026-10-06

## Context

On a device, 「识别一次 → 逐行核对 → 确认 → 重新分析」 needs two presses to produce
anything:

1. 「识别一次」 photographs the screen and lands the batch in the review state (ADR-0022
   decision 7).
2. 「确认」 lands the review. The panel shows 「原文与说话人已人工核对。」 and the
   confirmed lines.
3. 「重新分析」 shows 「正在分析当前会话…」, and then goes back to
   「原文与说话人已人工核对。」 with **nothing on the panel** — no drafts, and the batch
   the user just confirmed is gone too.
4. Pressing 「重新分析」 a second time produces the drafts.

Two independent defects compose into that. Neither is the review failing to land: an
instrumented run of the whole path shows the runtime publishing `advice`, the reviewed note
and the transcript, all three, in the right order.

**Defect one — a confirmed batch is still handed to the model as unconfirmed.** The runtime
writes `confidence: double.nan` on every captured line (`_capturedLines`), and
`renderTranscript` turns a non-finite confidence into `[OCR待核对]`. So the transcript the
model reads marks *every* line of a batch the user has just read and corrected as
unvouched-for. ADR-0022 decision 4 required exactly this — "the marker says *this text came
out of pixels*; `reviewed` says *a person read this batch*" — and decision 16 repeated it.
The consequence nobody priced was the model's: told that every line is doubtful, a model
that is asked to draft a reply answers with none. `rankCandidates` has a branch for it
(`candidates.isEmpty → RankingStatus.notNeeded`), and `rewriteSnapshot` even refuses on it
with 「本轮建议不回复，无需改写」 — so zero candidates is a state the domain reaches on
purpose, not a parse failure.

**Defect two — the panel cannot render 「本轮建议不回复」.** `panel_page.dart` reads:

```dart
if (reviewing)              reviewForm
else if (advice == null && transcript.isNotEmpty) transcript
else if (advice == null)    emptyState
else                        one card per candidate
```

An advice is not null, so the transcript branch is skipped; there are no candidates, so the
`else` draws nothing. The panel answers a legitimate verdict with a blank body, and the one
thing on it that belongs to the user — the batch they just confirmed — is withdrawn by the
very analysis they asked for. That is the panel half of the same mistake ADR-0018's first
device run made: a result that worked looking exactly like a result that found nothing.

## Decision

**A review ends the per-line doubt, and the panel keeps the batch whenever it has no drafts
to draw.**

1. **A reviewed batch is quoted without `[OCR待核对]`.** `Snapshot.fromCaptured` renders
   the transcript from the lines with the recogniser's confidence taken off them when
   `reviewed` is true. Everything else is untouched: `capturedLines` keeps the confidence
   (the anti-injection filter and the signature read it), and `source` stays `ocr`, so the
   model is still told where the words came from. A `说话人待确认` line keeps its label —
   the user chose *not* to attribute it, which is a different fact (ADR-0015) and one a
   review confirms rather than resolves.
2. **The doubt is a claim about the text, not a fact about the source.** What ended is the
   sentence "the engine cannot vouch for this line". After a person has typed the line
   themselves, the engine is quoting that person, not the recogniser — and ADR-0022 decision
   4 was right that confirming is not a claim the recogniser was right, which is why
   `source` does not move.
3. **The batch stays on the panel when the verdict has no drafts.** The transcript branch
   fires on `advice == null || advice.candidates.isEmpty`. The verdict itself stays reachable
   through 「详情」, which the panel already offers whenever there is an advice.
4. **The runtime builds the domain snapshot in one place.** `_snapshotOf` is now the only
   door from a `ChatUiSnapshot` to a `Snapshot`, and both the analysis and `_refusalRemedy`
   go through it. `_refusalRemedy` used to render the transcript itself, so it kept marking a
   confirmed batch as unconfirmed and offered 「去核对」 for a batch the user had already
   confirmed — on the refusal that a review cannot fix at all (a background that is too
   long).

## Rejected alternatives

- **Leave the marker and refuse an advice with no candidates instead.** Treat zero
  candidates as the model failing to answer and throw, so the panel shows 「模型未返回候选，
  请重试」. Rejected: `RankingStatus.notNeeded` is the domain's own word for 「本轮建议不
  回复」, which is a verdict about the *conversation*, not a defect in the call. Refusing it
  would delete a legitimate answer, and it would still leave the panel unable to say
  anything when the domain does reach it.
- **Keep the marker and add a note explaining the empty result.** Rejected: it treats the
  symptom. The model was told the batch was untrustworthy after the user had vouched for it;
  the honest fix is to stop saying that.
- **Always show the transcript, below the drafts.** Rejected for now: it is a layout change
  on a 300 dp Android overlay that is already tight, and the case that hurts is specifically
  the one where there are no drafts to show. Revisiting it does not need this ADR.
- **Drop the marker in the runtime instead of the domain** (`_capturedLines` taking a
  `reviewed` argument). Rejected: the transcript is the domain's own output and the thing the
  model reads, so the rule belongs where the rendering is; done in the runtime it would have
  left `_refusalRemedy` rendering the same batch a second way.

## Consequences

- **The confirmed batch reaches the model as the user left it.** The words are the user's,
  the source is still a screenshot, and the gate still short-circuits on `reviewed`
  (ADR-0022 decision 2) — so nothing about the refusal path moves.
- **A verdict with no drafts is now visible**: the batch, the note, and 「详情」. It reads as
  「本轮建议不回复」 rather than as a failed analysis.
- **One fewer way for 「重新分析」 to look like it did nothing.** What remains of the
  reported symptom is the model's own judgement, which is now at least visible.
- **ADR-0022 decisions 4 and 16 are amended in place**, and their text is left standing: the
  distinction they drew between the marker and the flag was right, and what changed is which
  of the two the model is told after a review.
- **Two doors now render the same batch the same way.** ADR-0022 decision 13's remedy is
  decided over the same transcript the analysis sends, so 「去核对」 can no longer be offered
  for a batch that has already been confirmed.
