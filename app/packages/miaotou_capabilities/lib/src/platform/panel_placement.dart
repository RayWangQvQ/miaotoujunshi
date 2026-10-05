import '../model/screen_rect.dart';
import 'floating_panel.dart';

/// Snaps a floating panel to its nearest vertical screen edge.
final class EdgeSnap {
  const EdgeSnap._();

  static const double margin = 0;

  static ScreenRect snap(ScreenRect window, ScreenRect screen) {
    if (screen.isEmpty) {
      return window;
    }

    final double width = window.width > screen.width
        ? screen.width
        : window.width;
    final double height = window.height > screen.height
        ? screen.height
        : window.height;
    final double distanceToLeft = window.left - screen.left;
    final double distanceToRight = screen.right - window.right;
    final double left = distanceToLeft <= distanceToRight
        ? screen.left + margin
        : screen.right - margin - width;

    double top = window.top;
    if (top < screen.top + margin) {
      top = screen.top + margin;
    }
    final double lowest = screen.bottom - margin - height;
    if (top > lowest) {
      top = lowest;
    }

    return ScreenRect.fromLTWH(left, top, width, height);
  }
}

/// Session-scoped memory for a floating panel's last snapped location.
final class PanelPositionMemory {
  ScreenRect? _remembered;

  ScreenRect? get remembered => _remembered;

  ScreenRect? resolve({
    required PanelPlacement placement,
    required ScreenRect screen,
    required ScreenRect size,
  }) {
    if (placement.anchor != PanelAnchor.free) {
      return null;
    }
    if (placement.dx == 0 && placement.dy == 0) {
      return _remembered;
    }
    final ScreenRect landed = EdgeSnap.snap(
      ScreenRect.fromLTWH(placement.dx, placement.dy, size.width, size.height),
      screen,
    );
    _remembered = landed;
    return landed;
  }

  void remember(ScreenRect rect) => _remembered = rect;
}
