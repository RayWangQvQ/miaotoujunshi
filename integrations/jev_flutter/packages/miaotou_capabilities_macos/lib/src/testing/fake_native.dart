import 'dart:async';
import 'dart:typed_data';

import 'package:miaotou_capabilities/miaotou_capabilities.dart';
import 'package:miaotou_capabilities_macos/miaotou_capabilities_macos.dart';

/// A scripted macOS.
///
/// The point of the seam ([MacosNative]) is that everything above it can be
/// exercised with no Mac attached. This is the Mac: it answers, it records the
/// order it was asked in, and it can be told to fail.
///
/// The call log is the interesting part. Several of the properties #14 asks for
/// are statements about **order** — the panel has to be hidden before the frame
/// is taken and given back after — and an assertion about the return value alone
/// cannot see an ordering mistake.
class FakeMacosNative implements MacosNative {
  FakeMacosNative({
    this.windowId = '77',
    this.frame,
    this.lines = const <OcrLine>[],
    this.captureOutcome,
    this.injectResult,
    this.screen = const ScreenRect(left: 0, top: 0, right: 1440, bottom: 900),
    this.window = const ScreenRect(left: 100, top: 100, right: 520, bottom: 720),
  });

  final String? windowId;
  final CaptureFrame? frame;
  final List<OcrLine> lines;

  /// What the next capture answers. Settable so a test can make one fail.
  CaptureOutcome? captureOutcome;

  /// What the next injection answers.
  InjectResult? injectResult;
  final ScreenRect screen;
  final ScreenRect window;

  /// Every call, in the order it arrived. `'hide'`, `'capture:77'`, `'show'`, …
  final List<String> log = <String>[];

  /// Whether the panel is on screen, which the real host tracks and this one has
  /// to as well: the restore path depends on knowing what was taken.
  bool panelUp = false;

  bool focusable = false;
  String? injectedText;

  final StreamController<NativePanelEvent> _events =
      StreamController<NativePanelEvent>.broadcast();

  /// Something the panel "said".
  void emit(NativePanelEvent event) => _events.add(event);

  @override
  Future<String?> findTargetWindow() async {
    log.add('findTargetWindow');
    return windowId;
  }

  @override
  Future<CaptureOutcome> capture({String? targetWindowId}) async {
    log.add('capture:$targetWindowId');
    return captureOutcome ??
        CaptureOk(
          frame ??
              CaptureFrame(
                pixels: Uint8List.fromList(<int>[1, 2, 3, 4]),
                width: 2,
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
  Future<InjectResult> inject(String text, {required InjectTarget target}) async {
    log.add('inject:${target.windowId}');
    injectedText = text;
    return injectResult ?? InjectResult.verified(text);
  }

  @override
  Future<PanelGeometry> panelGeometry() async {
    log.add('panelGeometry');
    return PanelGeometry(screen: screen, window: window);
  }

  @override
  Future<void> showPanel({required PanelPlacement placement, ScreenRect? at}) async {
    log.add(at == null ? 'show:${placement.anchor.name}' : 'show:at');
    panelUp = true;
  }

  @override
  Future<void> restorePanel() async {
    log.add('restore');
    panelUp = true;
  }

  @override
  Future<bool> hidePanel() async {
    log.add('hide');
    final bool was = panelUp;
    panelUp = false;
    return was;
  }

  @override
  Future<void> setPanelFocusable(bool value) async {
    log.add('focusable:$value');
    focusable = value;
  }

  @override
  Stream<NativePanelEvent> get events => _events.stream;

  Future<void> close() => _events.close();
}
