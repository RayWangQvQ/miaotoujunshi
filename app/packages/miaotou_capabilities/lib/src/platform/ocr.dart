import '../model/screen_rect.dart';
import 'screen_capture.dart';

/// One recognised line of text.
final class OcrLine {
  const OcrLine({
    required this.text,
    required this.bounds,
    required this.confidence,
  });

  final String text;

  /// In the frame's own bitmap coordinates. Use [CaptureFrame.mapToScreen] to
  /// turn it into something the panel can point at.
  final ScreenRect bounds;

  /// The engine's own confidence, 0..1. Not comparable across engines — the
  /// three platforms score differently — so a caller may compare it against a
  /// threshold it chose for one platform, and nothing else.
  final double confidence;

  @override
  String toString() => 'OcrLine($text, $bounds, ${confidence.toStringAsFixed(2)})';
}

/// Reading text out of pixels.
///
/// The implementations are three different engines — Apple Vision, ML Kit and
/// RapidOCR — and on Windows the work happens inside the native bridge rather
/// than in Dart (ADR-0009 decision 6). This interface exists so that none of
/// that reaches the caller.
abstract interface class Ocr {
  /// Recognises text in [frame].
  ///
  /// [languages] is an ordered preference list supplied by the caller, for
  /// example `['zh-Hans', 'en']`. No implementation chooses the language set:
  /// it would then differ per port and per device, and the same screenshot
  /// would read differently depending on where it was taken.
  Future<List<OcrLine>> recognize(
    CaptureFrame frame, {
    required List<String> languages,
  });
}
