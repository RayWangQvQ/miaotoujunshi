# Build all three ports from one Flutter codebase

- Status: accepted
- Date: 2026-10-03

## Context

The three ports are three independent implementations of one product. Android is
Kotlin against the platform View system, the accessibility service and ML Kit;
Windows is Python on PySide6 with `ctypes` into Win32, Windows Graphics Capture
through a Rust extension and RapidOCR; macOS is Python on PyObjC with Quartz,
Apple Vision and the Accessibility API. Together they are 16,096 lines, and they
agree on almost nothing structural.

The expensive part is not the line count, it is that the contract has one
definition and three implementations. `miaotoujunshi/references/data/trend-rules.json`
declares `"senders": ["me", "other"]`; Android uses that pair throughout, Windows
uses `me`/`her` on its main path and `other` on its CSV path, and macOS uses
`me`/`them` on its OCR path and `other` on its CSV path. Every port converts at
its own boundary, so a new shared file that assumes one spelling is read wrongly
by a port and nothing goes red. Nothing in the repository asserts that two ports
agree about anything.

`2026-10-03-flutter-migration-feasibility.md` assessed the migration and
recommended against it, on the grounds that the platform-capability layer — 3,788
lines of screen capture, OCR, synthetic input and native windows — cannot be
shared, that the calibrated perception heuristics are the repository's only
measured asset and rewriting them invalidates them, and that several of the
distribution benefits are reachable without changing framework. The owner
nonetheless decided to migrate, with **deduplication of the business and UI
layers as the primary driver** — the one reason the feasibility report accepted as
sufficient.

Two facts constrain the timing and are recorded here because they are not visible
in the code. First, **this product has never been released**. There are no
installed users, so no in-place upgrade path, no data migration from the three
legacy stores, and no historical compatibility obligation is in scope. Second, the
three ports' developer-side device acceptance is complete but leaves no
machine-replayable evidence; the calibration values exist only as constants and
comments.

## Decision

**The three ports are replaced by one Flutter application, built for Android,
Windows and macOS from a single codebase.**

1. **Location.** The project lives at `integrations/jev_flutter/`, which the
   root allowlist already registers as the `app` layer, so
   `scripts/validate_layout.py` needs no new entry and no new layer name.
   **Superseded by [ADR-0017](0017-retire-the-integrations-wrapper.md):** the project
   now lives at `app/`. The reasoning here still holds — the allowlist needed no new
   entry and no new layer name — and the directory is now spelled that way.
2. **Structure.** A Dart 3.13+ / Flutter 3.47+ **pub workspace** (a root
   `pubspec.yaml` with `workspace:` and per-package `resolution: workspace`), with
   `apps/miaotou_app/` as the only Flutter application and `packages/` holding a
   platform-free `miaotou_domain` plus one capability interface package and three
   platform implementation packages. Melos is not used.
3. **Scope: all three ports.** Android keeps its system components in Kotlin; the
   UI, the business logic and the panel content move to Flutter. There is no port
   left on its old stack.
4. **Feature baseline is the union of the three ports.** The Android knowledge
   base, the macOS memory bridge, the Windows anti-injection filter and the
   Windows update check all become cross-platform capabilities. No port loses a
   feature it had, and no feature stays behind a per-platform switch.
5. **The Android system layer stays Kotlin.** An `AccessibilityService` is a
   system-bound Service that Flutter neither can nor needs to host; the screenshot
   APIs (`takeScreenshot`, `takeScreenshotOfWindow`), the per-app node-path adapter
   and the `ACTION_SET_TEXT`/`ACTION_PASTE` injection with read-back remain
   Kotlin, about 1,700 lines of measured assets. The floating panel is split:
   window semantics stay in a **new hand-written Kotlin plugin** — not
   `flutter_overlay_window`, which has had no commit in fifteen months and 49 open
   issues — and Flutter renders the panel's content.
6. **The old ports are frozen, not deleted, and not developed.** During migration
   `integrations/jev_android`, `integrations/jev_windows` and
   `integrations/jev_mac` keep building and keep being the behavioural reference,
   but take blocking fixes only. Each is archived as a git tag and deleted when
   its replacement is accepted.
7. **The macOS port is the pilot**, because its capability surface is the
   smallest and its packaging gain is the largest. This survives the fact that
   `CGWindowListCreateImage` was obsoleted in macOS 15 — macOS must move to
   ScreenCaptureKit regardless of Flutter, so the pilot inherits a rewrite it
   would have needed anyway.
8. **No legacy-data work.** Nothing is written to migrate preferences,
   credentials, knowledge or memory out of the three old stores, and no
   compatibility shim is added for their formats.

## Rejected alternatives

- **Stay on three stacks and deduplicate along the feasibility report's route B
  then A** (unify the speaker token, then merge the two Python `core/` trees into
  one shared implementation). Strictly cheaper and it captures the largest
  duplication — but it cannot reach Android, whose logic is Kotlin, so the
  contract keeps two implementations and the UI keeps three. Rejected because the
  owner's stated driver is deduplication, which this route only delivers for two
  thirds of the problem.
- **Migrate the two desktop ports only, leave Android on Kotlin.** Avoids the
  highest-risk item (a semi-transparent Flutter surface over another app) and the
  second Flutter engine. Rejected because it forfeits UI unification, which is
  the point.
- **Migrate macOS alone as a proof of concept and decide later.** Smallest
  commitment. Rejected as the *final* scope because a one-port Flutter app is
  strictly more work than the Python it replaces; it survives only as milestone
  order, which decision 7 adopts.
- **Share the domain layer only, keep each port's native UI** (Dart domain over
  FFI, or a local sidecar service). The feasibility report's route D. Rejected:
  Android cannot run a Dart/Python sidecar, and a remote service contradicts
  `PRIVACY.md`'s promise that chat content is neither persisted nor additionally
  uploaded.
- **Rewrite the three ports in one step.** No dual-track period, no freeze.
  Rejected: with no released users there is nothing to protect, but there is also
  no fallback if the first port fails, and the frozen ports are the only
  behavioural reference for the calibration work.
- **Keep `flutter_overlay_window` and patch it.** Fewer lines to write in Kotlin.
  Rejected because the package is unmaintained and its open defects include a
  hang in `closeOverlay()` and a crash in `OverlayService.onStartCommand`;
  adopting it means owning a fork of a dead dependency for the product's central
  UI.

## Consequences

- **The perception heuristics are invalidated and will be recalibrated per
  port.** `chat_area()`'s pixel anchors, `ChatAppAdapter`'s per-app node paths and
  `fill.py`'s `MIN_INPUT_AREA = 10000.0` are measured values, not portable
  constants. Recalibration is in scope, and it is the migration's largest cost.
- **The regression net lapses.** The 108 Python tests in `tests/` and the five
  Android JVM test classes are the only current evidence that nothing is broken.
  Most of the Python ones go away with the Python ports.
- **Two packaging obligations change for the better.** The Windows package stops
  bundling `PySide6-Fluent-Widgets`, so the release artifact's repository-wide
  GPLv3 constraint disappears; macOS stops shipping a source archive and gains a
  signed, notarised `.app`.
- **Dual-track cost is real.** Four build pipelines run during migration, and the
  frozen ports still need security and blocking fixes.
- **Per-platform Kotlin/Swift/C++ code does not disappear.** Android retains its
  accessibility layer; Windows needs hand-written native bridges for continuous
  window capture and synthetic input; macOS needs a ScreenCaptureKit plugin. The
  capability contract makes each port declare these explicitly — a compiler-
  enforced statement of support that the current three-stack layout has no
  equivalent for.
- **Three upstream attribution obligations move rather than lapse.** Translating
  derived logic into Dart is still a derivative work; the new `NOTICE` must cover
  all three upstreams plus the Flutter dependency tree.
- **`integrations/` grows by one directory before it shrinks by three.** The old
  and new trees coexist until the last port is replaced. **Spent, and the wrapper then
  retired by [ADR-0017](0017-retire-the-integrations-wrapper.md):** all three deletions
  landed, and `integrations/` itself is gone.
