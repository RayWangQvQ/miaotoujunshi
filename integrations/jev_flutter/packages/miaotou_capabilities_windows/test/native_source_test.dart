import 'dart:io';

import 'package:test/test.dart';

void main() {
  final Directory bridge = Directory('native_bridge');

  test(
    'the bridge is an executable with no network-enabled OCR dependency',
    () {
      final String cargo = File('${bridge.path}/Cargo.toml').readAsStringSync();
      expect(cargo, contains('name = "miaotou_bridge"'));
      expect(
        cargo,
        contains(
          'rapidocr-core = { version = "0.2.2", default-features = false }',
        ),
        reason:
            'models are packaged locally; the bridge must have no downloader',
      );
      expect(cargo, isNot(contains('reqwest')));
      final String ocr = File('${bridge.path}/src/ocr.rs').readAsStringSync();
      expect(ocr, contains('config.max_side_len = 4000'));
      expect(ocr, contains('config.inference.intra_threads = 4'));
      expect(ocr, contains('validate_languages(languages)?'));
    },
  );

  test('capture uses WGC, a held target and named shared memory', () {
    final String capture = File('${bridge.path}/src/capture.rs')
        .readAsStringSync();
    final String shared = File('${bridge.path}/src/shared_frame.rs')
        .readAsStringSync();
    expect(capture, contains('GraphicsCaptureApiHandler'));
    expect(capture, contains('self.target.as_deref() != Some(&target)'));
    expect(capture, contains('Window::from_raw_hwnd'));
    expect(shared, contains('CreateFileMappingW'));
    expect(shared, contains('MapViewOfFile'));
  });

  test('draft injection has no focus, keystroke or send path', () {
    final String inject = File('${bridge.path}/src/inject.rs')
        .readAsStringSync();
    expect(inject, contains('IUIAutomationValuePattern'));
    expect(inject, contains('CurrentValue'));
    expect(inject, contains('validate_target(raw)?'));
    expect(inject, contains('window.process_name()?'));
    for (final String forbidden in <String>[
      'SetForegroundWindow',
      'SendInput',
      'keybd_event',
      'VK_RETURN',
      'InvokePattern',
    ]) {
      expect(inject, isNot(contains(forbidden)));
    }
  });

  test('the app process windows are excluded from capture', () {
    final String source = File('lib/src/panel_exclusion.dart')
        .readAsStringSync();
    expect(source, contains('_wdaExcludeFromCapture = 0x11'));
    expect(source, contains('SetWindowDisplayAffinity'));
    expect(source, contains('owner.value != context[0]'));
  });
}
