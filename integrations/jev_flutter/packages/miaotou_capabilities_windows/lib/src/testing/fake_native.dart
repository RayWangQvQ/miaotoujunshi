import 'dart:typed_data';

import 'package:miaotou_capabilities/miaotou_capabilities.dart';

import '../native.dart';

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
