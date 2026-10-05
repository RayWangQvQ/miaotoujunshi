import 'package:flutter/material.dart';
import 'package:miaotou_domain/miaotou_domain.dart';

import '../design/copy.dart';
import '../design/spacing.dart';
import '../widgets/empty_state.dart';
import '../widgets/labeled_block.dart';
import 'content.dart';

/// What is remembered about one person.
///
/// The field order and the field names come from the payload — `profile_fields`
/// in `relationship-enums.json`, carried as `profileFields` in the domain — so
/// this page is a list of nine labels over nine values rather than a hand-built
/// form. A field the payload stops naming would disappear from the data and from
/// here in the same change, which is the whole reason the domain kept the list.
class KnowledgePage extends StatelessWidget {
  const KnowledgePage({super.key, required this.content});

  final ShellContent content;

  @override
  Widget build(BuildContext context) {
    final AppCopy copy = CopyScope.of(context);
    final Profile? profile = content.profile;
    if (profile == null) {
      return EmptyState(message: copy.text(CopyKey.knowledgeEmpty));
    }

    final List<(CopyKey, String)> rows = <(CopyKey, String)>[
      (CopyKey.profileLabel, profile.label),
      (CopyKey.profileStage, profile.stage),
      (CopyKey.profileGoal, profile.goal),
      (CopyKey.profileBackground, profile.background),
      (CopyKey.profileMyMbti, profile.myMbti),
      (CopyKey.profileTheirMbti, profile.theirMbti),
      (CopyKey.profileMyScore, profile.myScore),
      (CopyKey.profileTheirScore, profile.theirScore),
      (CopyKey.profileNotes, profile.notes),
    ];

    return ListView(
      padding: AppSpacing.page,
      children: <Widget>[
        for (final (CopyKey key, String value) in rows)
          if (value.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.m),
              child: LabeledBlock(
                label: copy.text(key),
                value: value,
              ),
            ),
      ],
    );
  }
}
