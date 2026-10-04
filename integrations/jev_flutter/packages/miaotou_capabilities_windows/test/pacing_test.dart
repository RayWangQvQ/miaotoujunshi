import 'dart:async';
import 'dart:typed_data';

import 'package:miaotou_capabilities/miaotou_capabilities.dart';
import 'package:miaotou_capabilities_windows/miaotou_capabilities_windows.dart';
import 'package:test/test.dart';

void main() {
  DateTime now = DateTime(2026, 10, 5, 12);

  CaptureOutcome frame() => CaptureOk(
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

  test(
    'rate limit, exponential backoff and reset retain the measured schedule',
    () async {
      final WindowsCapturePacing pacing = WindowsCapturePacing(
        clock: () => now,
      );
      int attempts = 0;

      Future<CaptureOutcome> fail() async {
        attempts++;
        return const CaptureFailed(code: 9, message: 'no frame');
      }

      await pacing.run(fail);
      expect(await pacing.run(fail), isA<CaptureFailed>());
      expect(attempts, 1, reason: 'a throttled call must not reach WGC');

      final List<int> intervals = <int>[pacing.requiredInterval.inSeconds];
      for (int i = 0; i < 6; i++) {
        now = now.add(pacing.requiredInterval);
        await pacing.run(fail);
        intervals.add(pacing.requiredInterval.inSeconds);
      }
      expect(intervals, <int>[1, 2, 4, 8, 16, 30, 30]);

      now = now.add(pacing.requiredInterval);
      await pacing.run(() async => frame());
      expect(pacing.failStreak, 0);
      expect(pacing.requiredInterval, const Duration(seconds: 1));
    },
  );

  test(
    'a bridge callback that never returns is stopped by the watchdog',
    () async {
      final WindowsCapturePacing pacing = WindowsCapturePacing(
        clock: () => now,
        watchdog: const Duration(milliseconds: 20),
      );

      final CaptureOutcome result = await pacing.run(
        () => Completer<CaptureOutcome>().future,
      );

      expect(result, isA<CaptureFailed>());
      expect((result as CaptureFailed).code, WindowsCapturePacing.timeoutCode);
      expect(pacing.failStreak, 1);
    },
  );
}
