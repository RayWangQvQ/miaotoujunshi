import 'package:flutter/material.dart';
import 'package:miaotou_domain/miaotou_domain.dart';

import '../design/copy.dart';
import '../design/spacing.dart';
import '../widgets/empty_state.dart';
import '../widgets/labeled_block.dart';
import '../widgets/status_badge.dart';
import '../widgets/trend_chart.dart';
import 'content.dart';

/// The K-line, and the two counts that say what it was built from.
///
/// The chart needs two things, not one: the candles and the contract they were
/// read under. A trend without its `TrendRules` is a picture with no stated
/// metric, so this page shows the empty state rather than drawing one — the
/// disclaimer is part of the data's meaning and not decoration hung underneath
/// it.
class TrendPage extends StatelessWidget {
  const TrendPage({super.key, required this.content});

  final ShellContent content;

  @override
  Widget build(BuildContext context) {
    final AppCopy copy = CopyScope.of(context);
    final Trend? trend = content.trend;
    final TrendRules? rules = content.trendRules;
    if (trend == null || rules == null) {
      return EmptyState(message: copy.text(CopyKey.trendEmpty));
    }

    return ListView(
      padding: AppSpacing.page,
      children: <Widget>[
        TrendChart(trend: trend, metricNote: rules.metricNote),
        AppSpacing.gapM,
        Wrap(
          spacing: AppSpacing.s,
          runSpacing: AppSpacing.xs,
          children: <Widget>[
            StatusBadge(
              label: '${copy.text(CopyKey.trendDayCount)}'
                  '${trend.candles.length}'
                  '${copy.text(CopyKey.trendDayUnit)}',
            ),
            StatusBadge(
              label: '${trend.messages}${copy.text(CopyKey.trendMessages)}',
            ),
          ],
        ),
        AppSpacing.gapM,
        LabeledBlock(
          label: copy.text(CopyKey.trendSource),
          value: trend.source,
        ),
      ],
    );
  }
}
