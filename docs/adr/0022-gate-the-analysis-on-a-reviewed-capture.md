# Gate the analysis on a reviewed capture, and give the review a surface on the panel

- Status: accepted
- Date: 2026-10-06

## Context

ADR-0018 restored the manual whole-frame capture, and with it the only way in for an
application with no adapter — Douyin is the one the report names. On a device it does not
work, and it cannot: **every manual capture is refused by the domain, whatever it read.**

The chain, all of it checkable in the code:

- `conversation_runtime.dart:381` writes `confidence: double.nan` on every line of a
  capture, because the source of the analysis is the capture.
- `renderTranscript` (`snapshot.dart:152`) treats a non-finite confidence as *below*
  `ocrConfidenceThreshold` and appends `[OCR待核对]` — so the marker lands on **every**
  line, not on the doubtful ones.
- `allLinesUnconfirmed` (`snapshot.dart:200`) is then true by construction, and
  `checkAnalysable` (`prompts.dart:364`) throws 「当前对话全部待核对，请先确认说话人和原文，
  再生成回复」.
- **The confirmation that sentence asks for has no surface.** The transcript the panel
  shows is read-only text (`panel_page.dart:444`), the only buttons are
  「识别一次」/「重新分析」/「详情」, and the refusal is published as a note and nothing else
  (`conversation_runtime.dart:348`). Tapping 「重新分析」 again re-runs the same path and
  fails identically. The path is a dead end for the user and was never exercised by a test
  — `conversation_runtime_test.dart` asserts that the transcript appears and stops there.

Three documents disagree with the code, and one of them predicted this:

- **ADR-0019's own rejected alternatives** say a marker on every line is a marker on no
  line, and reject 「mark every OCR line with a fixed low confidence」 on exactly that
  ground. The implementation marks every line.
- **ADR-0019 rejected filing a capture as `unknown`** because `allLinesUnconfirmed` would
  refuse 「the very conversation the user just asked us to read — unless they manually
  confirmed each line, and the panel surface for that does not exist」. The same refusal
  now arrives by a different route (text doubt rather than attribution doubt), and the
  missing surface is what the user hit.
- **ADR-0018's Consequences** put it plainly: 「The per-line corrector the retired port had
  is not restored by this ADR… a mis-guess can be read but not corrected. Tracked as its own
  item — it is the one piece without which ADR-0019's marking is a warning nobody can act
  on.」 This is that item.

The retired port had the surface, and had it as a *structural* gate: `OverlayController.showReview`
(`9629f3b^`) put an editable multi-line box on the panel under 「核对本轮对话」, and
`ChatCaptureService.reviewSnapshot` routed **every** snapshot through it —
`runAnalysis()`'s only caller sat inside the confirmation callback.

## Decision

**The analysis is gated on a snapshot-level fact that the user reviewed this batch, and the
review is a surface on the panel.**

1. **A review surface is restored, and it lives on the panel.** The panel is the only
   surface visible over the application being read — the user is looking at Douyin, and the
   words being checked are still on the screen behind it.
2. **The gate reads the batch, not the lines.** `checkAnalysable` short-circuits
   `allLinesUnconfirmed` when the snapshot has been reviewed. A user who reads a capture and
   says "that is the conversation" has answered the question the refusal asks, even if they
   changed nothing.
3. **`reviewed` is a field on `ChatUiSnapshot`** (`miaotou_capabilities`), and a field on the
   domain's `Snapshot` beside `source`. The capability layer is where it is born — a capture
   is produced there — and the domain is the only place the gate lives, so it needs the value
   to travel the same road as the lines.
4. **The line markers stay exactly as they are.** Every line of a machine-read batch keeps
   `[OCR待核对]`, and the model keeps seeing it. The marker says *this text came out of
   pixels*; `reviewed` says *a person read this batch*. They are different claims and the
   panel must not conflate them (ADR-0019's Consequences warned about exactly this
   collapse).

   **Amended:** [ADR-0024](0024-quote-a-reviewed-batch-and-show-a-verdict-with-no-drafts.md)
   ends the marker once a batch has been reviewed — a reviewed batch is quoted without
   `[OCR待核对]`, while `source` stays `ocr`. The distinction this decision drew was right
   and still holds for an *unreviewed* batch; what was wrong was keeping the doubt after a
   person had taken it on, which told the model a confirmed batch was unvouched-for and cost
   the reply. See also decision 16, amended the same way.
5. **The review is per line: a three-state speaker and the text.** Each line gets 我 /
   对方 / 不确定 and an editable body, because the domain already carries three speakers
   (`speakerLabel` renders the third as 「说话人待确认」) and ADR-0015's point is that
   inventing an author is worse than admitting there is none. A two-state toggle would force
   an attribution on a line the user cannot attribute.
6. **Lines can be deleted and merged into the previous one.** OCR groups by line spacing
   (ADR-0019 decision 1), so both failure modes are ordinary: a timestamp or a system hint
   becomes a pseudo-bubble, and one wrapped message becomes two. Merging appends the line's
   text to the one above with a single space — the rule `_Group.text` already uses — and
   keeps the upper line's speaker. Confirming a batch with no non-blank line left is
   refused by disabling the button rather than by an error.
7. **A capture enters the review state immediately.** The gate would refuse the first
   analysis of an unreviewed batch every time, so offering that analysis first would be a
   round trip that is known to fail.
8. **The geometry guess is pre-filled.** The panel already guessed a side per line and the
   note above it already says the guess may be wrong; making the user re-attribute every
   line would charge them for the heuristic's mistakes. What the review adds is the chance
   to fix the ones that are wrong.
9. **Confirm lands the review; the analysis stays the user's next action.** The retired port
   fused the two (「确认原文并分析」). Keeping them apart is what the setting
   `autoAnalyze` already implies, and it lets the user review a capture without spending a
   model call.
10. **The review state owns the panel's bottom row.** While reviewing it offers 取消,
    确认 and 「识别一次」, and hides 「重新分析」 — a button that cannot succeed is a
    button the user will press. 「识别一次」 stays because re-photographing is the answer
    to a capture that read badly, and it is the same button as everywhere else, not a
    second one beside it.
11. **Cancelling drops the batch.** What was read is thrown away and the panel returns to
    having nothing, which is the state it was in before the capture. Keeping the text and
    the gate both would leave the panel showing words it refuses to use.
12. **The review is re-enterable.** A 「核对」 button sits on the panel whenever the batch
    on it has lines, so a wrong character noticed after confirming does not require
    re-photographing the screen.
13. **A refusal carries its own way out.** `PanelNote.remedy` stops being a
    `PermissionKind` and becomes a small sealed type, so the 「全部待核对」 refusal can
    offer 「去核对」 exactly as the accessibility refusal offers 「去开启」 (ADR-0021
    decision 8). A refusal that names an action and cannot take the user to it is the defect
    this ADR exists to remove.
14. **The reviewed lines and the flag cross on one typed command.** `PanelCommand` gains a
    line list and the protocol gains `confirmTranscript` / `cancelReview` / `openReview`;
    the codec serialises the lines as a JSON array, the way it already serialises a note as
    a map. Two down-streams and one up-stream stay two and one.
15. **The panel grows for the review state, by screen ratio, on Android only.** The Android
    overlay is 300×380 dp and does not resize for the input method, so editing in it would
    be editing through a keyboard. The desktop windows are 420×620 and already have the room.
16. **The model's vocabulary is untouched.** `Snapshot.source` stays `ocr` and no new field
    reaches the prompt: `prompts.dart:64` already tells the model that
    「说话人可能经过人工核对」, which is as much as the pipeline can honestly say.

    **Amended:** [ADR-0024](0024-quote-a-reviewed-batch-and-show-a-verdict-with-no-drafts.md)
    takes the marker off a reviewed batch. `source` is still `ocr` and no field was added,
    so the vocabulary is still untouched in the sense this decision meant; what changed is
    that a reviewed batch is quoted as the user left it rather than as the recogniser left
    it.
17. **The review surface serves any batch, not only a capture.** `PanelFrame.transcript`
    stops meaning "what the last whole-frame capture read" and becomes "the lines behind the
    batch on the panel": the runtime publishes them for a tree read too. Without that, a
    tree read whose every line is unattributed has no reachable way out — the refusal would
    name a review the panel could not show — and the standing 「核对」 button could not exist
    on the paths that need it.
18. **An analysis reads the batch the user reviewed, not a fresh read.** `_analyze` prefers
    a reviewed snapshot over a new tree read. It re-reads the tree first for every other
    case, so without this the confirmation would be discarded by the very next analysis and
    the reviewed batch would be replaced by an identical unreviewed one. A new read still
    wins as soon as the platform pushes one, which is how a reviewed batch stops being
    current when the conversation moves on.

## Rejected alternatives

- **Delete the `double.nan` and let the capture be analysed.** The cheapest repair by far,
  and it is what ADR-0019's rejected alternative implies. Rejected because it answers only
  half the report: the user's second sentence is that the recognised text cannot be
  edited, and a mis-guessed side that can be read but not corrected is the open item
  ADR-0018 named. It would also leave `[OCR待核对]` firing nowhere on Android — which is
  the state ADR-0018 called out as a defect and ADR-0019 fixed.
- **Make `reviewed` the only gate and delete `allLinesUnconfirmed`.** Tidier, one
  question in one place. Rejected because the tree-read path never enters the review state,
  so a read whose every line is unattributed would stop being refused.
- **File every capture as `Speaker.unknown` and let the review fix it.** The most honest
  option and the one ADR-0015 leans toward. Rejected for the reason ADR-0019 gave: it
  throws away a hint that is usually right, and every line then costs the user a tap.
- **One multi-line box with `我：`/`对方：` prefixes, as the retired port had it.** Proven on
  a device and the least code. Rejected because the prefix protocol is invisible — the old
  port had to teach it with a toast — and a pasted multi-line message silently becomes
  several messages.
- **Confirm-and-analyse in one tap.** Rejected only because it spends a model call the
  user did not ask for, and because it makes the two actions impossible to tell apart when
  the analysis fails.
- **A standing 「核对」 button as the only way in.** Rejected: the first analysis of every
  capture would then be a known-failing round trip.
- **Carry `reviewed` in `Snapshot.source` or in the note text.** Rejected: one word
  would then mean both how the text was obtained and who has looked at it, or a string would
  become state that silently changes behaviour when the copy is reworded.
- **Restore the retired port's blanket gate — every snapshot through review.** Rejected:
  the tree-read paths are not marked and are not what the report is about, and a
  confirmation demanded on every foreground change is a confirmation nobody reads. What is
  restored is the surface and the gate on the path that needed it.
- **Grow the window on all three ports.** Rejected as scope: the desktop panel is not the
  one that is too short, and resizing it would move the anchor the placement's `dy` is
  measured against.

## Consequences

- **One function now holds two questions.** `checkAnalysable` refuses an unreviewed batch
  whose every line is doubtful, and refuses nothing once the batch has been reviewed. The
  two readings are one line apart and must stay legible.
- **A reviewed batch is analysed even if the user changed nothing and the text is wrong.**
  That is the decision: the batch carries a person's word, and the marker still tells the
  model the text came from pixels.
- **`PanelNote.remedy` is no longer a permission.** Anything that reads it to mean
  "a system page is the fix" must now say which remedy it is; the permission case is one
  variant of two.
- **The panel window changes size while reviewing.** `AndroidOverlayHost` grows it by a
  ratio of the screen, so the same `panel.placement` describes a taller window while the
  review is up, and the panel engine's own expanded/collapsed switch now has a third state
  to keep out of its way.
- **Android's input method on the overlay remains unverified.** The only mechanism is
  clearing `FLAG_NOT_FOCUSABLE` (`AndroidOverlayHost.kt:131`); there is no
  `FLAG_ALT_FOCUSABLE_IM` and no `WindowInsets` handling anywhere in the port, and the
  candidate draft's `TextField` — the only editable control that existed before this — has
  no device record either. Per ADR-0014 this needs a device run, and a taller window is a
  mitigation rather than a guarantee.
- **The review state has its own bottom row and its own layout.** Two layouts on one panel,
  each needing its own widget test, which is the cost of hiding a button that cannot
  succeed.
- **The panel now shows what a tree read read.** Decision 17 puts the lines on the panel for
  every source, so a read that used to be invisible until an analysis returned is now
  visible before one is asked for. The empty state is left for the case it describes —
  nothing read at all.
- **A reviewed batch can outlive the screen it came from.** Until the platform pushes a new
  read, an analysis answers about the batch the user confirmed, which may be older than what
  is in front of them. That is the point of confirming, and the fill guard still compares
  against a fresh read before anything is written into an input box.
- **The automatic path still does not ask.** `autoAnalyze` keeps analysing a tree read
  without a confirmation, as it did before; the retired port's 「no confirmation, no
  analysis」 is deliberately not restored.

**Amended (2026-10-06): a conversation-identity event must not end a review.** Decision 18
says "a new read still wins as soon as the platform pushes one", and the first
implementation read that as *every* pushed read. Android's `AndroidConversationEvent` maps
to `ChatUiSnapshot(lines: const [])` — it fires on foreground flips and read-only changes
and carries no words at all — and it was ending reviews: tapping a line to edit it, and the
accessibility event that tap caused, wiped the batch out from under the user. `_acceptSnapshot`
now treats an empty read as an identity update only (it moves the panel's "current
conversation" and nothing else), and only a read with words in it supersedes the batch being
reviewed. The distinction is *has words / has none*, not *pushed / pulled*.
