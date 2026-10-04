import 'package:flutter/material.dart';

import '../design/colors.dart';
import '../design/spacing.dart';

/// What a badge is telling the reader.
///
/// Four tones, not two: "the ranking did not run" ([caution]) and "the ranking
/// threw" ([alert]) are different statements about different things, and the old
/// ports collapsed both into a warning colour. The colour is not the message —
/// the words are — but a reader who has learned the difference should be able to
/// see it.
enum StatusTone {
  /// A fact with no valence: a rank, a count, a name.
  neutral,

  /// Something finished the way it was meant to.
  positive,

  /// Something to know about, and nothing is broken.
  caution,

  /// Something failed.
  alert,
}

/// One short label in a pill.
///
/// Shared because the same four states appear on the candidate card, on the
/// trend view and later on the panel, and a badge drawn twice is a badge whose
/// two copies disagree about what amber means.
class StatusBadge extends StatelessWidget {
  const StatusBadge({
    super.key,
    required this.label,
    this.tone = StatusTone.neutral,
  });

  final String label;

  final StatusTone tone;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final Color color = switch (tone) {
      StatusTone.neutral => colors.toneNeutral,
      StatusTone.positive => colors.tonePositive,
      StatusTone.caution => colors.toneCaution,
      StatusTone.alert => colors.toneAlert,
    };

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: AppRadius.pillShape,
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        label,
        style: Theme.of(context)
            .textTheme
            .labelSmall
            ?.copyWith(color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}
