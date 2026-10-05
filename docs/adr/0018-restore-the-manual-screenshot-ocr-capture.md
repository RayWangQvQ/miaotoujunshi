# Restore the manual screenshot-OCR capture the Flutter migration dropped

- Status: accepted
- Date: 2026-10-05

## Context

The retired Android port had a capability the Flutter codebase does not: a bubble-menu
item 「截屏识别一次」 that photographed whatever was in front and OCR'd the whole frame.
It worked on **any** application, adapted or not — `ChatCaptureService.kt:474` said so in
as many words ("Works on ANY app, adapted or not"), and `:278` made it the *only* way in
for an application with no adapter, because `v1.3` had already decided that unadapted
applications are never handled automatically. The same port carried an `ocrFallback`
setting and an OCR-engine choice.

`9629f3b` ("feat(android): promote Flutter implementation", #24) retired that port. The
capability was not carried over, and **nothing recorded the loss**: neither
`docs/plans/0001-flutter-migration.md` nor any of the seventeen ADRs contains the strings
「截屏识别」, `ocrFallback` or `OCR_VISION`. There is no repository evidence of a decision
to drop it — the migration simply did not cover it.

It was found from the outside. A report that "Feishu can read chat records but the OCR
option seems to have been removed in Douyin" is a misdiagnosis of a real absence, and both
halves matter:

- **Douyin was never a capture target**, and `PRIVACY.md:3` has said 「微信与抖音暂不支持」
  since `10fcb6f`. The adapter registry has held exactly
  `QQAdapter(), XAdapter(), FeishuAdapter()` since the initial import `3262ae0`; `git log -S`
  finds no `douyin`, `抖音` or `aweme` in any code file at any revision.
- **The manual path that would have let a user read it anyway is gone.** Feishu works
  because it is in the registry — and it is the only adapter that *requires* OCR, because
  its message text is drawn rather than laid out as views (`ChatAppAdapter.kt:304-309`).
  So the observed asymmetry is about the registry, not about an OCR switch; but the user's
  memory of an "OCR option" was a memory of the manual capture, and it was accurate.

Half of the machinery survived the migration. `recognizeWholeFrame` and `groupOcrLines`
are in the Flutter port (`RetainedCaptureService.kt:237`, `:315`), including the 1.2× line-gap
grouping and the note 「OCR 未分边，把全部消息当作对方所说」. What is missing is the user
entry point, the trigger path for unadapted applications (`:66` gates on `adapters[pkg]`),
and the ball-parking that made the entry point reachable.

Three live statements describe capabilities that do not exist, and one of them is
load-bearing: `miaotou_capabilities_android/lib/src/capabilities.dart:70-72` claims the port
offers "the cloud vision route", attributed to #22 — a ticket that is closed and claims its
acceptance criteria were met. `OcrEngine.kt:18` cites `docs/v1.3-plan.md`, which is not in
this repository. `docs/design/overlay-proposal.md:17` puts an OCR section in the settings
page that `settings_page.dart` does not have.

## Decision

**The manual whole-frame recognition is restored, and it is composed in the app layer out
of contract members that already exist.**

1. **No contract member is added.** ADR-0009's boundary is left exactly as it is. The manual
   path is a composition of `screenCapture.findTargetWindow()`, `screenCapture.capture()`,
   `ocr.recognize()` and `floatingPanel.hideForCapture()`/`restoreAfterCapture()` — all
   members the Android port already implements and the other two ports already answer for.
   Adding `UiTreeReader.captureOnce()` was the obvious shape and is the wrong one: it would
   have required a member on an interface whose own doc comment calls itself "Android only",
   a probe entry, a `42 → 43` count assertion, and two new permanent refusals.
2. **It works on every application, and there is no allowlist.** An unadapted application is
   not an error state; it is the case the manual path exists for. The path is never
   automatic: the adapter registry stays the only thing that triggers a capture without the
   user asking, which is the `v1.3` rule the retired port already carried.
3. **An application with no adapter keeps the suspended ball.** The retired port's rule is
   adopted whole (`ChatCaptureService.kt:223-246`): the ball stays parked over the
   unadapted application — a ball that is gone cannot be tapped — and comes off over our own
   settings screens, the launcher and the system UI.
4. **The application's name comes from the platform, not from a table.** `ChatApps.NAMES`
   stops being the only source: the display name is the one the system reports for the
   package (`PackageManager.getApplicationLabel` on Android), Chinese or English as the
   system has it, with 「未识别会话」 only when the system cannot name it either. A
   hand-maintained package→name table loses to a new application every time, which is the
   failure mode that produced the report this ADR answers.
5. **The cloud vision route stays out.** Its removal predates the migration —
   `OcrEngine.kt:17-18` records that `v1.3` deliberately took the vision model off this path
   — and Android's on-device OCR needs no network: the dependency is the *bundled*
   `com.google.mlkit:text-recognition-chinese`, not the Play-Services variant. The stale
   claim at `capabilities.dart:70-72` is deleted rather than honoured.
6. **Every stale statement is corrected in the same change** — the three above, plus
   `PRIVACY.md:3` and `platform-build.yml:200`, whose 「微信与抖音暂不支持」 becomes a
   statement about **automatic** adapters, because "not an adapter" and "not readable" stop
   being the same thing the moment a manual path exists.

## Rejected alternatives

- **Correct the documentation and add nothing.** The cheapest option, and the one the
  evidence actually supports for Douyin: nothing was removed, and the privacy note is
  accurate about adapters. Rejected because the report was still right about something —
  a capability that exists in no revision after `9629f3b` is not a documentation problem,
  and restoring only the words would leave the user unable to read the application they
  asked about.
- **Add `UiTreeReader.captureOnce()`.** The tidiest reading of "the platform owns pixels".
  Rejected on blast radius that buys nothing: fifteen call sites across four packages, two
  new permanent refusals on ports where a manual capture is meaningless, and — the
  decisive part — the grouping and side-inference logic would land in Kotlin, where the
  calibration the decision below requires could only be pinned by an instrumented test on a
  device instead of a synthetic fixture.
- **Push it to all three ports in the same change.** Composition means desktop gets a
  degenerate version for free (it would re-photograph the chat window it already watches).
  Rejected as scope: the report is an Android one, and desktop behaviour is a decision that
  needs its own evidence.
- **Restore the `ocrFallback` setting and the engine choice.** Rejected: the engine choice
  was already withdrawn on this path before the migration (§5), and a setting that turns the
  manual path off only protects users from a button they pressed themselves.
- **Recognise automatically on unadapted applications.** Would have made Douyin "work"
  without a menu item. Rejected: it contradicts the `v1.3` rule (§2), and it photographs
  screens the user never asked about.

## Consequences

- **The line-gap grouping and the note now exist twice.** `groupOcrLines` stays in Kotlin for
  the automatic path, and the manual path needs its own implementation in Dart because it
  never reaches the service's adapter-gated method. Two implementations of the same 1.2×
  rule will drift. Recorded as the cost of keeping ADR-0009's boundary intact; the fixture
  below is what keeps them comparable.
- **`[OCR待核对]` is dead on Android today, and this decision depends on it.** The runtime
  builds `CapturedLine` without a confidence (`conversation_runtime.dart:183`), while the
  domain reads a null confidence as "not from OCR", and the capability channel hardcodes
  `confidence` to `1.0` because ML Kit's Chinese recogniser does not report one per line.
  Both halves are fixed here — see ADR-0019, which is where that marking is decided.
- **`PanelFrame.appNames` is never populated on the Android port.** `conversation_runtime`
  republishes whatever map the previous frame carried, and nothing fills it, so the panel
  header has never named an application on this port. §4 therefore needs a path that does
  not exist yet: either a field on the conversation identity (a Dart model shared by all
  three ports) or a new contract member for resolving a package to a name. The decision
  stands; the mechanism is open and is the largest single item in the implementation.
- **A wrong side guess now enters the transcript as a confident `我`.** With §1 of ADR-0019
  writing `me`/`other` directly, `prompts.dart:64`'s "OCR side judgement is only a clue" is
  load-bearing text rather than a caveat, and weakening it changes behaviour.
- **The per-line corrector the retired port had is not restored by this ADR.** The old panel
  let the user rewrite each line's speaker and body before a call was made
  (`OverlayController.kt:490`); the Flutter panel has no such surface, so a mis-guess can be
  read but not corrected. Tracked as its own item — it is the one piece without which
  ADR-0019's marking is a warning nobody can act on.
- **Device acceptance is required and cannot be replaced by the fixture.** The fixture pins
  the threshold arithmetic; whether a frame is obtainable at all on a given application
  (FLAG_SECURE, an unusual window type) is only observable on a device, per ADR-0014.
