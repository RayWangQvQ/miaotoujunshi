# Pin the perception calibration with synthetic fixtures

- Status: accepted
- Date: 2026-10-03

## Context

Two things are true of this repository's test story at the moment. It is the only
evidence that nothing is broken — 108 Python cases in `tests/`, weighted heavily
toward macOS, plus five Android JVM test classes covering the capture service, the
route keys, the trend data, the conversation reference and the shared-material
reader. And it does not cover the asset that matters most: `chat_area()`'s pixel
anchors, `ChatAppAdapter`'s per-app node paths and `fill.py`'s
`MIN_INPUT_AREA = 10000.0` were measured on real devices by trial and error, and
those measurements exist only as constants and the comments beside them. The
device acceptance that validated them left no replayable artifact.

ADR-0007 replaces the three ports and invalidates most of the Python suite with
them. ADR-0009 puts the platform layer behind interfaces, which makes the domain
testable without a device. But the interfaces do not help with the calibration
constants — those are values about real client applications, not about the
platform.

ADR-0005 deliberately rejected a cross-port conformance test and chose
documentation as the only guard. That decision is not reopened here.

## Decision

**The domain is tested with `dart test`; the perception calibration is pinned by
committed synthetic fixtures; the cross-check against the Python implementations
is a one-off migration tool.**

1. **Pure logic moves to `miaotou_domain` and runs under `dart test`.** No Flutter
   toolkit, no platform package, no device — milliseconds in CI, which makes this
   the cheapest and therefore the most-used part of the suite.
2. **The perception calibration is pinned by synthetic fixtures.** A fixture is a
   fabricated input — a rendered chat-interface bitmap, or a node tree — plus the
   expected output of the calibration step it exercises. The material is invented:
   fabricated contact names, fabricated message text, no real screenshot and no
   real chat content.
3. **Fixtures are committed and run in CI.** They are ordinary repository assets,
   not a local-only harness.
4. **Android's five JVM test classes stay unchanged** while their subjects remain
   in Kotlin (ADR-0007 decision 5). They cover code the migration does not touch.
5. **The cross-check against the Python implementations is one-off.** During
   migration, the same fixtures are fed to both the Dart and the Python
   implementations and the conclusions are compared. The harness is deleted
   together with the Python ports. It is a migration instrument, not a guard.
6. **No cross-port conformance assertion is added.** ADR-0005's decision stands.

The distinction that keeps decision 6 from contradicting decisions 2 and 3: a
**fixture** pins one implementation's behaviour across time, which is what a
migration needs; a **conformance test** would assert that three implementations
agree at one moment, which is what ADR-0005 rejected as the wrong price for the
problem it addressed.

## Rejected alternatives

- **Real device screenshots as fixtures.** Highest fidelity, and the only way to
  reproduce how a specific client version actually renders. Rejected on privacy
  first: a chat screenshot *is* chat content, and `PRIVACY.md` promises that
  neither is persisted or additionally uploaded — committing them would contradict
  it in the repository itself, not merely on a device. They are also not
  CI-runnable without a device, and a fixture no one can run is not a guard.
- **Fixtures limited to the perception layer, no domain suite.** Smallest new
  surface, and it targets the asset that is actually at risk. Rejected because the
  domain is where the migration's deduplication lands, and shipping it without a
  regression net trades one risk for a larger one.
- **Fixtures that only record intermediate values** (anchor coordinates, node
  paths, area thresholds) with no imagery. Cleanest on privacy and trivially
  CI-runnable, but it cannot cover the image-processing steps that produce those
  values, which is exactly where a language port drifts.
- **Add the cross-port conformance assertion on top.** Would catch a port drifting
  from the shared contract in CI rather than on a device. Rejected: the owner chose
  a documentation-only guard deliberately (ADR-0005), and after ADR-0007 the
  three-implementation problem it guards largely disappears — one domain, three
  platform packages that the compiler already holds to the same interface.
- **Keep the Python suite as the long-term guard** by running it against the frozen
  ports. Rejected: it tests code that is scheduled for deletion, and it would
  outlive its subject only as a source of false confidence.
- **Rely on device acceptance alone.** Honest about what actually verifies the
  calibration, and it is what happens today. Rejected because it is the status quo
  that left no replayable evidence, and because a migration is precisely when the
  same check needs to be run against two implementations.

## Consequences

- **Fixtures are committed, so they must never contain real chat content or real
  contact labels.** This is a review rule with no mechanical guard, and it is the
  one place where the privacy constraint depends on discipline rather than design.
- **Fixture coverage is bounded by how faithfully a fabricated interface imitates
  the real clients.** It will not catch a rendering quirk introduced by a WeChat
  update; device acceptance is still required for that, and stays a manual step.
- **The recalibration work is where these fixtures get created**, not after it —
  the first version of each fixture comes out of observing the real client.
- **The one-off cross-check needs the frozen ports to stay runnable**, which is the
  practical reason ADR-0007 keeps them building rather than deleting them
  immediately.
- **`dart test` is the cheapest job in CI**, so a large part of the suite can run
  on every change without a device or an emulator — a property neither existing
  test story has.
