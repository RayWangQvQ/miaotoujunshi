/// A rectangle in screen coordinates, in logical points.
///
/// The contract carries its own rectangle type instead of `dart:ui`'s `Rect`
/// on purpose: the interface package is platform-free, `dart:ui` exists only
/// inside Flutter, and a package that imported it could no longer be exercised
/// with `dart test` — the cheapest part of the new test story (ADR-0008). The
/// application converts to `Rect` where it paints.
final class ScreenRect {
  const ScreenRect({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  const ScreenRect.fromLTWH(double left, double top, double width, double height)
      : left = left,
        top = top,
        right = left + width,
        bottom = top + height;

  /// A rectangle with no area, for a position that is known but a size that is
  /// not.
  static const ScreenRect empty = ScreenRect(left: 0, top: 0, right: 0, bottom: 0);

  final double left;
  final double top;
  final double right;
  final double bottom;

  double get width => right - left;

  double get height => bottom - top;

  bool get isEmpty => width <= 0 || height <= 0;

  bool contains(double x, double y) =>
      x >= left && x <= right && y >= top && y <= bottom;

  ScreenRect translatedBy(double dx, double dy) =>
      ScreenRect(left: left + dx, top: top + dy, right: right + dx, bottom: bottom + dy);

  ScreenRect scaledBy(double sx, double sy) => ScreenRect(
        left: left * sx,
        top: top * sy,
        right: right * sx,
        bottom: bottom * sy,
      );

  @override
  bool operator ==(Object other) =>
      other is ScreenRect &&
      other.left == left &&
      other.top == top &&
      other.right == right &&
      other.bottom == bottom;

  @override
  int get hashCode => Object.hash(left, top, right, bottom);

  @override
  String toString() => 'ScreenRect(left: $left, top: $top, '
      'width $width, height $height)';
}
