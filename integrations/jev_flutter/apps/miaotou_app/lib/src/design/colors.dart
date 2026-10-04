import 'package:flutter/material.dart';

/// Every colour the application uses, named by what it means.
///
/// A page never writes `Colors.red`; it asks for [balanceUp]. That is the whole
/// point of this file, and it is what makes "colour semantics exist once"
/// checkable rather than intended: the audit in `test/design_system_test.dart`
/// fails if a raw `Color` literal appears anywhere outside `design/`.
///
/// Two decisions here are worth knowing before changing a value:
///
/// * **Rising is red and falling is green.** The K-line borrows the Chinese
///   market's idiom, and a reader of this chart is a reader of that idiom. It is
///   a direction, not a verdict — the balance rising does not mean the day went
///   well, and `#8`'s `metric_note` is the sentence that says so.
/// * **A failure is dark red, and is not the chart's red.** [balanceUp] and
///   [toneAlert] are deliberately different values: one says "this number went
///   up", the other says "something broke", and a reader should not have to
///   guess which one a red patch means.
///
/// One palette only. A dark palette is a separate piece of work and would
/// double every value here, so it waits until somebody asks for it.
final class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.surface,
    required this.surfaceRaised,
    required this.surfaceSunken,
    required this.border,
    required this.borderStrong,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.textOnAccent,
    required this.accent,
    required this.accentMuted,
    required this.speakerMe,
    required this.speakerOther,
    required this.balanceUp,
    required this.balanceDown,
    required this.toneNeutral,
    required this.tonePositive,
    required this.toneCaution,
    required this.toneCautionBackground,
    required this.toneAlert,
  });

  /// The page behind everything else.
  final Color surface;

  /// A card or a panel sitting on [surface].
  final Color surfaceRaised;

  /// A well: an inset area such as a code block or a disabled field.
  final Color surfaceSunken;

  final Color border;
  final Color borderStrong;

  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;

  /// Text drawn on [accent].
  final Color textOnAccent;

  /// The one hue that means "this is the thing you do next".
  final Color accent;

  /// [accent] as a background, for a selected row or a soft button.
  final Color accentMuted;

  /// Attribution for a line the user wrote.
  final Color speakerMe;

  /// Attribution for a line the other person wrote.
  final Color speakerOther;

  /// The balance rose: other wrote more than me that day.
  final Color balanceUp;

  /// The balance fell.
  final Color balanceDown;

  /// A badge that states a fact, such as a candidate's rank.
  final Color toneNeutral;

  /// A badge that states something went right, such as a completed save.
  final Color tonePositive;

  /// A badge that states a caveat, such as "排序暂不可用". Nothing is broken.
  final Color toneCaution;

  /// [toneCaution] as a background, for the read-only banner on the panel
  /// (ADR-0002 decision 3 asks for a banner, and a banner needs a field to sit
  /// on rather than a border).
  final Color toneCautionBackground;

  /// A badge that states a failure. Something is broken.
  final Color toneAlert;

  /// The one palette the application ships.
  factory AppColors.light() => const AppColors(
        surface: Color(0xFFF7F5F2),
        surfaceRaised: Color(0xFFFFFFFF),
        surfaceSunken: Color(0xFFEFEBE5),
        border: Color(0xFFDCD6CE),
        borderStrong: Color(0xFFB9B0A4),
        textPrimary: Color(0xFF1F1B18),
        textSecondary: Color(0xFF5B534C),
        textMuted: Color(0xFF8A817A),
        textOnAccent: Color(0xFFFFFFFF),
        accent: Color(0xFF2E6F62),
        accentMuted: Color(0xFFD5E5E0),
        speakerMe: Color(0xFF2E6F62),
        speakerOther: Color(0xFF9A5B34),
        balanceUp: Color(0xFFC0392B),
        balanceDown: Color(0xFF1E8E4E),
        toneNeutral: Color(0xFF8A817A),
        tonePositive: Color(0xFF2E6F62),
        toneCaution: Color(0xFFB7791F),
        toneCautionBackground: Color(0xFFFBF1DE),
        toneAlert: Color(0xFF8E2F2F),
      );

  /// The values that must not collapse into each other, and why.
  ///
  /// Read by the test rather than asserted here, because the reason each pair is
  /// on the list is a sentence and sentences belong in one place.
  static const List<(String, String)> distinctPairs = <(String, String)>[
    ('speakerMe', 'speakerOther'),
    ('balanceUp', 'balanceDown'),
    ('balanceUp', 'toneAlert'),
    ('toneCaution', 'toneAlert'),
    ('textPrimary', 'textSecondary'),
    ('surface', 'surfaceRaised'),
  ];

  /// Reads the palette out of the theme, so a page never holds one.
  static AppColors of(BuildContext context) {
    final AppColors? colors = Theme.of(context).extension<AppColors>();
    if (colors == null) {
      throw StateError(
        'no AppColors in the theme; the application was built without '
        'design/theme.dart, and a page is asking for a colour it cannot name',
      );
    }
    return colors;
  }

  /// One value by the name the audit uses.
  ///
  /// Exists for the test that walks [distinctPairs]; nothing in the UI reads a
  /// colour by string.
  Color byName(String name) => switch (name) {
        'surface' => surface,
        'surfaceRaised' => surfaceRaised,
        'surfaceSunken' => surfaceSunken,
        'border' => border,
        'borderStrong' => borderStrong,
        'textPrimary' => textPrimary,
        'textSecondary' => textSecondary,
        'textMuted' => textMuted,
        'textOnAccent' => textOnAccent,
        'accent' => accent,
        'accentMuted' => accentMuted,
        'speakerMe' => speakerMe,
        'speakerOther' => speakerOther,
        'balanceUp' => balanceUp,
        'balanceDown' => balanceDown,
        'toneNeutral' => toneNeutral,
        'tonePositive' => tonePositive,
        'toneCaution' => toneCaution,
        'toneCautionBackground' => toneCautionBackground,
        'toneAlert' => toneAlert,
        _ => throw ArgumentError('no colour named $name'),
      };

  @override
  ThemeExtension<AppColors> copyWith() => this;

  @override
  ThemeExtension<AppColors> lerp(
    covariant ThemeExtension<AppColors>? other,
    double t,
  ) =>
      this;
}
