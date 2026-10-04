import 'package:flutter/material.dart';

import '../design/colors.dart';
import '../design/spacing.dart';
import 'status_badge.dart';

/// A label above a value.
///
/// The detail view is almost entirely these, and the candidate card has two of
/// them, so it is one widget: a reader who learns where the label sits in one
/// place has learned it everywhere, and a change to the label's weight or colour
/// is one edit rather than a hunt through five pages.
class LabeledBlock extends StatelessWidget {
  const LabeledBlock({
    super.key,
    required this.label,
    required this.value,
    this.tone,
  });

  final String label;

  final String value;

  /// Marks the value as something to read twice. Null keeps it ordinary.
  final StatusTone? tone;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final ThemeData theme = Theme.of(context);
    final Color? valueColor = switch (tone) {
      null => null,
      StatusTone.neutral => colors.textPrimary,
      StatusTone.positive => colors.tonePositive,
      StatusTone.caution => colors.toneCaution,
      StatusTone.alert => colors.toneAlert,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(color: colors.textMuted),
        ),
        AppSpacing.gapXs,
        Text(
          value,
          style: theme.textTheme.bodyMedium?.copyWith(color: valueColor),
        ),
      ],
    );
  }
}
