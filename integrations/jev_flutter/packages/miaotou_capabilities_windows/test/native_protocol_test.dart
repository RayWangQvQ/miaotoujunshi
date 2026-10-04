import 'dart:typed_data';

import 'package:miaotou_capabilities/miaotou_capabilities.dart';
import 'package:miaotou_capabilities_windows/miaotou_capabilities_windows.dart';
import 'package:test/test.dart';

void main() {
  test(
    'capture IPC carries metadata while pixels come from shared memory',
    () async {
      final _Rpc rpc = _Rpc(<String, Map<String, Object?>>{
        'capture.latest': <String, Object?>{
          'generation': 4,
          'mapping': r'Local\MiaotouFrame-4',
          'byteLength': 8,
          'width': 2,
          'height': 1,
          'scaleX': 1.25,
          'scaleY': 1.25,
          'originX': 40.0,
          'originY': 50.0,
        },
      });
      final _Memory memory = _Memory(
        Uint8List.fromList(<int>[1, 2, 3, 4, 5, 6, 7, 8]),
      );
      final _PanelExclusion panelExclusion = _PanelExclusion();
      final ProcessWindowsNative native = ProcessWindowsNative(
        panelExclusion: panelExclusion,
        rpc: rpc,
        sharedMemory: memory,
      );

      final CaptureOutcome outcome = await native.capture(
        targetWindowId: '4242',
      );

      final CaptureFrame frame = (outcome as CaptureOk).frame;
      expect(frame.pixels, <int>[1, 2, 3, 4, 5, 6, 7, 8]);
      expect(frame.region.left, 40);
      expect(memory.reads, <String>[r'Local\MiaotouFrame-4:8']);
      expect(panelExclusion.calls, 1);
      expect(rpc.calls.single.$1, 'capture.latest');
      expect(rpc.calls.single.$2, <String, Object?>{'windowId': '4242'});
      expect(
        rpc.calls.single.$2.containsKey('pixels'),
        isFalse,
        reason: 'a raw frame must never be copied through JSON IPC',
      );
    },
  );

  test(
    'OCR refers to the shared generation rather than resending frame bytes',
    () async {
      final _Rpc rpc = _Rpc(<String, Map<String, Object?>>{
        'capture.latest': <String, Object?>{
          'generation': 9,
          'mapping': 'frame',
          'byteLength': 4,
          'width': 1,
          'height': 1,
          'scaleX': 1.0,
          'scaleY': 1.0,
          'originX': 0.0,
          'originY': 0.0,
        },
        'ocr.recognize': <String, Object?>{
          'lines': <Object?>[
            <String, Object?>{
              'text': '中文',
              'confidence': 0.9,
              'left': 1.0,
              'top': 2.0,
              'right': 20.0,
              'bottom': 12.0,
            },
          ],
        },
      });
      final ProcessWindowsNative native = ProcessWindowsNative(
        rpc: rpc,
        sharedMemory: _Memory(Uint8List.fromList(<int>[1, 2, 3, 4])),
      );
      final CaptureFrame frame =
          ((await native.capture(targetWindowId: '77')) as CaptureOk).frame;

      final List<OcrLine> lines = await native.recognize(
        frame,
        languages: const <String>['zh-Hans'],
      );

      expect(lines.single.text, '中文');
      expect(rpc.calls.last.$2['generation'], 9);
      expect(rpc.calls.last.$2.containsKey('pixels'), isFalse);
    },
  );
}

final class _Rpc implements WindowsBridgeRpc {
  _Rpc(this.answers);

  final Map<String, Map<String, Object?>> answers;
  final List<(String, Map<String, Object?>)> calls =
      <(String, Map<String, Object?>)>[];

  @override
  Future<Map<String, Object?>> call(
    String method, [
    Map<String, Object?> arguments = const <String, Object?>{},
  ]) async {
    calls.add((method, arguments));
    return answers[method]!;
  }

  @override
  Future<void> close() async {}
}

final class _Memory implements SharedFrameReader {
  _Memory(this.bytes);

  final Uint8List bytes;
  final List<String> reads = <String>[];

  @override
  Uint8List read(String mappingName, int byteLength) {
    reads.add('$mappingName:$byteLength');
    return Uint8List.fromList(bytes);
  }
}

final class _PanelExclusion implements PanelExclusion {
  int calls = 0;

  @override
  void excludeCurrentProcessWindows() {
    calls++;
  }
}
