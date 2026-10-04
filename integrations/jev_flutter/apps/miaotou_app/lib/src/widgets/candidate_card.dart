import 'package:flutter/material.dart';
import 'package:miaotou_domain/miaotou_domain.dart';

import '../design/colors.dart';
import '../design/copy.dart';
import '../design/spacing.dart';
import 'labeled_block.dart';
import 'status_badge.dart';

/// One draft reply, with the two lines that explain it and the weight that ranks
/// it.
///
/// Shared between the detail page and the panel, which is the reason it is a
/// component at all: the same draft has to read the same way in both places, and
/// a candidate rendered by two pieces of code is a candidate whose weight badge
/// will eventually mean two things.
///
/// **A missing weight is not a zero weight.** [Candidate.weight] is null until
/// the ranking step has run, and showing `0%` would claim the draft lost. The
/// card says "未排序" instead — the domain is careful about that distinction in
/// `RankingStatus`, and this is where a careless rendering would undo it.
class CandidateCard extends StatelessWidget {
  const CandidateCard({
    super.key,
    required this.candidate,
    required this.rank,
    this.rankingStatus,
    this.onCopy,
  });

  final Candidate candidate;

  /// One-based, in the order the panel should show them.
  final int rank;

  /// How far the ranking got. [RankingStatus.unavailable] is the one that
  /// changes what the card says about the weight.
  final RankingStatus? rankingStatus;

  /// Copies the draft. Null means there is nowhere to copy it to yet.
  final VoidCallback? onCopy;

  @override
  Widget build(BuildContext context) {
    final AppCopy copy = CopyScope.of(context);
    final AppColors colors = AppColors.of(context);
    final ThemeData theme = Theme.of(context);
    final int? weight = candidate.weight;
    final bool rankingFailed = rankingStatus == RankingStatus.unavailable;

    return Card(
      child: Padding(
        padding: AppSpacing.card,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Wrap(
              spacing: AppSpacing.s,
              runSpacing: AppSpacing.xs,
              children: <Widget>[
                StatusBadge(
                  label: '${copy.text(CopyKey.candidateRank)} $rank',
                ),
                if (rankingFailed)
                  StatusBadge(
                    label: copy.text(CopyKey.rankingUnavailable),
                    tone: StatusTone.caution,
                  )
                else if (weight == null)
                  StatusBadge(label: copy.text(CopyKey.candidateUnranked))
                else
                  StatusBadge(
                    label: '${copy.text(CopyKey.candidateWeight)} $weight%',
                    tone: StatusTone.positive,
                  ),
              ],
            ),
            AppSpacing.gapS,
            Text(
              candidate.text,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: colors.textPrimary,
                height: 1.5,
              ),
            ),
            AppSpacing.gapS,
            LabeledBlock(
              label: copy.text(CopyKey.candidateReason),
              value: candidate.reason,
            ),
            AppSpacing.gapS,
            LabeledBlock(
              label: copy.text(CopyKey.candidateTradeoff),
              value: candidate.tradeoff,
            ),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton.icon(
                onPressed: onCopy,
                icon: const Icon(Icons.content_copy, size: 16),
                label: Text(copy.text(CopyKey.candidateCopy)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
