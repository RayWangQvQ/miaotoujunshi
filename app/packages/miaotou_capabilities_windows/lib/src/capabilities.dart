import 'package:miaotou_capabilities/miaotou_capabilities.dart';
import 'package:miaotou_capabilities_shared/miaotou_capabilities_shared.dart';

import 'native.dart';

/// Windows's answer for screen capture.
///
/// Owned by #17. Capture runs inside the out-of-process native bridge around
/// Windows Graphics Capture (ADR-0013). It is the largest hand-written surface
/// in the migration and the port most likely to overrun.
final class WindowsScreenCapture implements ScreenCapture {
  WindowsScreenCapture(this._native, {CapturePacing? pacing})
    : pacing = pacing ?? CapturePacing();

  final WindowsNative _native;
  final CapturePacing pacing;

  static const int bridgeUnavailableCode = -3;

  @override
  Future<String?> findTargetWindow() => _native.findTargetWindow();

  @override
  Future<CaptureOutcome> capture({String? targetWindowId}) =>
      pacing.run(() async {
        try {
          return await _native.capture(targetWindowId: targetWindowId);
        } on WindowsBridgeUnavailable catch (error) {
          return CaptureFailed(
            code: bridgeUnavailableCode,
            message: 'Windows 原生桥已停止：${error.message}',
          );
        }
      });
}

/// Windows's answer for reading another application's view of itself.
///
/// **Permanent refusal.** No desktop port reads an accessibility node tree to
/// find the conversation: everything they know arrives as pixels, and the text
/// is recovered by OCR. This is the case ADR-0009 decision 2 was written for, and
/// the reason the refusal is `UnsupportedError` rather than a not-yet.
final class WindowsUiTreeReader implements UiTreeReader {
  const WindowsUiTreeReader();

  static const String _platform = 'Windows';
  static const String _reason =
      'the desktop ports read pixels, not accessibility nodes; the words come '
      'back through Ocr';

  @override
  Future<ChatUiSnapshot?> readActiveChat() async => unsupportedOnThisPlatform(
    platform: _platform,
    member: 'UiTreeReader.readActiveChat',
    reason: _reason,
  );

  @override
  Stream<ChatUiSnapshot> get snapshots => unsupportedOnThisPlatform(
    platform: _platform,
    member: 'UiTreeReader.snapshots',
    reason: _reason,
  );
}

/// Windows's answer for the system permissions.
///
/// **Permanent refusal.** The two permissions in the contract are Android's: a
/// foreign window is drawn over only on Android because only Android has a
/// floating overlay to grant, and the accessibility service has no desktop
/// equivalent. This port owns its own windows outright, so the first has nothing
/// to ask for. The second is refusable for a sharper reason than "not needed":
/// Windows' accessibility API *could* answer, and the port deliberately reads
/// pixels instead (Windows Graphics Capture, ADR-0009 decision 6) so that the
/// three ports share one perception path — promising a grant this port would
/// then never consult would be the worse answer.
final class WindowsPermissions implements Permissions {
  const WindowsPermissions();

  static const String _platform = 'Windows';
  static const String _reason =
      'this port owns its own windows and reads pixels rather than an '
      'accessibility tree, so it has neither a floating grant to request nor a '
      'service to bind';

  @override
  Future<PermissionReport> read() async => unsupportedOnThisPlatform(
    platform: _platform,
    member: 'Permissions.read',
    reason: _reason,
  );

  @override
  Future<void> openSettings(PermissionKind kind) async =>
      unsupportedOnThisPlatform(
        platform: _platform,
        member: 'Permissions.openSettings(${kind.name})',
        reason: _reason,
      );
}

/// Windows's answer for OCR.
///
/// Owned by #17. The recognition runs inside the same native bridge as capture —
/// Rust over ONNX Runtime, reusing RapidOCR's models and its post-processing —
/// rather than in Dart (ADR-0009 decision 6). DBNet's post-processing needs
/// contour detection and a perspective crop with no Dart equivalent.
final class WindowsOcr implements Ocr {
  const WindowsOcr(this._native);

  final WindowsNative _native;

  @override
  Future<List<OcrLine>> recognize(
    CaptureFrame frame, {
    required List<String> languages,
  }) => _native.recognize(frame, languages: languages);
}

/// Windows's answer for injecting text.
///
/// Owned by #17. Verifies the landing by reading the field's text back through
/// the same native helper that injected it.
final class WindowsTextInject implements TextInject {
  const WindowsTextInject(this._native);

  final WindowsNative _native;

  @override
  Future<InjectResult> inject(String text, {required InjectTarget target}) =>
      _native.inject(text, target: target);
}
