import 'dart:async';

import 'package:miaotou_capabilities/miaotou_capabilities.dart';

/// The measured Windows capture schedule.
///
/// The old port delivered at most one settled frame per second, doubled the
/// retry delay after failures up to thirty seconds, and refused to wait forever
/// for a native callback. Keeping those three decisions above the process
/// boundary makes them testable even though WGC itself is Windows-only.
final class WindowsCapturePacing {
  WindowsCapturePacing({
    DateTime Function()? clock,
    this.minInterval = const Duration(seconds: 1),
    this.maxBackoff = const Duration(seconds: 30),
    this.watchdog = const Duration(seconds: 3),
  }) : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;
  final Duration minInterval;
  final Duration maxBackoff;
  final Duration watchdog;

  static const int throttledCode = -1;
  static const int timeoutCode = -2;
  static const int _maxShift = 6;

  DateTime? _lastAttempt;
  int _failStreak = 0;

  int get failStreak => _failStreak;

  Duration get requiredInterval {
    if (_failStreak <= 0) {
      return minInterval;
    }
    final int shift = _failStreak - 1;
    final int milliseconds =
        minInterval.inMilliseconds *
        (1 << (shift < _maxShift ? shift : _maxShift));
    return Duration(
      milliseconds: milliseconds > maxBackoff.inMilliseconds
          ? maxBackoff.inMilliseconds
          : milliseconds,
    );
  }

  Future<CaptureOutcome> run(Future<CaptureOutcome> Function() capture) async {
    final DateTime now = _clock();
    final DateTime? last = _lastAttempt;
    if (last != null && now.difference(last) < requiredInterval) {
      return const CaptureFailed(code: throttledCode, message: '截屏太频繁');
    }
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
