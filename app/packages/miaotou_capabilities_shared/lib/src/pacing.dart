import 'dart:async';

import 'package:miaotou_capabilities/miaotou_capabilities.dart';

/// How often a port is allowed to ask the system for a frame, and what it does
/// with the answers.
///
/// **Timing is the implementation's business, not the caller's** (ADR-0009), and
/// the numbers are not invented here. They are the ones the Android port measured
/// and then wrote down (`capture/ocr/ScreenCapture.kt`): a one-second floor
/// between attempts, a doubling backoff while failures repeat capped at thirty
/// seconds, and a three-second watchdog for a platform callback that never
/// arrives. A capture that runs every second is the difference between a tool and
/// a battery complaint, and a callback that never returns is the difference
/// between a panel and a hang.
///
/// Keeping those three decisions on this side of the platform boundary is what
/// makes them testable at all: the desktop ports feed pixels from Quartz and from
/// Windows Graphics Capture, neither of which a test can drive, but the schedule
/// around them is ordinary Dart.
///
/// The two codes this class produces are **ours, not the platform's** — the
/// contract passes platform codes through untranslated, and no port has a code
/// for "you are asking too fast". They are negative so they can never collide
/// with a platform error value, which is the choice the Android port made first
/// and for the same reason.
///
/// The clock is injected so the schedule can be tested without waiting for it.
final class CapturePacing {
  CapturePacing({
    DateTime Function()? clock,
    this.minInterval = const Duration(seconds: 1),
    this.maxBackoff = const Duration(seconds: 30),
    this.watchdog = const Duration(seconds: 3),
  }) : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;

  /// The floor between two attempts, and the first step of the backoff.
  final Duration minInterval;

  /// Where the doubling stops.
  final Duration maxBackoff;

  /// How long one attempt may take before it is abandoned.
  final Duration watchdog;

  /// Our own code for "the rate limit is still running".
  static const int throttledCode = -1;

  /// Our own code for "the platform callback never arrived".
  static const int timeoutCode = -2;

  /// Beyond this many consecutive failures the doubling stops growing. Six steps
  /// from one second is already past the cap; the guard only stops the shift from
  /// overflowing on a long outage.
  static const int _maxShift = 6;

  DateTime? _lastAttempt;
  int _failStreak = 0;

  /// Consecutive failed attempts. Read by tests and by a support report.
  int get failStreak => _failStreak;

  /// How long the caller must wait before the next attempt is allowed to run.
  ///
  /// One second normally; one, two, four, eight … while failures repeat, capped
  /// at [maxBackoff]. A single success resets it, because a port that recovered
  /// once has no reason to keep waiting.
  Duration get requiredInterval {
    if (_failStreak <= 0) {
      return minInterval;
    }
    final int shift = _failStreak - 1;
    final int scaled =
        minInterval.inMilliseconds * (1 << (shift < _maxShift ? shift : _maxShift));
    return Duration(
      milliseconds:
          scaled > maxBackoff.inMilliseconds ? maxBackoff.inMilliseconds : scaled,
    );
  }

  /// Runs one capture under the rate limit, the backoff and the watchdog.
  ///
  /// A refused capture is a value, not an exception (the contract says so), and so
  /// is a throttled or timed-out one: the caller has a decision to make about each
  /// and none of them is "crash".
  Future<CaptureOutcome> run(Future<CaptureOutcome> Function() capture) async {
    final DateTime now = _clock();
    final DateTime? last = _lastAttempt;
    if (last != null && now.difference(last) < requiredInterval) {
      return const CaptureFailed(code: throttledCode, message: '截屏太频繁');
    }

    // Recorded before the attempt rather than after it, so a capture that takes
    // longer than the interval still leaves the next one waiting: pacing a loop by
    // its start time is the only way the floor holds when the work is slow.
    _lastAttempt = now;

    final CaptureOutcome outcome;
    try {
      outcome = await capture().timeout(watchdog);
    } on TimeoutException {
      _failStreak++;
      return const CaptureFailed(code: timeoutCode, message: '截屏超时');
    }

    if (outcome is CaptureOk) {
      _failStreak = 0;
    } else {
      _failStreak++;
    }
    return outcome;
  }
}
