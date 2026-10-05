# Declare a port replaced only after device acceptance passes

- Status: accepted
- Date: 2026-10-03

## Context

ADR-0007 freezes the three ports and replaces them one at a time, with macOS as
the pilot. Two forces pull in opposite directions. The frozen ports cost four
build pipelines and four dependency sets for the duration, so the repository wants
them gone early. But they are also the only behavioural reference for the
calibration fixtures (ADR-0011) and the only working implementation of the
product, so deleting one too early removes the thing the migration is measured
against.

Each port also has one unknown that decides whether that port can be migrated at
all, and none of the unknowns can be resolved by reading code:

- **macOS**: whether a `MainFlutterWindow` converted to an `NSPanel` with
  `.nonactivatingPanel` can both avoid stealing the chat application's focus and
  accept Chinese IME input in the review editor.
- **Android**: whether a hand-written overlay plugin can render a semi-transparent
  Flutter surface over another application, given that Flutter's unpainted pixels
  are black by default and a transparent surface sits above other views.
- **Windows**: how much work the native bridge actually is.

Device acceptance in this repository is manual and leaves no replayable artifact —
ADR-0011's fixtures exist precisely because it does not.

## Decision

**A port's replacement is accepted, and its old directory deleted, only when three
things hold; the gate experiments are run one at a time, each just before its
port.**

1. **Acceptance criteria**, all three required:
   - the new app completes the flow the old port's `README.md` describes, on a real
     device;
   - the synthetic fixtures are green;
   - every capability the union baseline assigns to that port works — including
     features that port never had, which arrive with the union (ADR-0007
     decision 4).
2. **Deletion cadence.** On acceptance, tag the old directory, delete it, and
   remove its CI job, its `paths` filter entry and its README section in the same
   change. The migration does not accumulate old trees to clean up at the end.
3. **Gate experiments run one at a time**, each before the port it gates:
   experiment B (macOS `NSPanel` with non-activating behaviour and working Chinese
   IME) before the pilot; experiment A (Android semi-transparent overlay) before
   the Android port; experiment C (a minimal Windows Graphics Capture bridge
   producing frames from an occluded window) before the Windows port.
4. **The cross-check harness runs before each deletion**, while both
   implementations still exist, and is removed with the last Python port.

## Rejected alternatives

- **Delete all three old trees at the end.** The cross-check reference stays
  available for the whole migration and rollback is trivial. Rejected because it
  carries four pipelines and four dependency trees through the entire period, and
  the cleanup becomes a second migration of its own.
- **Stop a port's CI when it is replaced but keep the directory until the end.**
  Removes the pipeline cost while preserving the reference. Rejected because it
  leaves code in the repository with no pipeline to keep it honest — a state that
  looks maintained and is not.
- **Accept a port on fixtures plus a smoke pass of the main flow.** Much faster,
  and the fixtures are the only mechanical evidence anyway. Rejected because the
  one thing fixtures cannot cover is whether the recalibrated anchors work against
  the real client, which is the risk the migration actually carries.
- **Accept by co-capturing the same window with the old and the new app** and
  diffing judgements and injections frame by frame. The strongest evidence
  available. Rejected as the *acceptance* standard because it needs both apps
  resident on one machine, and it does not extend to Android, but it is the
  strongest available form of the migration cross-check and belongs there.
- **Run all three gate experiments before starting.** Removes the possibility of
  discovering a blocking constraint halfway through. Rejected: it front-loads
  Android's and Windows' risk into a period where nothing else is being learned,
  and experiment C is a native bridge — well beyond the "one day" the earlier
  design assumed.
- **Defer the gate experiments entirely** and discover the constraints while
  building. Rejected because each one decides whether its port is migrated at all,
  which is too large a question to answer by accident.

## Consequences

- **Three deletions spread across the migration**, each touching CI filters and the
  README in the same change — more, smaller cleanup steps instead of one large one.
- **Each deletion narrows the cross-check**, so the harness must run before it, not
  after. A port deleted without the cross-check having run loses the only
  comparison it had.
- **The acceptance flow stays manual and unreplayable.** This ADR does not fix that;
  ADR-0011's fixtures reduce what has to be verified by hand, they do not remove
  the step.
- **Experiment A's premise changed and its outcome still decides Android.** The
  earlier design built it on `flutter_overlay_window`; ADR-0007 replaced that with
  a hand-written plugin, so the experiment now tests the plugin's transparency and
  layering rather than a third-party package's.
- **macOS's experiment B is the only one on the critical path now**, so the pilot
  can start without the Android or Windows questions being answered.
- **The three tags are `archive/jev-<port>-<language>-final`**, not the
  `legacy/<port>-final` the migration plan suggested. The plan's §13 records the
  naming and why; what matters for this ADR is that all three were pushed to the
  remote in the same change that deleted the directory, so the archived tree is
  reachable from a clone and not only from the machine that did the deletion.
