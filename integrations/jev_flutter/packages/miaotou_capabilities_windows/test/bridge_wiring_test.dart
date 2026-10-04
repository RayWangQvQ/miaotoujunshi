import 'dart:typed_data';

import 'package:miaotou_capabilities/miaotou_capabilities.dart';
import 'package:miaotou_capabilities_windows/miaotou_capabilities_windows.dart';
import 'package:miaotou_capabilities_windows/testing.dart';
import 'package:test/test.dart';

void main() {
  late FakeWindowsNative native;

  setUp(() {
    native = FakeWindowsNative();
  });

  test(
    'one chosen handle is held across continuously delivered frames',
    () async {
      final WindowsScreenCapture capture = WindowsScreenCapture(
        native,
        pacing: WindowsCapturePacing(
          clock: _SteppingClock().call,
          minInterval: Duration.zero,
        ),
      );

      final String? target = await capture.findTargetWindow();
      await capture.capture(targetWindowId: target);
      await capture.capture(targetWindowId: target);

      expect(native.log, <String>[
        'findTargetWindow',
        'capture:77',
        'capture:77',
      ]);
    },
  );

  test(
    'bridge failure is a reportable capture result, not an app crash',
    () async {
      native.captureError = const WindowsBridgeUnavailable('worker exited');
      final WindowsScreenCapture capture = WindowsScreenCapture(
        native,
        pacing: WindowsCapturePacing(minInterval: Duration.zero),
      );

      final CaptureOutcome outcome = await capture.capture(
        targetWindowId: '77',
      );

      expect(outcome, isA<CaptureFailed>());
      expect(
        (outcome as CaptureFailed).code,
        WindowsScreenCapture.bridgeUnavailableCode,
      );
      expect(outcome.message, contains('worker exited'));
    },
  );

  test(
    'OCR stays offline in the bridge and keeps its requested languages',
    () async {
      native.lines = const <OcrLine>[
        OcrLine(
          text: '你好',
          bounds: ScreenRect(left: 1, top: 2, right: 30, bottom: 20),
          confidence: 0.91,
        ),
      ];
      final WindowsOcr ocr = WindowsOcr(native);

      final List<OcrLine> lines = await ocr.recognize(
        _frame(),
        languages: const <String>['zh-Hans', 'en'],
      );

      expect(lines.single.text, '你好');
      expect(native.log, <String>['recognize:zh-Hans+en']);
    },
  );

  test(
    'injection targets a named window and only read-back is success',
    () async {
      native.injectResult = const InjectResult.unverified('read-back differed');
      final WindowsTextInject inject = WindowsTextInject(native);

      final InjectResult result = await inject.inject(
        '好的',
        target: const InjectTarget(windowId: '77'),
      );

      expect(result.verifiedLanding, isFalse);
      expect(native.injectedText, '好的');
      expect(native.log, <String>['inject:77']);
    },
  );
}

CaptureFrame _frame() => CaptureFrame(
  pixels: Uint8List.fromList(<int>[1, 2, 3, 4]),
  width: 1,
  height: 1,
  scaleX: 1,
  scaleY: 1,
  originX: 0,
  originY: 0,
);

final class _SteppingClock {
  DateTime _now = DateTime(2026, 10, 5, 12);

  DateTime call() {
    final DateTime result = _now;
    _now = _now.add(const Duration(seconds: 1));
    return result;
  }
}
