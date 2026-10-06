import 'package:flutter/material.dart';

/// The one spacing scale, and the one set of corner radii.
///
/// Named steps rather than numbers because a number in a page is a number
/// nobody can audit: `EdgeInsets.all(12)` in six files is six decisions, and
/// `AppSpacing.m` in six files is one. The audit in
/// `test/design_system_test.dart` fails if a raw inset literal appears outside
/// `design/`, which is what keeps the scale a scale.
final class AppSpacing {
  const AppSpacing._();

  /// Between a label and the value it labels.
  static const double xs = 4;

  /// Inside a control, and between a control and its neighbour.
  static const double s = 8;

  /// Between two blocks that belong to one card.
  static const double m = 12;

  /// The padding of a card, and the gap between two cards.
  static const double l = 16;

  /// Between a section and the next one.
  static const double xl = 24;

  /// The padding of a page.
  static const double xxl = 32;

  /// The gap a page leaves above its first section on a wide window.
  static const double xxxl = 48;

  static const EdgeInsets card = EdgeInsets.all(m);
  static const EdgeInsets page = EdgeInsets.all(l);

  /// The padding of a card on the floating panel.
  ///
  /// The panel is a 300dp overlay, not a page: every point of padding it pays is
  /// a point of the batch it does not show. A tighter card keeps the header,
  /// the note and the review form from eating the window they share, while the
  /// main window's pages keep [card]'s roomier reading.
  static const EdgeInsets panel = EdgeInsets.all(s);

  /// A row of chips or badges.
  static const EdgeInsets row = EdgeInsets.symmetric(horizontal: s);

  static const SizedBox gapXs = SizedBox(height: xs, width: xs);
  static const SizedBox gapS = SizedBox(height: s, width: s);
  static const SizedBox gapM = SizedBox(height: m, width: m);
  static const SizedBox gapL = SizedBox(height: l, width: l);
}

/// The two widths at which the shell changes shape.
///
/// Widths, not platforms: a small window on a desktop and a tablet in landscape
/// get the same navigation, and a phone held upright gets the other. #11's fifth
/// acceptance criterion is that nothing here asks which platform it is on, and
/// `test/main_window_test.dart` fails if `lib/` starts asking.
final class AppBreakpoint {
  const AppBreakpoint._();

  /// At or above this, the navigation is a rail beside the page.
  static const double rail = 600;

  /// At or above this, the rail shows its labels.
  static const double extendedRail = 1000;
}

/// Corner radii. `pill` is the badge's: a value large enough to be a semicircle
/// at any height, so a badge never has to compute one.
final class AppRadius {
  const AppRadius._();

  /// A chip or an input.
  static const double s = 4;

  /// A card.
  static const double m = 8;

  /// A panel or a dialog.
  static const double l = 12;

  static const double pill = 999;

  static final BorderRadius card = BorderRadius.circular(m);
  static final BorderRadius panel = BorderRadius.circular(l);
  static final BorderRadius pillShape = BorderRadius.circular(pill);
}
