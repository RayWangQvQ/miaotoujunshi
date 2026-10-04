import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miaotou_app/src/design/copy.dart';
import 'package:miaotou_app/src/design/theme.dart';
import 'package:miaotou_app/src/panel/panel_page.dart';
import 'package:miaotou_app/src/panel/protocol.dart';
import 'package:miaotou_app/src/shell/destination.dart';
import 'package:miaotou_app/src/widgets/candidate_card.dart';
import 'package:miaotou_capabilities/miaotou_capabilities.dart';
import 'package:miaotou_domain/miaotou_domain.dart';

import 'support/harness.dart';

/// The floating panel: what it shows, what it must never show, and the one thing
/// it loses when the user looks away (ADR-0002).
///
/// The header rules are ADR-0002 decision 1 — a second line naming the analysed
/// conversation, and **never a raw package name**. That last clause has no
/// Android test to copy because Android enforces it by construction
/// (`ChatApps.displayName` returning null), so it is enforced the same way here:
/// [ConversationLabel] has no package field, and the assertions below check both
/// halves — that the label is right, and that the package is nowhere on screen.
void main() {
  const ConversationRef wechat =
      ConversationRef(packageName: 'com.tencent.mm', title: '张三');
  const ConversationRef qq =
      ConversationRef(packageName: 'com.tencent.mobileqq', title: '李四');
  const ConversationRef unnamed =
      ConversationRef(packageName: 'com.tencent.mm');
  const ConversationRef stranger =
      ConversationRef(packageName: 'com.example.unknown');

  const Map<String, String> appNames = <String, String>{
    'com.tencent.mm': '微信',
    'com.tencent.mobileqq': 'QQ',
  };

  Advice adviceWith(String text) => Advice(
        support: '.',
        facts: const <String>['x'],
        hypotheses: const <String>[],
        unknowns: const <String>[],
        intent: null,
        intentConfidence: null,
        strategy: '.',
        recommendation: '.',
        nextStep: '.',
        stopCondition: '.',
        question: '',
        candidates: <Candidate>[
          Candidate(text: text, reason: '.', tradeoff: '.'),
        ],
        rankingStatus: RankingStatus.ranked,
      );

  PanelFrame frame({
    required ConversationRef analysed,
    ConversationRef? live,
    Advice? advice,
  }) =>
      PanelFrame(
        analysed: analysed,
        live: live,
        advice: advice,
        appNames: appNames,
      );

  group('the header names the analysed conversation', () {
    testWidgets('both halves known', (WidgetTester tester) async {
      await pumpPanel(
        tester,
        frame(analysed: wechat, live: wechat, advice: adviceWith('好')),
      );

      expect(find.text('微信 · 张三'), findsOneWidget);
      expect(find.text('正在看'), findsOneWidget);
    });

    testWidgets('and never shows the package it was told about', (
      WidgetTester tester,
    ) async {
      await pumpPanel(
        tester,
        frame(analysed: wechat, live: wechat, advice: adviceWith('好')),
      );

      final List<String> onScreen = renderedTexts(tester);
      expect(
        onScreen.where((String text) => text.contains('com.tencent.mm')),
        isEmpty,
        reason: 'ADR-0002 decision 1: a raw package name is never shown. The '
            'frame does carry one — it has to, to tell two conversations apart '
            '— which is exactly why the label is built before the header sees '
            'anything: $onScreen',
      );
    });

    testWidgets('an app with no name and a conversation with no title', (
      WidgetTester tester,
    ) async {
      await pumpPanel(
        tester,
        frame(analysed: stranger, live: stranger, advice: adviceWith('好')),
      );

      // Android's own expectation: 「未识别会话」, not `com.example.unknown`.
      expect(find.text('未识别会话'), findsOneWidget);
      final List<String> onScreen = renderedTexts(tester);
      expect(
        onScreen.where((String text) => text.contains('com.example.unknown')),
        isEmpty,
        reason: 'the fallback for an unknown app is the neutral label, never '
            'the package: $onScreen',
      );
    });

    testWidgets('an unnamed thread is a state, not an error', (
      WidgetTester tester,
    ) async {
      // ADR-0002: a missing title is a legitimate state. If this threw, the
      // panel would be unusable against any app whose title OCR cannot read.
      await pumpPanel(
        tester,
        frame(analysed: unnamed, live: unnamed, advice: adviceWith('好')),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('微信 · 未识别会话'), findsOneWidget);
      expect(find.byType(CandidateCard), findsOneWidget,
          reason: 'the drafts are still there: an unnamed thread is not an '
              'empty panel');
      expect(find.text('填入'), findsNothing,
          reason: 'a fill writes into a specific thread, and this one is not '
              'named — macOS gates on the same thing');
    });
  });

  group('the read-only flip', () {
    testWidgets('while the analysed conversation is the one in front', (
      WidgetTester tester,
    ) async {
      await pumpPanel(
        tester,
        frame(analysed: wechat, live: wechat, advice: adviceWith('好')),
      );

      expect(find.text('填入'), findsOneWidget);
      expect(find.text('复制'), findsOneWidget);
      expect(find.text('详情'), findsOneWidget);
      expect(find.text('重新分析'), findsOneWidget);
    });

    testWidgets('the user moved on: fill goes, copy and detail stay', (
      WidgetTester tester,
    ) async {
      final PanelFrame before =
          frame(analysed: wechat, live: wechat, advice: adviceWith('好'));
      await pumpPanel(tester, before);
      expect(find.text('填入'), findsOneWidget);

      // The main window notices the user is somewhere else and sends a frame.
      // Nothing else changes: same analysis, same drafts.
      await pumpPanel(
        tester,
        frame(analysed: wechat, live: qq, advice: adviceWith('好')),
      );

      expect(find.text('浏览中 · 只读'), findsOneWidget);
      expect(find.text('填入'), findsNothing,
          reason: 'ADR-0002 decision 3: read-only revokes fill. Windows used to '
              'disable copy and reason as well, and that is the divergence this '
              'corrects');
      expect(find.text('复制'), findsOneWidget,
          reason: 'the drafts are still useful');
      expect(find.text('详情'), findsOneWidget);
      expect(find.byType(CandidateCard), findsOneWidget);
      expect(find.text(AppCopy.zh.text(CopyKey.panelReadOnlyBanner)),
          findsOneWidget,
          reason: 'a silently missing button is not an explanation');
    });

    testWidgets('reanalyse becomes analyse-current', (WidgetTester tester) async {
      await pumpPanel(
        tester,
        frame(analysed: wechat, live: qq, advice: adviceWith('好')),
      );

      expect(find.text('重新分析'), findsNothing);
      expect(find.text('分析当前会话'), findsOneWidget,
          reason: 'ADR-0002 decision 3: the old 「重新分析」 reused the snapshot '
              'on the panel, which while read-only belongs to another '
              'conversation, so tapping it silently did nothing');
    });
  });

  group('commands going up', () {
    testWidgets('a tap on copy is a command, not a clipboard', (
      WidgetTester tester,
    ) async {
      final InMemoryPanelChannel channel = await pumpPanel(
        tester,
        frame(analysed: wechat, live: wechat, advice: adviceWith('好')),
      );

      await tester.tap(find.text('复制'));
      await tester.pumpAndSettle();

      expect(channel.sent.single.kind, PanelCommandKind.copy);
      expect(channel.sent.single.candidateIndex, 0,
          reason: 'which draft matters: the panel is not allowed to guess');
    });

    testWidgets('read-only still lets the user ask for the details', (
      WidgetTester tester,
    ) async {
      final InMemoryPanelChannel channel = await pumpPanel(
        tester,
        frame(analysed: wechat, live: qq, advice: adviceWith('好')),
      );

      await tester.tap(find.text('详情'));
      await tester.pumpAndSettle();

      expect(channel.sent.single.kind, PanelCommandKind.details);
    });

    testWidgets('the bottom button asks for the conversation in front', (
      WidgetTester tester,
    ) async {
      final InMemoryPanelChannel channel = await pumpPanel(
        tester,
        frame(analysed: wechat, live: qq, advice: adviceWith('好')),
      );

      await tester.tap(find.text('分析当前会话'));
      await tester.pumpAndSettle();

      expect(channel.sent.single.kind, PanelCommandKind.analyseCurrent);
    });

    test('every action the domain allows is a command the panel can send', () {
      // The two enums are the same vocabulary twice — one for what is allowed,
      // one for what goes over the wire — and that is the kind of duplication
      // that drifts. This is what stops it drifting.
      final Set<String> kinds = <String>{
        for (final PanelCommandKind kind in PanelCommandKind.values) kind.name,
      };
      for (final PanelAction action in PanelAction.values) {
        expect(kinds, contains(action.name),
            reason: '${action.name} is allowed by derivePanel but has no '
                'command kind, so the panel could be told to offer something '
                'it cannot ask for');
      }
    });
  });

  group('only transient state lives in the panel', () {
    testWidgets('the drag landing is the panel\'s own', (
      WidgetTester tester,
    ) async {
      await pumpPanel(
        tester,
        frame(analysed: wechat, live: wechat, advice: adviceWith('好')),
      );

      expect(_landing(tester), Matrix4.identity(),
          reason: 'the panel starts where the window put it');

      // ADR-0012's panel is frameless, so the header is the drag handle.
      await tester.drag(find.text('喵头军师'), const Offset(40, 25));
      await tester.pumpAndSettle();

      expect(_landing(tester), Matrix4.translationValues(40, 25, 0),
          reason: 'the user dragged the panel, and where it landed is the '
              'panel\'s own to remember');
    });

    testWidgets('expanded or collapsed, and new content does not collapse it', (
      WidgetTester tester,
    ) async {
      await pumpPanel(
        tester,
        frame(analysed: wechat, live: wechat, advice: adviceWith('好')),
      );
      expect(find.byType(CandidateCard), findsOneWidget);

      await tester.tap(find.byIcon(Icons.expand_less));
      await tester.pumpAndSettle();
      expect(find.byType(CandidateCard), findsNothing,
          reason: 'collapsed hides the body');

      // The main window sends a new analysis. The panel must show *it* — which
      // is what fails if the advice is ever cached in the panel's own state —
      // while staying collapsed, because that is the panel's business.
      await pumpPanel(
        tester,
        frame(analysed: wechat, live: wechat, advice: adviceWith('新的一句')),
      );

      expect(find.byType(CandidateCard), findsNothing,
          reason: 'still collapsed: transient state is the panel\'s own and a '
              'new frame is not a reason to lose it');

      await tester.tap(find.byIcon(Icons.expand_more));
      await tester.pumpAndSettle();
      expect(find.text('新的一句'), findsOneWidget,
          reason: 'the panel renders the frame it was handed, not the one it '
              'was handed first');
      expect(find.text('好'), findsNothing);
    });

    test('the panel\'s state holds nothing but the surface', () {
      // Scanned rather than asserted on a widget, because "no field of type
      // Advice" is a statement about the source. A cached advice would keep
      // showing a stale analysis after the frame changed, which is the failure
      // the previous test catches behaviourally; this one names it.
      final String state = _sourceOf('panel/panel_page.dart')
          .split('class _PanelPageState extends State<PanelPage> {')
          .last;
      // Two-space indent: a field of the state class, and not a local variable
      // inside `build`, which is indented further and is where `advice` is
      // legitimately named.
      final RegExp stored = RegExp(
        r'^ {2}(?:late )?final\s+(?:Advice|Snapshot|ConversationRef|PanelFrame|Candidate|Trend|Profile)\b',
        multiLine: true,
      );
      expect(
        stored.allMatches(_stripComments(state)).toList(),
        isEmpty,
        reason: 'the panel holds no content: everything it shows comes from the '
            'frame, and a field here would be a second source of truth',
      );
    });

    test('the panel asks for nothing', () {
      final String source = _sourceOf('panel/panel_page.dart');
      expect(
        RegExp(r'Session|CapabilitySet|capabilityRegistry|SharedMaterial|ModelTransport')
            .allMatches(_stripComments(source))
            .toList(),
        isEmpty,
        reason: 'the panel cannot ask which conversation is in front: that is '
            'the main window\'s to answer, and a second source of truth beside '
            'it is the drift ADR-0002 decision 2 exists to prevent',
      );
    });
  });

  testWidgets('the gallery hosts it, so it is not dead code', (
    WidgetTester tester,
  ) async {
    final AppHarness harness = AppHarness();
    await pumpApplication(tester, harness);

    harness.window.navigate(ShellDestination.settings);
    await tester.pumpAndSettle();
    await tester.tap(find.text('组件陈列'));
    await tester.pumpAndSettle();

    expect(find.byType(PanelPage), findsNWidgets(2),
        reason: 'one showing the analysed conversation, one showing the same '
            'analysis after the user has moved on');
    expect(find.text('浏览中 · 只读'), findsOneWidget);
    expect(find.text('正在看'), findsOneWidget);
  });
}

/// Where the panel is sitting, read out of the transform it is drawn under.
Matrix4 _landing(WidgetTester tester) =>
    tester.widget<Transform>(find.byKey(const Key('panel-landing'))).transform;

Future<InMemoryPanelChannel> pumpPanel(
  WidgetTester tester,
  PanelFrame frame, {
  AppCopy copy = AppCopy.zh,
}) async {
  final InMemoryPanelChannel channel = InMemoryPanelChannel();
  addTearDown(channel.dispose);

  await tester.pumpWidget(
    CopyScope(
      copy: copy,
      child: MaterialApp(
        theme: buildTheme(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: PanelPage(frame: frame, onCommand: channel.send),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return channel;
}

String _sourceOf(String relative) {
  Directory directory = Directory.current;
  while (true) {
    final File candidate = File('${directory.path}/lib/src/$relative');
    if (candidate.existsSync()) {
      return candidate.readAsStringSync();
    }
    directory = directory.parent;
  }
}

String _stripComments(String source) => source
    .replaceAll(RegExp(r'//[^\n]*'), '')
    .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '');
