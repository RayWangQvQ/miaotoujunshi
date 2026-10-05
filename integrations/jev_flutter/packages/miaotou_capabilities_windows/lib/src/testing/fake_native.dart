import 'dart:async';
import 'dart:typed_data';

import 'package:miaotou_capabilities/miaotou_capabilities.dart';

import '../native.dart';
import '../panel_native.dart';
import '../secrets.dart';

final class FakeWindowsNative implements WindowsNative {
  FakeWindowsNative({
    this.windowId = '77',
    this.captureOutcome,
    this.injectResult,
  });

  final String? windowId;
  CaptureOutcome? captureOutcome;
  InjectResult? injectResult;
  WindowsBridgeUnavailable? captureError;
  List<OcrLine> lines = const <OcrLine>[];

  final List<String> log = <String>[];
  String? injectedText;

  @override
  Future<String?> findTargetWindow() async {
    log.add('findTargetWindow');
    return windowId;
  }

  @override
  Future<CaptureOutcome> capture({String? targetWindowId}) async {
    log.add('capture:$targetWindowId');
    final WindowsBridgeUnavailable? error = captureError;
    if (error != null) {
      throw error;
    }
    return captureOutcome ??
        CaptureOk(
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
  }

  @override
  Future<List<OcrLine>> recognize(
    CaptureFrame frame, {
    required List<String> languages,
  }) async {
    log.add('recognize:${languages.join('+')}');
    return lines;
  }

  @override
  Future<InjectResult> inject(
    String text, {
    required InjectTarget target,
  }) async {
    log.add('inject:${target.windowId}');
    injectedText = text;
    return injectResult ?? InjectResult.verified(text);
  }
}

final class FakeWindowsPanelNative implements WindowsPanelNative {
  PanelGeometry geometry = const PanelGeometry(
    screen: ScreenRect(left: 0, top: 0, right: 1440, bottom: 900),
    window: ScreenRect(left: 0, top: 0, right: 420, bottom: 620),
  );
  bool visible = false;
  bool focusable = false;
  int restores = 0;
  final List<(PanelPlacement, ScreenRect?)> shows =
      <(PanelPlacement, ScreenRect?)>[];
  final StreamController<NativeWindowsPanelEvent> _events =
      StreamController<NativeWindowsPanelEvent>.broadcast();

  void drag({required ScreenRect window, required ScreenRect screen}) {
    _events.add(NativeWindowsPanelDragged(window: window, screen: screen));
  }

  @override
  Stream<NativeWindowsPanelEvent> get events => _events.stream;

  @override
  Future<PanelGeometry> panelGeometry() async => geometry;

  @override
  Future<void> showPanel({
    required PanelPlacement placement,
    ScreenRect? at,
  }) async {
    visible = true;
    shows.add((placement, at));
  }

  @override
  Future<bool> hidePanel() async {
    final bool wasVisible = visible;
    visible = false;
    return wasVisible;
  }

  @override
  Future<void> restorePanel() async {
    visible = true;
    restores++;
  }

  @override
  Future<void> setPanelFocusable(bool value) async {
    focusable = value;
  }
}

final class MemoryWindowsCredentialBackend implements WindowsCredentialBackend {
  final Map<String, String> _values = <String, String>{};

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async {
    _values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    _values.remove(key);
  }

  @override
  Future<Set<String>> keys() async => _values.keys.toSet();
}
