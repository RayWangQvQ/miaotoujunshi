import 'dart:convert';

import 'package:miaotou_capabilities/miaotou_capabilities.dart';

import '../panel/protocol.dart';

/// The panel's own settings: how solid it is, and where it was left.
///
/// **One prefix, one owner.** Both keys live in [Preferences] under `panel.`,
/// which is the main window's store, and the main window is the only thing that
/// reads or writes them. The panel engine has no store at all — it is *fed* the
/// appearance over the panel protocol — so there is no second reader and no
/// drift (ADR-0002 decision 2, ADR-0020).
///
/// The placement is one JSON value rather than two numbers because
/// [Preferences] has no number type with a fraction in it: `String`, `bool`,
/// `int` and `List<String>` are the whole contract, and widening it to store a
/// pair of coordinates would be a change to all three ports for one value that
/// is already a [PanelPlacement]. Three ports used to keep this in three
/// different places — a JSON file on Windows, a native preference file on
/// Android, process memory on macOS — and those stores are gone.
final class PanelSettings {
  const PanelSettings({
    this.appearance = const PanelAppearance(),
    this.placement,
  });

  static const String appearanceKey = 'panel.opacity';
  static const String placementKey = 'panel.placement';

  final PanelAppearance appearance;

  /// Where the user last left the panel, or null when they never dragged it.
  ///
  /// Null is a real answer and not the same as `(0, 0)`: a port that has never
  /// been given a placement picks its own first-run corner, and telling it to go
  /// to the origin would put the panel in the top-left of the screen on every
  /// machine that has never dragged it.
  final PanelPlacement? placement;

  static Future<PanelSettings> load(Preferences preferences) async {
    final int? opacity = await preferences.getInt(appearanceKey);
    final String? placement = await preferences.getString(placementKey);
    return PanelSettings(
      appearance: opacity == null
          ? const PanelAppearance()
          : PanelAppearance.percent(opacity),
      placement: placement == null ? null : decodePlacement(placement),
    );
  }

  /// Writes the fill alpha. Deliberately not part of a whole-settings save: the
  /// slider writes here on its own, so that dragging it cannot go through the
  /// settings page's `_save()`, which rebuilds a [ModelSettings] from
  /// `defaults` and would blank four analysis fields on the way past.
  static Future<void> saveAppearance(
    Preferences preferences,
    PanelAppearance appearance,
  ) => preferences.setInt(appearanceKey, appearance.opacity);

  static Future<void> savePlacement(
    Preferences preferences,
    PanelPlacement placement,
  ) => preferences.setString(placementKey, encodePlacement(placement));

  static String encodePlacement(PanelPlacement placement) =>
      jsonEncode(<String, Object?>{
        'anchor': placement.anchor.name,
        'dx': placement.dx,
        'dy': placement.dy,
      });

  /// Refuses a value this codebase could not have written.
  ///
  /// **Throws rather than falling back to the default.** A panel that silently
  /// reverts to its first-run corner after a bad read is a bug nobody can see,
  /// and this key has exactly one writer; the same posture as the panel protocol
  /// and the capability contract, both of which report an unrepresentable case
  /// instead of inventing an answer for it.
  static PanelPlacement decodePlacement(String raw) {
    final Object? decoded = jsonDecode(raw);
    if (decoded is! Map<Object?, Object?>) {
      throw const FormatException('panel.placement must be a JSON object');
    }
    final Object? anchor = decoded['anchor'];
    if (anchor is! String) {
      throw const FormatException('panel.placement.anchor must be a string');
    }
    return PanelPlacement(
      anchor: PanelAnchor.values.firstWhere(
        (PanelAnchor value) => value.name == anchor,
        orElse: () => throw FormatException('unknown panel anchor $anchor'),
      ),
      dx: _finite(decoded, 'dx'),
      dy: _finite(decoded, 'dy'),
    );
  }

  static double _finite(Map<Object?, Object?> map, String key) {
    final Object? value = map[key];
    if (value is! num || !value.toDouble().isFinite) {
      throw FormatException('panel.placement.$key must be finite');
    }
    return value.toDouble();
  }
}
