import 'dart:typed_data';

import '../model/screen_rect.dart';

/// One captured bitmap plus the geometry needed to map a position in it back to
/// the screen.
///
/// Geometry travels with the frame because the screenshot is not the screen: a
/// capture is taken of a *window*, at whatever scale the display runs at, and a
/// position in the bitmap means nothing downstream until it has been mapped
/// back. The mapping is the implementation's business; the arithmetic is here so
/// that all three ports do it the same way.
final class CaptureFrame {
  const CaptureFrame({
    required this.pixels,
    required this.width,
    required this.height,
    required this.scaleX,
    required this.scaleY,
    required this.originX,
    required this.originY,
  });

  /// Raw pixels, in memory only. This never reaches disk (PRIVACY.md), which is
  /// why the type carries a byte list rather than a path.
  final Uint8List pixels;

  final int width;
  final int height;

  /// Bitmap pixels per logical screen point, along each axis.
  final double scaleX;
  final double scaleY;

  /// The screen position of the bitmap's top-left corner, in logical points.
  final double originX;
  final double originY;

  bool get hasPixels => pixels.isNotEmpty && width > 0 && height > 0;

  /// The region of the screen this frame covers.
  ScreenRect get region =>
      ScreenRect.fromLTWH(originX, originY, width / scaleX, height / scaleY);

  /// Maps a rectangle measured in the bitmap's own coordinates back to screen
  /// coordinates. This is what turns an OCR line's position into something the
  /// panel can point at.
  ScreenRect mapToScreen(ScreenRect bitmapRect) => ScreenRect(
        left: originX + bitmapRect.left / scaleX,
        top: originY + bitmapRect.top / scaleY,
        right: originX + bitmapRect.right / scaleX,
        bottom: originY + bitmapRect.bottom / scaleY,
      );

  @override
  String toString() =>
      'CaptureFrame(${width}x$height, scale ${scaleX}x$scaleY, '
      'origin ($originX, $originY))';
}

/// The result of asking for a frame.
///
/// A failure is a value rather than an exception because a refused capture is an
/// expected condition — the window is minimised, the surface is protected, the
/// rate limit is still running — and the caller has a decision to make about
/// each. Exceptions are reserved for the platform being unable to answer at all.
sealed class CaptureOutcome {
  const CaptureOutcome();
}

final class CaptureOk extends CaptureOutcome {
  const CaptureOk(this.frame);

  final CaptureFrame frame;

  @override
  String toString() => 'CaptureOk($frame)';
}

final class CaptureFailed extends CaptureOutcome {
  const CaptureFailed({required this.code, required this.message});

  /// The platform's own error code, passed through rather than translated: the
  /// three platforms do not share a taxonomy and inventing one would hide what
  /// actually happened.
  final int code;

  final String message;

  @override
  String toString() => 'CaptureFailed($code: $message)';
}

/// Reading pixels off the screen or off one window of it.
abstract interface class ScreenCapture {
  /// The window handle to pass back to [capture], or null when no target is
  /// found. There is never a fallback window: capturing the wrong window
  /// silently is worse than capturing nothing.
  ///
  /// The caller holds the returned handle across frames rather than asking
  /// again each time. WeChat 4.x exposes several equally sized windows, so
  /// re-selecting on every frame makes the target jump between them.
  Future<String?> findTargetWindow();

  /// Takes one frame. [targetWindowId] comes from [findTargetWindow]; null means
  /// "the screen", which is the only thing the desktop ports can always do.
  ///
  /// Timing — the rate limit, the backoff, the watchdog, and hiding the panel
  /// before the shot so the compositor drops its frame — belongs to the
  /// implementation, not to this interface (ADR-0009).
  Future<CaptureOutcome> capture({String? targetWindowId});
}
