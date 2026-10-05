import 'package:miaotou_capabilities/miaotou_capabilities.dart';

import 'ingest_native.dart';
import 'panel_native.dart';

/// Android's answer for screen capture.
///
/// Owned by #22. The `takeScreenshot` / `takeScreenshotOfWindow` calls stay in
/// Kotlin, along with the 1s rate limit, the 1→30s backoff and the 3s watchdog
/// that were calibrated on real devices (ADR-0009 decision 1).
///
/// A frame here is a *window*, not the screen, which is why CaptureFrame carries
/// the origin and the scale that map it back.
final class AndroidScreenCapture implements ScreenCapture {
  AndroidScreenCapture(this._native);

  final AndroidIngestNative _native;

  @override
  Future<String?> findTargetWindow() => _native.findTargetWindow();

  @override
  Future<CaptureOutcome> capture({String? targetWindowId}) =>
      _native.capture(targetWindowId: targetWindowId);
}

/// Android's answer for reading the foreground application's own view of itself.
///
/// Owned by #22. **This is the capability only Android has.** An
/// `AccessibilityService` wakes on a content change and hands over a node tree,
/// which is how this port reads a conversation without photographing it — and
/// why the two desktop packages refuse the same interface permanently
/// (ADR-0009 decision 2). The service itself stays Kotlin: it is a system-bound
/// component that Flutter neither can nor needs to host (ADR-0007 decision 5).
final class AndroidUiTreeReader implements UiTreeReader {
  AndroidUiTreeReader(this._native);

  final AndroidIngestNative _native;

  @override
  Future<ChatUiSnapshot?> readActiveChat() => _native.readActiveChat();

  @override
  late final Stream<ChatUiSnapshot> snapshots = _native.events
      .where((AndroidIngestEvent event) => event is AndroidSnapshotEvent)
      .cast<AndroidSnapshotEvent>()
      .map((AndroidSnapshotEvent event) => event.snapshot);
}

/// Android's answer for OCR.
///
/// Owned by #22. Backed by ML Kit, and also by the cloud vision route the port
/// already offers — the one endpoint that sends a screenshot anywhere, and the
/// reason the visibility question in PRIVACY.md stays open.
final class AndroidOcr implements Ocr {
  AndroidOcr(this._native);

  final AndroidIngestNative _native;

  @override
  Future<List<OcrLine>> recognize(
    CaptureFrame frame, {
    required List<String> languages,
  }) => _native.recognize(frame, languages: languages);
}

/// Android's answer for injecting text.
///
/// Owned by #22. `ACTION_SET_TEXT` or `ACTION_PASTE`, and the landing is verified
/// by reading the node's text back.
final class AndroidTextInject implements TextInject {
  AndroidTextInject(this._native);

  final AndroidIngestNative _native;

  @override
  Future<InjectResult> inject(String text, {required InjectTarget target}) =>
      _native.inject(text, target: target);
}

/// Android's answer for the floating window.
///
/// Owned by #21. A hand-written Kotlin plugin, not `flutter_overlay_window`: that
/// package has had no commit in fifteen months and its open defects include a
/// hang in `closeOverlay()` (ADR-0007). The plugin owns the window semantics; the
/// panel's content is rendered by Flutter in a second engine, and the gate-A
/// experiment on a real device is what established that all four rendering pieces
/// are required.
final class AndroidFloatingPanel implements FloatingPanel {
  AndroidFloatingPanel({
    AndroidPanelNative? native,
    this.hideSettle = const Duration(milliseconds: 120),
  }) : _native = native ?? MethodChannelAndroidPanelNative();

  final AndroidPanelNative _native;
  final Duration hideSettle;
  bool _upBeforeCapture = false;

  @override
  Future<void> show({required PanelPlacement placement}) =>
      _native.showPanel(placement);

  @override
  Future<void> hide() async {
    _upBeforeCapture = false;
    await _native.hidePanel();
  }

  @override
  Future<void> hideForCapture() async {
    _upBeforeCapture = await _native.hidePanel();
    if (_upBeforeCapture) {
      await Future<void>.delayed(hideSettle);
    }
  }

  @override
  Future<void> restoreAfterCapture() async {
    if (!_upBeforeCapture) {
      return;
    }
    _upBeforeCapture = false;
    await _native.restorePanel();
  }

  @override
  Future<void> setFocusable(bool value) => _native.setPanelFocusable(value);

  @override
  late final Stream<PanelEvent> events = _native.panelEvents.map(
    (AndroidPanelEvent event) => switch (event) {
      AndroidPanelDragged(:final double x, :final double y) => PanelDragged(
        x: x,
        y: y,
      ),
      AndroidPanelTapped(:final String action) => PanelTapped(action: action),
      AndroidPanelReadOnly(:final bool readOnly) => PanelReadOnlyChanged(
        readOnly: readOnly,
      ),
    },
  );
}
