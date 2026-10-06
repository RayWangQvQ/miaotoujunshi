# Review a batch as one editable block of text, and read the speaker off a line prefix

- Status: accepted
- Date: 2026-10-06

## Context

ADR-0022 restored the review surface, and built it as **one widget row per line**:
a three-state speaker and two line operations above, a text field below
(`panel_page.dart:557-653`). Two rows per line was a trade the 300dp panel forced,
and the comment says so. Measured in the code, a line costs roughly ninety points
of height. A ten-line capture wants nine hundred points of scrolling inside a
window that is three hundred and eighty tall.

Worse, the one operation the row form cannot express is the one the user reports
needing: **a missing line has no affordance at all.** Deleting a line and folding
it into the line above are both buttons; inserting one is not, and there is no
`insertLine` anywhere in the tree. The only way to add a line the recogniser
dropped is to re-photograph the screen.

ADR-0022 considered the obvious answer — the retired port's single multi-line box
with `我：` / `对方：` prefixes — and rejected it on two grounds:

> Proven on a device and the least code. Rejected because the prefix protocol is
> invisible — the old port had to teach it with a toast — and a pasted multi-line
> message silently becomes several messages.

Both objections are answerable now, and answering them is what this ADR is for:

- **Visibility is fixable without a toast.** The retired port taught the rule in a
  message that disappeared. A one-line hint plus a **fixed example line rendered
  above the box** puts the rule on screen for as long as the review is up. The
  shape is not new to the user either: the read-only transcript already renders
  `{who}：{text}` (`CopyKey.panelTranscriptLine`).
- **The paste failure is a consequence of one specific rule, not of the box.** It
  only happens if a line with no prefix is filed as *unknown*. Make a prefix-less
  line **inherit the previous line's speaker** instead, and a multi-line paste
  dropped right after `我：` is `我` all the way down — which is what the user
  meant.

What has to survive the change is ADR-0015: the third speaker is not decorative,
and admitting there is no author beats inventing one. `未定：` has to be a
first-class prefix, and it has to be written out on serialisation.

## Decision

**The review edits one block of text. The speaker lives in a prefix at the start
of each line, and the panel parses the block back into typed lines on confirm.**

1. **One block replaces the row list.** `PanelFrame.transcript` is serialised into
   a single string when the review is entered or re-entered, and parsed back into
   `List<PanelLine>` when it is confirmed. `_ReviewRow` and the per-line widgets
   go away.
2. **The prefix carries the speaker.** Each line starts with `我：`, `对方：` or
   `未定：`. **Serialisation always writes one, including `未定：`** — a line
   written without a prefix would parse as *inherit*, so a round trip would
   silently change its speaker. Round-tripping is the reason the prefix is not
   optional on the way out.
3. **A line with no prefix inherits the speaker of the line above; a first line
   with no prefix is `未定`.** This is what makes pasting safe (Context) and what
   lets the user drop the prefixes they do not care about.
4. **Parsing is tolerant: a speaker word, then a half-width or full-width colon,
   then optional spaces.** Hand-typed input is mostly half-width; a strict
   full-width match would downgrade a perfectly clear line to *inherit*. The
   match is anchored at the start of the line and nowhere else.
5. **A newline is a new message, and there is no escape for a newline inside
   one.** Chat messages that wrap are the minority; a hint sentence is cheaper
   than an escape nobody types.
6. **Parsing drops blank lines and trims each surviving line.** `_confirmTranscript`
   already drops empty lines (`conversation_runtime.dart:256`); the block form
   just makes blank lines easy to produce.
7. **The protocol stays a typed line list.** The panel parses; `PanelCommand`
   still carries `List<PanelLine>` and `confirmTranscript` is untouched, so
   `window_channel.dart` and `panel_window_test.dart` do not move. Parsing sits
   on the panel side because the panel owns the surface that produced the text.
8. **The two per-line operations are removed.** Deleting a line is deleting its
   text; folding it into the line above is deleting the newline between them.
   Both were buttons only because a row list cannot express either by typing.
9. **Changing a speaker keeps a shortcut.** Three buttons — 我 / 对方 / 未定 —
   rewrite the prefix of the line the caret is on, or of every line the selection
   touches. They are **disabled while the field has never been focused**: with no
   caret there is no line to act on, and guessing "the last line" would be an
   intention the user did not state. This is the one thing the row form gave away
   for free, so it is the one thing carried over.
10. **The protocol is made visible rather than taught.** A one-line hint stating
    the three prefixes and the inherit rule, plus a fixed non-editable example
    line above the box. ADR-0022 rejected the box partly because the retired port
    explained the prefix in a toast; a rule that stays on screen is not that.
11. **The review does not focus the field on entry.** Focus is still taken on
    pointer-down, as every editable field on the panel does today. Android's input
    method over the overlay has no device record (ADR-0022 Consequences), and a
    block that pulls the keyboard up the moment the review opens is a larger
    unknown than a field that waits for a tap.
12. **The block fills the space the review form has and scrolls inside it.**
    `Expanded` in the review column rather than a fixed `maxLines`, so the desktop
    panel uses the room it already has and the Android window still gets the growth
    ADR-0022 decision 15 gave it.
13. **The read-only transcript becomes the same block — non-editable, scrollable,
    same prefixes.** Otherwise tapping 「核对」 would reformat the same words
    underneath the user's caret, and the two shapes of one batch would disagree
    about what a batch looks like.
14. **Overwriting behaves exactly as it does today.** A pushed read carrying words
    still supersedes the batch being reviewed, and 「识别一次」 still replaces it.
    The block makes an edit more expensive to lose, but a guard here would
    contradict the amendment ADR-0022 already made about which pushed reads end a
    review, and a second confirmation on a surface built for speed is the wrong
    trade.
15. **Confirm stays disabled on a block with nothing left in it**, still showing
    `panelReviewNothingLeft`. Disabling a button beats refusing with an error
    (ADR-0022 decision 6).

## Rejected alternatives

- **Two boxes, one per side.** Removes the prefix protocol entirely and kills the
  paste problem outright. Rejected because it destroys the **order** of the
  conversation, and `renderTranscript` feeds the model an ordered transcript —
  which line followed which is most of what the analysis is about.
- **A strict full-width colon with no space.** Round-trips exactly what
  serialisation writes. Rejected because a hand-typed half-width colon silently
  downgrades the line, and a silent downgrade is the class of failure this ADR
  exists to remove.
- **An escape for a newline inside a message (`\n`).** Rejected: nobody types it,
  and it immediately needs an escape for the escape.
- **Keep the row list and add an insert button.** Fixes the missing-line case
  without touching the speaker protocol at all. Rejected on the size the user
  reported — the row form is ~90dp a line — and because the insert target is
  ambiguous in a list (*before or after which line?*) in a way a text caret is
  not.
- **Serialise the block into `PanelCommand` as a single string.** Moves parsing
  across the window boundary and into the codec, and `panel_window_test.dart:101`
  asserts a typed line list. The panel owns the surface; let it own the parse.
- **Auto-focus the field on entry.** Rejected for the reason in decision 11.

## Consequences

- **The review is lossy in exactly one direction: the speaker of a line whose
  prefix the user deletes.** It falls back to *inherit*, which is a defined
  answer rather than an error — but it is a change the user did not spell out.
- **A message that genuinely contains a newline cannot be written.** Accepted
  (decision 5).
- **`[OCR待核对]` and `reviewed` are untouched.** This changes how a person edits
  a batch, not what the batch claims. ADR-0024's rule still ends the marker on a
  reviewed batch; the analysis gate still reads `reviewed`.
- **The panel now owns a parser.** It is the first piece of parsing on the panel
  side of the engine boundary and needs unit tests of its own, separate from the
  widget tests.
- **The row form's widget tests are reformed, not deleted.** The two cases that
  only exercised the removed buttons go; the rest are re-expressed against the
  block.
- **Android's input method is still unverified**, and the block makes the review
  depend on it more than a row of small fields did. A device run is still owed
  (ADR-0014).
- **GLOSSARY's 「核对」 entry is rewritten** — it said 「逐行」 and named the two
  operations this ADR removes — and 「核对稿」 is added for the block itself.

## Amendment (2026-10-06): the hint and example line are removed, and the header is one row

Decision 10 shipped a one-line hint plus a fixed example line above the box, and
the two sentences above the block ate height on the one surface that has the
least of it — the 300dp panel. The user reported the header as dead weight: the
block is already *full of* `我：` / `对方：` / `未定：` prefixes, because
serialisation writes one on every line (decision 2), so the protocol is taught by
the content the user is about to edit rather than by a sentence they must read
first. The rule is no less visible this way — it is in front of their eyes — and
it is visible for as long as the block is.

The amendment changes two things:

- **The hint and the fixed example line are gone.** The title 「核对本轮对话」
  stays, as the one anchor that says which state the panel is in; nothing else
  stands between the title and the block.
- **The title and the three speaker buttons share one row**, and the buttons
  shrink to the label's own size. The buttons still read `我` / `对方` / `未定`,
  which is the whole of the prefix protocol, so they carry what the removed
  sentences carried.

Decision 10's *reasoning* — ADR-0022 rejected the box because a toast that
disappears teaches nothing — stands. What is withdrawn is only the *mechanism*:
a fixed example line above the box, replaced by the example the serialised block
already is.

### Floating-panel height and the keyboard (clarification)

The Android overlay is not an Activity, so `adjustResize` does not reach it and
there is no input-method inset to react to. The panel does **not** promise to
shrink out from under the keyboard; it pins to the top of the screen
(`SAFE_EXPANDED_TOP_DP`) and the user scrolls. The original answer to this was a
*ratio* of the screen height — shipped at `0.65`, then `0.50` — but the growing
window was itself the thing the user fought, and it is withdrawn for a fixed
height (see the amendment below). A device run is still owed (ADR-0014).

## Amendment (2026-10-06): a 删行 shortcut replaces the 未定 button, and the surface reads smaller

Two further corrections, both from the user's read of the running panel:

- **The 未定 button is gone, and 删行 takes its place.** Decision 9 shipped three
  speaker buttons — 我 / 对方 / 未定 — one per speaker. But 未定 is not a *state
  the user wants to reach by button*: it is the honest "no author" answer
  (ADR-0015), reached by typing the prefix or inheriting it. A shortcut whose
  whole job is to say "there is no author" earns its place less than one that
  deletes a line the recogniser read wrong — the exact missing-line case decision
  1 and the rejected row-list alternative both named. So the row is now 我 / 对方
  / 删行. The `未定：` prefix is untouched: serialisation still writes it
  (decision 2), and parsing still accepts it, so the state stays reachable
  without a button.

- **删行 deletes the caret's *physical* line, not the message.** The block shows
  one message per logical line, but a long message wraps into several physical
  lines. The user asked to delete the line they can *see*, so that is what it
  does: a non-last line goes with its trailing newline, a last line with its
  preceding newline, and the caret falls back to the start of the deleted span
  so a second tap removes the next line. It is a text edit — the block is the
  source of truth while the review is up — not a command to the engine. It is
  styled red, apart from the speaker buttons, because it is the one destructive
  action in the row. Like the speaker buttons it is disabled until the block has
  focus, and disabled again once the block is empty.

The visual change is one pass over the whole surface rather than a single token:
the block reads at `bodySmall` (it is the densest surface on the panel, and every
point of text it gives up is a line the user does not scroll to find), and the
bottom-row buttons — confirm, cancel, 识别一次, 详情, 核对, 分析 — share one
compact style (`visualDensity.compact`, `labelSmall`, a reduced height) so the
row stays on one line in a 300dp window. The title and shortcut row were already
at `labelSmall` from the first amendment.

## Amendment (2026-10-06): the panel is one fixed height, and the whole surface is tighter

The review's growing window — ADR-0022 decision 15, restated as a ratio cap in the
clarification above — is withdrawn outright. The user asked for the review panel to
be *shorter*, and then, when the arithmetic showed the ratio was still being fought
by the `EXPANDED_HEIGHT_DP` floor, for the height to **stop changing**:

- **The expanded panel is a fixed 320 dp in every state.** The review no longer
  asks the host for a taller window. The whole `setReviewing` / `onReviewChanged`
  / `_requestReviewSize` chain — Dart application layer, the panel window channel,
  and the Kotlin `REVIEW_HEIGHT_RATIO` + `reviewing` field — is deleted, not left
  as a no-op. A request that the host no longer honours is dead code that would
  read as "still growing" to the next reader. The collapsed ball is unaffected;
  the change is only that the expanded panel has one height instead of two.
  `EXPANDED_HEIGHT_DP` drops 380 → 320.

- **The whole surface reads tighter.** A new `AppSpacing.panel` inset (8 dp,
  versus the 12 dp `AppSpacing.card` the main-window pages keep) is what the
  header, note, banner, review form, transcript and bottom row all use now, and
  the review block's `minLines` drops 8 → 6. The panel is a 300 dp overlay, not a
  page, and every point of padding it pays is a point of the batch it does not
  show. The empty-state's `AppSpacing.page` is the one thing left roomier, because
  an empty panel is a prompt, not a list.

Why a fixed height beats a smaller ratio: `REVIEW_HEIGHT_RATIO` was only ever a
mitigation for a keyboard the overlay cannot see, and tuning it smaller ran into
the `EXPANDED_HEIGHT_DP` floor anyway — a "shorter review" that is shorter than the
ordinary panel is a state the user cannot aim at. One height for both states means
the panel never jumps under the user's hand, and the keyboard still gets the bottom
of the screen because the panel stays pinned to the top and scrolls.

## Amendment (2026-10-06): the shortcut buttons stop dismissing the caret they act on

On a device, tapping 我 / 对方 / 删行 did nothing. The buttons gate their own
`onPressed` on `_reviewFocus.hasFocus`, and a tap on a shortcut button was — from the
field's point of view — a tap *outside* the field. That fired the field's
`onTapOutside`, which called `_releaseInputFocus` and unfocused the block, flipping
`hasFocus` to false and disabling the three buttons in the same frame the tap landed
on them. The buttons were disabling themselves with the very gesture that pressed
them.

Two changes, one cause:

- **The whole form is one `TextFieldTapRegion`.** The title row, the shortcut row
  and the block share one `EditableText` tap group, so a shortcut tap is a tap
  *inside* the group and never reaches the field's `onTapOutside`. The buttons read
  the caret instead of killing it.
- **The shortcut buttons refuse focus.** Each is wrapped in `Focus(canRequestFocus:
  false)`: a button that took focus would steal it from the block and reach the same
  self-disabling by a second route. The tap is kept; the focus is refused, so the
  caret stays in the block.

The `hasFocus` gate itself is unchanged and still right — no caret, no line to act
on — it is only the *cause* of a lost focus that was wrong, and now a shortcut tap
no longer loses it.

## Amendment (2026-10-06): the panel clamps its type, so no text on it out-reads a body line

The candidate page still read too large: the review form had been brought down to
`bodySmall`, but the candidate draft read at `bodyLarge` (16 px) and its reason and
tradeoff at `bodyMedium`. Rather than shrink the shared widgets by hand — and leak a
"panel" special-case into a component the detail page also uses — the panel clamps its
whole type scale:

- **The panel pushes its own theme down the tree.** `PanelPage` builds a clamped
  `ThemeData` (`_panelTheme`): `bodyLarge` is set to `bodyMedium` (16 → 14 px) and
  `bodyMedium` to `bodySmall` (14 → 12 px), and it is applied with a `Theme` widget so
  the shared `CandidateCard` and `LabeledBlock` — which read `Theme.of(context)`, not a
  parameter — pick it up. This is the "maximum size" the user asked for: nothing on the
  overlay can out-read a body line, and any text added to the panel later inherits the
  cap for free. The main window's pages keep their own scale, because they never see
  this theme.
- **The candidate card tightens its inset on the overlay.** `CandidateCard` and
  `LabeledBlock` gain a `dense` flag, set only by the panel: the card's inset drops to
  the panel's 8 dp (`AppSpacing.panel`) and its reason/tradeoff label reads at
  `labelSmall`. The detail, knowledge and trend pages leave `dense` false.

`bodySmall` is the floor and is untouched — the review block, the note and the
header's conversation line already read it and have nowhere lower to go.
