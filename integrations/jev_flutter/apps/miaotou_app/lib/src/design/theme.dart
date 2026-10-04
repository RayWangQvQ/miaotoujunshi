import 'package:flutter/material.dart';

import 'colors.dart';
import 'spacing.dart';

/// The one [ThemeData] the application builds, from the one palette.
///
/// Material's own colour roles are derived from [AppColors] rather than the
/// other way round. That direction matters: if a page reached for
/// `Theme.of(context).colorScheme.error` it would get a colour nobody in this
/// repository chose, and the audit that keeps raw colours out of `lib/` would
/// have a hole in it. So the scheme exists to keep Material's widgets legible,
/// and the application's own widgets read [AppColors.of].
ThemeData buildTheme({AppColors? colors}) {
  final AppColors palette = colors ?? AppColors.light();
  final ColorScheme scheme = ColorScheme(
    brightness: Brightness.light,
    primary: palette.accent,
    onPrimary: palette.textOnAccent,
    secondary: palette.speakerOther,
    onSecondary: palette.textOnAccent,
    error: palette.toneAlert,
    onError: palette.textOnAccent,
    surface: palette.surface,
    onSurface: palette.textPrimary,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: palette.surface,
    extensions: <ThemeExtension<dynamic>>[palette],
    appBarTheme: AppBarTheme(
      backgroundColor: palette.surface,
      foregroundColor: palette.textPrimary,
      elevation: 0,
      scrolledUnderElevation: 1,
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      color: palette.surfaceRaised,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.card,
        side: BorderSide(color: palette.border),
      ),
    ),
    dividerTheme: DividerThemeData(
      color: palette.border,
      space: AppSpacing.m,
      thickness: 1,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: palette.surfaceRaised,
      elevation: 0,
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: palette.surface,
      elevation: 0,
    ),
  );
}
