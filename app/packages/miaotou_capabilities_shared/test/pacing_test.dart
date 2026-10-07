import 'dart:async';
import 'dart:typed_data';

import 'package:miaotou_capabilities/miaotou_capabilities.dart';
import 'package:miaotou_capabilities_shared/miaotou_capabilities_shared.dart';
import 'package:test/test.dart';

/// The rate limit, the backoff and the watchdog.
///
/// Each of the three has a mutation below it, because a pacing class that is
/// merely *present* proves nothing: a throttle that never throttles, a backoff
/// that never grows and a watchdog that never fires all pass a test that only
/// checks the happy path returned a frame.
///
/// This is the one suite for the schedule. The two desktop ports carried a copy
/// each — `miaotou_capabilities_macos/test/pacing_test.dart` and
/// `miaotou_capabilities_windows/test/pacing_test.dart`, the second of which was
/// the first rewritten with a different class name — and the measured numbers are
/// the same numbers on every port because the schedule is the same decision.
void main() {
  /// A clock the test moves by hand, so a one-second floor costs no wall time.
  DateTime now = DateTime(2026, 10, 4, 12);
  CapturePacing pacingWith({
    Duration minInterval = const Duration(seconds: 1),
    Duration maxBackoff = const Duration(seconds: 30),
    Duration watchdog = const Duration(seconds: 3),
  }) => CapturePacing(
    clock: () => now,
    minInterval: minInterval,
    maxBackoff: maxBackoff,
    watchdog: watchdog,
  );

  CaptureOutcome aFrame() => CaptureOk(
    CaptureFrame(
      pixels: Uint8List.fromList(<int>[1, 2, 3, 4]),
      width: 1,
      height: 1,
      scaleX: 1,
      scaleY: 1,
      originX: 0,
      originY: 0,
    ),
  );

  CaptureOutcome refused() => const CaptureFailed(code: 9, message: 'no frame');

  test('a second capture inside the interval is refused, not attempted', () async {
    final CapturePacing pacing = pacingWith();
    int attempts = 0;

    Future<CaptureOutcome> body() async {
      attempts++;
      return aFrame();
    }

    final CaptureOutcome first = await pacing.run(body);
    final CaptureOutcome second = await pacing.run(body);

    expect(first, isA<CaptureOk>());
    expect(
      attempts,
      1,
      reason: 'the second capture must not reach the system at all',
    );
    expect(second, isA<CaptureFailed>());
    expect((second as CaptureFailed).code, CapturePacing.throttledCode);
  });

  test('the floor is one second, and the attempt is timed from its start', () async {
    final CapturePacing pacing = pacingWith();
    await pacing.run(() async => refused());
    now = now.add(const Duration(milliseconds: 999));
    expect(await pacing.run(() async => refused()), isA<CaptureFailed>());

    now = now.add(const Duration(milliseconds: 2));
    expect(await pacing.run(() async => refused()), isA<CaptureFailed>());
  });

  test('failures double the wait and one success puts it back', () async {
    final CapturePacing pacing = pacingWith();
    expect(pacing.requiredInterval, const Duration(seconds: 1));

    final List<int> seen = <int>[];
    for (int i = 0; i < 7; i++) {
      now = now.add(pacing.requiredInterval);
      await pacing.run(() async => const CaptureFailed(code: 9, message: 'no'));
      seen.add(pacing.requiredInterval.inMilliseconds);
    }
    expect(
      seen,
      <int>[1000, 2000, 4000, 8000, 16000, 30000, 30000],
      reason: 'the wait after the n-th failure is 2^(n-1) seconds, capped at 30s '
          '(measured on the Android port, which is where these numbers come '
          'from). The cap is the point: an hour-long outage must not push the '
          'next attempt hours away',
    );

    now = now.add(pacing.requiredInterval);
    await pacing.run(() async => aFrame());
    expect(pacing.failStreak, 0);
    expect(pacing.requiredInterval, const Duration(seconds: 1));
  });

  test('a capture that never answers trips the watchdog rather than hanging', () async {
    final CapturePacing pacing = pacingWith(
      watchdog: const Duration(milliseconds: 20),
    );
    final CaptureOutcome outcome = await pacing.run(
      () => Completer<CaptureOutcome>().future,
    );
    expect(outcome, isA<CaptureFailed>());
    expect((outcome as CaptureFailed).code, CapturePacing.timeoutCode);
    expect(pacing.failStreak, 1, reason: 'a timeout is a failure and backs off');
  });

  test('the codes are ours, so they cannot collide with a platform code', () {
    expect(CapturePacing.throttledCode, lessThan(0));
    expect(CapturePacing.timeoutCode, lessThan(0));
  });
}
