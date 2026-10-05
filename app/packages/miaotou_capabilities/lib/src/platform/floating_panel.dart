/// Where the panel sits relative to the screen.
enum PanelAnchor {
  topLeft,
  topRight,
  bottomLeft,
  bottomRight,

  /// Placed by the caller's own coordinates rather than pinned to a corner.
  free,
}

/// Where the panel should appear.
final class PanelPlacement {
  const PanelPlacement({
    required this.anchor,
    this.dx = 0,
    this.dy = 0,
    this.width,
    this.height,
  });

  final PanelAnchor anchor;

  /// Offset from the anchor, in logical screen points.
  final double dx;
  final double dy;

  /// Requested size. Null means "let the panel decide", which is what every port
  /// currently does.
  final double? width;
  final double? height;

  @override
  String toString() =>
      'PanelPlacement(${anchor.name}, +$dx+$dy, ${width ?? '-'}x${height ?? '-'})';
}

/// Something the panel tells the rest of the application about.
sealed class PanelEvent {
  const PanelEvent();
}

/// The user finished dragging the panel to a new position.
final class PanelDragged extends PanelEvent {
  const PanelDragged({required this.x, required this.y});

  /// The landed position, in logical screen points. It is reported rather than
  /// stored so that whoever owns the preference decides whether to keep it.
  final double x;
  final double y;

  @override
  String toString() => 'PanelDragged($x, $y)';
}

/// The user tapped something on the panel.
final class PanelTapped extends PanelEvent {
  const PanelTapped({required this.action});

  /// The tapped element's identifier, as the panel's own content defines it.
  final String action;

  @override
  String toString() => 'PanelTapped($action)';
}

/// The panel's read-only state changed.
///
/// The panel *reports* this; it does not compute it. The derivation belongs to
/// the same owner ADR-0002 gave it — the accessibility service on Android, the
/// main window on the desktop ports — and rendering belongs to the UI layer.
/// This event exists so the UI can redraw when the derivation changes.
final class PanelReadOnlyChanged extends PanelEvent {
  const PanelReadOnlyChanged({required this.readOnly});

  final bool readOnly;

  @override
  String toString() => 'PanelReadOnlyChanged($readOnly)';
}

/// The floating window the advice appears in.
///
/// **Window semantics only.** Placement, visibility, the hide-for-capture pair,
/// focusable toggling and an event stream. What the panel *looks like* is the UI
/// layer's business, which is why nothing here mentions a widget, a colour or a
/// size in device pixels.
abstract interface class FloatingPanel {
  /// Shows the panel and, if it is already up, re-places it.
  Future<void> show({required PanelPlacement placement});

  /// Takes the panel off screen. After this it holds no captured frame.
  Future<void> hide();

  /// Takes the panel off screen for the duration of one capture.
  ///
  /// This is not an optimisation. A screenshot of a window that the panel is
  /// sitting over returns the panel, so the shot must be taken with the panel
  /// gone and the compositor must have dropped its frame first. The 120 ms the
  /// Android port waits for that is a measured value and belongs to the
  /// implementation, not to the caller.
  Future<void> hideForCapture();

  /// Puts the panel back after [hideForCapture].
  Future<void> restoreAfterCapture();

  /// Makes the panel able to take keyboard focus.
  ///
  /// The review page needs an IME to edit a draft; the collapsed ball must not
  /// take focus at all, or it steals the caret from the chat input.
  Future<void> setFocusable(bool value);

  /// What the panel tells the application.
  Stream<PanelEvent> get events;
}
