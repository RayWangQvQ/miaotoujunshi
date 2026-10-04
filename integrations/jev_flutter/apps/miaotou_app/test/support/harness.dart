import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miaotou_app/src/app.dart';
import 'package:miaotou_app/src/design/copy.dart';
import 'package:miaotou_app/src/session.dart';
import 'package:miaotou_app/src/shell/content.dart';
import 'package:miaotou_capabilities/miaotou_capabilities.dart';
import 'package:miaotou_capabilities/testing.dart';
import 'package:miaotou_domain/miaotou_domain.dart';

/// Everything a test needs to drive the real application, and the two numbers
/// the acceptance criteria are stated in.
///
/// The point is that these tests run `MiaotouApp` — the same widget `main.dart`
/// starts — rather than a page in isolation. A page in isolation cannot prove
/// that the shell routes to it, that the window can hide it, or that the session
/// outlives it, and those are three of #11's five criteria.
final class AppHarness {
  AppHarness({CapabilitySet? capabilities})
      : capabilities = capabilities ?? InMemoryCapabilities().toSet();

  final CapabilitySet capabilities;

  /// Ends are counted here rather than assumed: "the capabilities were torn
  /// down" is otherwise invisible, since nothing in the tree can observe it.
  int _endCount = 0;

  late final Session session =
      Session(capabilities: capabilities, onEnd: _recordEnd);

  late final MainWindowController window = MainWindowController();

  /// How many times the session actually ended something.
  int get endCount => _endCount;

  Future<void> _recordEnd() async {
    _endCount++;
  }
}

/// Pumps the whole application at a given size and settles it.
Future<void> pumpApplication(
  WidgetTester tester,
  AppHarness harness, {
  AppCopy? copy,
  ShellContent? content,
  Size size = const Size(1200, 2400),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MiaotouApp(
      session: harness.session,
      window: harness.window,
      copy: copy ?? AppCopy.zh,
      content: content ?? ShellContent.empty,
    ),
  );
  await tester.pumpAndSettle();
}

/// A content whose every string is the marker.
///
/// Paired with [AppCopy.sentinel], it makes a hard-coded string the only string
/// on the page that is not the marker — which is how the audit sees it.
ShellContent sentinelContent(String marker) => ShellContent(
      advice: Advice(
        support: marker,
        facts: <String>[marker],
        hypotheses: <String>[marker],
        unknowns: <String>[marker],
        intent: marker,
        intentConfidence: 0.5,
        strategy: marker,
        recommendation: marker,
        nextStep: marker,
        stopCondition: marker,
        question: marker,
        candidates: <Candidate>[
          Candidate(
            text: marker,
            reason: marker,
            tradeoff: marker,
            weight: 40,
          ),
        ],
        rankingStatus: RankingStatus.ranked,
      ),
      trend: Trend(
        title: marker,
        candles: <Candle>[
          Candle(date: marker, open: 0, high: 2, low: -1, close: 1),
          Candle(date: marker, open: 1, high: 3, low: 0, close: -1),
        ],
        source: marker,
        metric: messageBalanceMetric,
      ),
      trendRules: TrendRules(
        columns: <String>[marker],
        senders: <String>[senderMe, senderOther],
        timestampFormat: marker,
        maxBytes: 1024,
        maxMessages: 100,
        maxEventChars: 40,
        metric: messageBalanceMetric,
        metricNote: marker,
      ),
      profile: Profile(
        id: marker,
        label: marker,
        stage: marker,
        goal: marker,
        background: marker,
        myMbti: marker,
        theirMbti: marker,
        myScore: marker,
        theirScore: marker,
        notes: marker,
      ),
    );

/// Every [Text] currently in the tree, with the string it is showing.
List<String> renderedTexts(WidgetTester tester) => <String>[
      for (final Text text in tester.widgetList<Text>(find.byType(Text)))
        text.data ?? '',
    ];
