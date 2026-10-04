import 'package:flutter_test/flutter_test.dart';
import 'package:miaotou_app/src/shell/destination.dart';
import 'package:miaotou_app/src/shell/content.dart';
import 'package:miaotou_app/src/shell/gallery_page.dart';
import 'package:miaotou_app/src/shell/trend_page.dart';
import 'package:miaotou_app/src/widgets/candidate_card.dart';
import 'package:miaotou_app/src/widgets/status_badge.dart';
import 'package:miaotou_app/src/widgets/trend_chart.dart';
import 'package:miaotou_domain/miaotou_domain.dart';

import 'support/harness.dart';

/// The candidate card, the badge and the trend chart are shared, and a gallery
/// shows all three.
///
/// "Shared" is not "extracted": it means a page and the panel render the same
/// class, so a change to what amber means is one change. The gallery is the
/// other half — a component nobody can see on its own is a component nobody
/// checks, and #11 asks for it to be visible rather than merely present.
void main() {
  const String marker = '·';

  testWidgets('the gallery shows all three, and every badge tone', (
    WidgetTester tester,
  ) async {
    final AppHarness harness = AppHarness();
    await pumpApplication(tester, harness);

    harness.window.navigate(ShellDestination.settings);
    await tester.pumpAndSettle();
    await tester.tap(find.text('组件陈列'));
    await tester.pumpAndSettle();

    expect(find.byType(GalleryPage), findsOneWidget);
    expect(find.byType(CandidateCard), findsOneWidget);
    expect(find.byType(TrendChart), findsOneWidget);

    final List<StatusTone> tones = tester
        .widgetList<StatusBadge>(find.byType(StatusBadge))
        .map((StatusBadge badge) => badge.tone)
        .toList();

    expect(
      tones.toSet(),
      StatusTone.values.toSet(),
      reason: 'all four tones are in the gallery, because a tone a reader never '
          'sees next to the others is a tone whose meaning drifts',
    );
  });

  testWidgets('the pages render those same classes, not copies of them', (
    WidgetTester tester,
  ) async {
    final AppHarness harness = AppHarness();
    await pumpApplication(tester, harness, content: sentinelContent(marker));

    harness.window.navigate(ShellDestination.detail);
    await tester.pumpAndSettle();
    expect(find.byType(CandidateCard), findsOneWidget,
        reason: 'one candidate in the content, rendered by the shared card');
    expect(
      find.descendant(
        of: find.byType(CandidateCard),
        matching: find.byType(StatusBadge),
      ),
      findsNWidgets(2),
      reason: 'the rank and the weight on a candidate are both badges, so the '
          'badge the gallery shows is the badge the detail page uses; one '
          'badge means one of them stopped being shared',
    );

    harness.window.navigate(ShellDestination.trend);
    await tester.pumpAndSettle();
    expect(find.byType(TrendChart), findsOneWidget,
        reason: 'the trend page draws the same chart the gallery shows');
  });

  testWidgets('the chart is never drawn without the payload disclaimer', (
    WidgetTester tester,
  ) async {
    const String note = '这不是关系评分。';
    final Trend trend = Trend(
      title: '一天',
      candles: <Candle>[
        Candle(date: '2026-10-01', open: 0, high: 2, low: -1, close: 1),
      ],
      source: 'test',
      metric: messageBalanceMetric,
    );
    final TrendRules rules = TrendRules(
      columns: <String>['date'],
      senders: const <String>[senderMe, senderOther],
      timestampFormat: 'YYYY-MM-DD HH:MM',
      maxBytes: 1024,
      maxMessages: 10,
      maxEventChars: 40,
      metric: messageBalanceMetric,
      metricNote: note,
    );

    final AppHarness withNote = AppHarness();
    await pumpApplication(
      tester,
      withNote,
      content: ShellContent(trend: trend, trendRules: rules),
    );
    withNote.window.navigate(ShellDestination.trend);
    await tester.pumpAndSettle();

    expect(find.byType(TrendChart), findsOneWidget);
    expect(find.text(note), findsOneWidget,
        reason: 'the disclaimer is part of what the number means; #8 made it '
            'travel with the data and this is where it becomes visible');

    // Without the contract there is no chart at all, rather than a chart with a
    // blank line under it.
    final AppHarness withoutNote = AppHarness();
    await pumpApplication(
      tester,
      withoutNote,
      content: ShellContent(trend: trend),
    );
    withoutNote.window.navigate(ShellDestination.trend);
    await tester.pumpAndSettle();

    expect(find.byType(TrendPage), findsOneWidget);
    expect(find.byType(TrendChart), findsNothing,
        reason: 'a K-line with no stated metric is a picture of a score');
    expect(find.text('还没有走势数据。'), findsOneWidget);
  });
}
