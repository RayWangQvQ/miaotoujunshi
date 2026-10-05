# Guess the speaker from line geometry, and mark the guess by its provenance

- Status: accepted
- Date: 2026-10-05

## Context

The accessibility tree tells us which side a message came from, because a bubble is a
container with an edge (`ChatAppAdapter.kt` reads left-aligned bubbles as `other` and
right-aligned ones as `me`, and Feishu's read-receipt strip as the only usable signal). OCR
gives us nothing of the sort. `OcrLine` is a string and a rectangle: an OCR pass over a whole
frame yields text lines, and "who said this" is not a property text carries. A bubble also
wraps into several lines, so the unit that could carry a side is not even the unit a
recogniser returns. The retired port grouped lines into pseudo-bubbles by line spacing
(1.2× the previous line's height) and filed **every** group as the other party, with the
panel note 「OCR 未分边，把全部消息当作对方所说」.

Three pieces of the domain already anticipate better than that:

- `Speaker` is three-valued — `me`, `other`, `unknown` — and `speakerLabel` renders the third
  as 「说话人待确认」. ADR-0015's stated point is that inventing an author is worse than
  admitting there is none.
- A line whose OCR confidence is below `ocrConfidenceThreshold` (0.8) is rendered with
  `[OCR待核对]`, so that both the user and the model can discount it (`snapshot.dart:10-15`).
- `prompts.dart:64` already tells the model "OCR side judgement is only a clue; the speaker
  may have been human-confirmed, or may come from automatic recognition the user turned on".

And two pieces of it do not work on Android:

- **The `[OCR待核对]` marker can never fire.** `conversation_runtime.dart:183` builds every
  `CapturedLine` without a confidence, and a null confidence means "not from OCR" — so a line
  that came from a photograph is presented to the model as machine-read-and-trusted. The
  other path is hardcoded: `RetainedCaptureService.recognize()` sends `confidence: 1.0` with
  the comment "ML Kit's Android text API does not expose per-line confidence".
- **`Speaker.unknown` is a trap on this path.** `prompts.dart:366` refuses a transcript whose
  every line is unattributed (`allLinesUnconfirmed`), so filing a manual whole-frame capture
  as `unknown` would refuse the very conversation the user just asked us to read — unless
  they manually confirmed each line, and the panel surface for that does not exist.

## Decision

**The side is guessed from line geometry, written as a plain `me`/`other`, and the guess is
marked by making the line's provenance visible rather than by inventing a fourth state.**

1. **The guess is geometry, one generic formula.** A line's rectangle, measured against the
   content region (the frame's width minus its left and right safe margins), decides which
   side it leans to. No per-application table: the applications this path serves are the ones
   with no adapter, so there is no list to register them in.
2. **The result is `me` or `other`, and nothing new is added to the model.** No fourth
   `Speaker` value, no provenance field on `CapturedLine`. ADR-0015 deliberately left the
   model's vocabulary at the boundary, and a state that only this path produces would be one
   the prompt, the transcript renderer and the strategy step all have to learn.
3. **What marks the guess is the line's provenance.** The runtime stops discarding the OCR
   provenance: machine-read lines carry it, so `[OCR待核对]` fires for them. The `1.0`
   hardcode is corrected the same way — a line the engine cannot score is not a line the
   engine scored perfectly, and "not from OCR" must stop being the answer for a line that is.
4. **The old behaviour survives as the fallback.** When geometry cannot separate the sides —
   every line aligned the same way, which is exactly Feishu's layout — the grouping falls
   back to filing everything as the other party and says so in the panel note, as the retired
   port did.
5. **The thresholds are calibrated on a device and pinned by a synthetic fixture.** Two or
   three representative applications (an unadapted chat application, one that aligns
   everything left, one that does not) fix the constants; a fixture of synthetic rectangles
   then locks both the 1.2× line-gap grouping and the side threshold, per ADR-0011.

## Rejected alternatives

- **File everything as `unknown` and let the user correct it.** The most honest option, and
  the one that needs no heuristic at all. Rejected because it collides with
  `allLinesUnconfirmed`: a wholly OCR'd conversation would be refused analysis, and the panel
  has no line-by-line corrector to resolve it with. A path that produces nothing analysable
  is not more honest than a path that produces something analysable and labelled.
- **Add a provenance field to `CapturedLine`.** Cleaner in principle — the model could be told
  "this side is a guess" separately from "this text is uncertain". Rejected for now: it
  reverses ADR-0015's boundary for a distinction the prompt line in `prompts.dart:64` already
  draws in words, and it would need a Kotlin wire field behind it. If experience shows the
  model over-trusting guessed sides, this becomes an ADR of its own.
- **Mark every OCR line with a fixed low confidence.** The marker can then never be missed.
  Rejected because a marker on every line is a marker on no line: the transcript loses the
  ability to say which lines are doubtful, which is the entire value of the threshold.
- **Guess from the side's alignment *tendency* first, and only split when the frame shows
  both.** Attractive, and it is what §4's fallback does in practice, but as a *replacement*
  for the threshold it needs the same calibration while adding a second thing to get wrong.

## Consequences

- **A wrong guess is now a confident `我` in the transcript.** Nothing in the pipeline
  distinguishes it from a tree-read line, and the only counterweight is
  `prompts.dart:64`'s instruction to treat OCR sides as a clue. That sentence is
  load-bearing from this ADR onward.
- **The panel note and the `[OCR待核对]` marker now say different things on purpose.** The
  note is about the whole capture ("the sides could not be split"); the marker is about one
  line ("treat this line's text with care"). A reader who collapses them will think a
  correctly-guessed capture is untrustworthy, or a misrecognised character is a mis-guessed
  side.
- **Calibration is device work, and it is the most expensive thing in this change.** Two or
  three applications fix constants that no unit test can argue for; the fixture only stops
  them from moving afterwards.
- **Android's per-line confidence remains absent.** ML Kit reports none for Chinese text, so
  the marker must be driven by provenance rather than by a score. A future engine that does
  report one should not be assumed to agree with this decision's mechanism.
- **Superseded: the retired port's blanket attribution.** `ChatCaptureService.kt:476` filed
  every whole-frame line as the other party without attempting a split. That is now the
  fallback rather than the rule.
