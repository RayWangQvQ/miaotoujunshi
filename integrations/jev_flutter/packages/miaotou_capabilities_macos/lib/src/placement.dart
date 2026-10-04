import 'package:miaotou_capabilities/miaotou_capabilities.dart';

/// Pulling the floating window flush against the edge of the screen it is on.
///
/// The ball is dragged by a fingertip or a mouse, and neither of them can land it
/// on an edge. Left where it stopped, a ball two pixels from the left edge looks
/// like a bug and a ball in the middle of the screen looks like a decision the
/// user did not make — and the next launch puts it back in the middle again,
/// because nothing was remembered. So the drag is snapped here, in Dart, where it
/// can be tested without a window server.
///
/// ## Why the drag arrives with a size
///
/// [PanelDragged] carries the landed **position** only, because that is what the
/// contract says the panel reports. Snapping cannot be done from a position alone:
/// "flush to the right" is meaningless without knowing how wide the window is. The
/// native side therefore reports the window's own rectangle and this class reduces
/// it to the [PanelDragged] the contract defines — the extra numbers are used and
/// then dropped, rather than added to a published type for the convenience of one
/// caller.
///
/// ## Why anchoring is *not* here
///
/// `PanelAnchor` is resolved natively, where the panel's size is known before it
/// is asked where to go. Doing it in Dart as well would be a second implementation
/// of the same rule, and two implementations of a placement rule drift.
final class EdgeSnap {
  const EdgeSnap._();

  /// The distance the snapped window keeps from the screen edge.
  ///
  /// Zero: the window sits flush. A positive margin is what a panel wants when
  /// macOS puts a screen's own rounded corners there, and it is measured in the
  /// same logical points as everything else on this boundary.
  static const double margin = 0;

  /// Moves [window] flush against whichever vertical edge is nearer, and keeps it
  /// inside [screen] vertically.
  ///
  /// The horizontal edge is chosen by distance, not by which side of the middle the
  /// window happens to be on: a wide panel dragged to the far right is still
  /// nearer the right edge, and a narrow one dropped in the middle is a tie that
  /// resolves left — the side the reading edge is on, so the snap reads as a
  /// continuation of the drag rather than a jump across the screen.
  static ScreenRect snap(ScreenRect window, ScreenRect screen) {
    if (screen.isEmpty) {
      return window;
    }

    final double width = window.width > screen.width ? screen.width : window.width;
    final double height = window.height > screen.height ? screen.height : window.height;

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

/// Where the panel was last put, for as long as this process lives.
///
/// "Remembers its place" is two different promises and only one of them can be kept
/// here. Within a session this class holds the last landed position and offers it
/// back, so hiding the panel and showing it again does not throw the user's
/// arrangement away. **Across launches it cannot**: persistence is
/// `Preferences`, which is #15's to build, and a port that quietly wrote its own
/// plist would be a second store for one value. So the memory here is deliberately
/// session-scoped and says so, and #15 is where it becomes durable.
///
/// An anchored request is never overridden by the memory. `PanelAnchor.topRight`
/// is a decision somebody or something made on purpose, and quietly replacing it
/// with wherever the window happened to be last time would make the anchor
/// untestable — which is the property the anchor exists to have.
final class PanelPositionMemory {
  ScreenRect? _remembered;

  /// The last position the panel was snapped to, or null when it has not moved.
  ScreenRect? get remembered => _remembered;

  /// The position a free placement should use, or null to let the native side
  /// place the window itself.
  ///
  /// A corner anchor is never answered here: the native side resolves those,
  /// because the panel's size is known there and not here. A free placement with
  /// an explicit offset is honoured and remembered, so the next show can put the
  /// window back without being told. A free placement with no offset falls back
  /// to whatever was remembered, and to the native side when nothing was.
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

  /// Records a landed, snapped position.
  void remember(ScreenRect rect) => _remembered = rect;
}
