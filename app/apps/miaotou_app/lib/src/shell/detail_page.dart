import 'package:flutter/material.dart';
import 'package:miaotou_domain/miaotou_domain.dart';

import '../design/copy.dart';
import '../design/spacing.dart';
import '../widgets/candidate_card.dart';
import '../widgets/empty_state.dart';
import '../widgets/labeled_block.dart';
import '../widgets/status_badge.dart';
import 'content.dart';

/// The analysis, read at length.
///
/// The panel shows a draft; this page shows why the draft is what it is. It is
/// also the page that first reveals a design constraint worth writing down: the
/// intent's self-assessed confidence is **not** shown here. That sentence is
/// rendered by the domain (`intentConfidenceLabel`), because it is part of what
/// the model is told and what it comes back with, and #11's rule is that copy a
/// page writes lives in `design/copy.dart` while copy the domain owns travels
/// with the domain. Mixing the two in one audit would make "every page uses the
/// copy file" untestable, so the confidence line waits for #12, which owns panel
/// content.
class DetailPage extends StatelessWidget {
  const DetailPage({
    super.key,
    required this.content,
    this.onCopyCandidate,
  });

  final ShellContent content;

  /// Puts a draft on the clipboard. Null until a port provides one.
  final void Function(String text)? onCopyCandidate;

  @override
  Widget build(BuildContext context) {
    final AppCopy copy = CopyScope.of(context);
    final Advice? advice = content.advice;
    if (advice == null) {
      return EmptyState(message: copy.text(CopyKey.detailEmpty));
    }

    final ThemeData theme = Theme.of(context);
    // A local, so the closure below is checked against a promoted value rather
    // than against a field the compiler cannot prove is non-null.
    final void Function(String text)? copyCandidate = onCopyCandidate;

    return ListView(
      padding: AppSpacing.page,
      children: <Widget>[
        LabeledBlock(
          label: copy.text(CopyKey.detailSupport),
          value: advice.support,
        ),
        AppSpacing.gapM,
        LabeledBlock(
          label: copy.text(CopyKey.detailStrategy),
          value: advice.strategy,
        ),
        AppSpacing.gapM,
        LabeledBlock(
          label: copy.text(CopyKey.detailRecommendation),
          value: advice.recommendation,
        ),
        AppSpacing.gapM,
        LabeledBlock(
          label: copy.text(CopyKey.detailNextStep),
          value: advice.nextStep,
        ),
        AppSpacing.gapM,
        LabeledBlock(
          label: copy.text(CopyKey.detailStopCondition),
          value: advice.stopCondition,
        ),
        AppSpacing.gapM,
        LabeledBlock(
          label: copy.text(CopyKey.detailQuestion),
          value: advice.question,
        ),
        if (advice.facts.isNotEmpty) ...<Widget>[
          AppSpacing.gapM,
          LabeledBlock(
            label: copy.text(CopyKey.detailFacts),
            value: advice.facts.join('\n'),
          ),
        ],
        if (advice.hypotheses.isNotEmpty) ...<Widget>[
          AppSpacing.gapM,
          LabeledBlock(
            label: copy.text(CopyKey.detailHypotheses),
            value: advice.hypotheses.join('\n'),
            tone: StatusTone.caution,
          ),
        ],
        if (advice.unknowns.isNotEmpty) ...<Widget>[
          AppSpacing.gapM,
          LabeledBlock(
            label: copy.text(CopyKey.detailUnknowns),
            value: advice.unknowns.join('\n'),
          ),
        ],
        AppSpacing.gapL,
        Text(
          copy.text(CopyKey.detailCandidates),
          style: theme.textTheme.titleSmall,
        ),
        AppSpacing.gapS,
        for (int index = 0; index < advice.candidates.length; index++)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.m),
            child: CandidateCard(
              candidate: advice.candidates[index],
              rank: index + 1,
              rankingStatus: advice.rankingStatus,
              onCopy: copyCandidate == null
                  ? null
                  : () => copyCandidate(advice.candidates[index].text),
            ),
          ),
      ],
    );
  }
}
