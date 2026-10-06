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
  const ConversationRef wechat = ConversationRef(
    packageName: 'com.tencent.mm',
    title: '张三',
  );
  const ConversationRef qq = ConversationRef(
    packageName: 'com.tencent.mobileqq',
    title: '李四',
  );
  const ConversationRef unnamed = ConversationRef(
    packageName: 'com.tencent.mm',
  );
  const ConversationRef stranger = ConversationRef(
    packageName: 'com.example.unknown',
  );

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
    candidates: <Candidate>[Candidate(text: text, reason: '.', tradeoff: '.')],
    rankingStatus: RankingStatus.ranked,
  );

  Advice adviceWithCandidates(List<String> texts) => Advice(
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
      for (final String text in texts)
        Candidate(text: text, reason: '.', tradeoff: '.'),
    ],
    rankingStatus: RankingStatus.ranked,
  );

  PanelFrame frame({
    required ConversationRef analysed,
    ConversationRef? live,
    Advice? advice,
  }) => PanelFrame(
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
        reason:
            'ADR-0002 decision 1: a raw package name is never shown. The '
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
        reason:
            'the fallback for an unknown app is the neutral label, never '
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
      expect(
        find.byType(CandidateCard),
        findsOneWidget,
        reason:
            'the drafts are still there: an unnamed thread is not an '
            'empty panel',
      );
      expect(
        find.text('填入'),
        findsNothing,
        reason:
            'a fill writes into a specific thread, and this one is not '
            'named — macOS gates on the same thing',
      );
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
      final PanelFrame before = frame(
        analysed: wechat,
        live: wechat,
        advice: adviceWith('好'),
      );
      await pumpPanel(tester, before);
      expect(find.text('填入'), findsOneWidget);

      // The main window notices the user is somewhere else and sends a frame.
      // Nothing else changes: same analysis, same drafts.
      await pumpPanel(
        tester,
        frame(analysed: wechat, live: qq, advice: adviceWith('好')),
      );

      expect(find.text('浏览中 · 只读'), findsOneWidget);
      expect(
        find.text('填入'),
        findsNothing,
        reason:
            'ADR-0002 decision 3: read-only revokes fill. Windows used to '
            'disable copy and reason as well, and that is the divergence this '
            'corrects',
      );
      expect(
        find.text('复制'),
        findsOneWidget,
        reason: 'the drafts are still useful',
      );
      expect(find.text('详情'), findsOneWidget);
      expect(find.byType(CandidateCard), findsOneWidget);
      expect(
        find.text(AppCopy.zh.text(CopyKey.panelReadOnlyBanner)),
        findsOneWidget,
        reason: 'a silently missing button is not an explanation',
      );
    });

    testWidgets('reanalyse becomes analyse-current', (
      WidgetTester tester,
    ) async {
      await pumpPanel(
        tester,
        frame(analysed: wechat, live: qq, advice: adviceWith('好')),
      );

      expect(find.text('重新分析'), findsNothing);
      expect(
        find.text('分析当前会话'),
        findsOneWidget,
        reason:
            'ADR-0002 decision 3: the old 「重新分析」 reused the snapshot '
            'on the panel, which while read-only belongs to another '
            'conversation, so tapping it silently did nothing',
      );
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
      expect(
        channel.sent.single.candidateIndex,
        0,
        reason: 'which draft matters: the panel is not allowed to guess',
      );
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
        expect(
          kinds,
          contains(action.name),
          reason:
              '${action.name} is allowed by derivePanel but has no '
              'command kind, so the panel could be told to offer something '
              'it cannot ask for',
        );
      }
    });
  });

  group('only transient state lives in the panel', () {
    testWidgets('multiple candidates scroll inside the fixed overlay height', (
      WidgetTester tester,
    ) async {
      await pumpPanel(
        tester,
        frame(
          analysed: wechat,
          live: wechat,
          advice: adviceWithCandidates(<String>['第一条', '第二条', '第三条', '第四条']),
        ),
        panelSize: const Size(300, 380),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('第一条'), findsNWidgets(2));

      await tester.drag(
        find.byKey(const Key('panel-scroll')),
        const Offset(0, -1000),
      );
      await tester.pumpAndSettle();

      expect(find.text('第四条').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the drag landing is the panel\'s own', (
      WidgetTester tester,
    ) async {
      await pumpPanel(
        tester,
        frame(analysed: wechat, live: wechat, advice: adviceWith('好')),
      );

      expect(
        _landing(tester),
        Matrix4.identity(),
        reason: 'the panel starts where the window put it',
      );

      // ADR-0012's panel is frameless, so the header is the drag handle.
      await tester.drag(find.text('喵头军师'), const Offset(40, 25));
      await tester.pumpAndSettle();

      expect(
        _landing(tester),
        Matrix4.translationValues(40, 25, 0),
        reason:
            'the user dragged the panel, and where it landed is the '
            'panel\'s own to remember',
      );
    });

    testWidgets('the collapsed ball starts native window dragging', (
      WidgetTester tester,
    ) async {
      var dragStarts = 0;
      await pumpPanel(
        tester,
        frame(analysed: wechat, live: wechat, advice: adviceWith('好')),
        initialExpanded: false,
        onDragStart: () => dragStarts += 1,
      );

      await tester.drag(
        find.byKey(const Key('panel-ball')),
        const Offset(40, 25),
      );
      await tester.pumpAndSettle();

      expect(dragStarts, 1);
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
      expect(
        find.byType(CandidateCard),
        findsNothing,
        reason: 'collapsed hides the body',
      );

      // The main window sends a new analysis. The panel must show *it* — which
      // is what fails if the advice is ever cached in the panel's own state —
      // while staying collapsed, because that is the panel's business.
      await pumpPanel(
        tester,
        frame(analysed: wechat, live: wechat, advice: adviceWith('新的一句')),
      );

      expect(
        find.byType(CandidateCard),
        findsNothing,
        reason:
            'still collapsed: transient state is the panel\'s own and a '
            'new frame is not a reason to lose it',
      );

      await tester.tap(find.byKey(const Key('panel-ball')));
      await tester.pumpAndSettle();
      expect(
        find.text('新的一句'),
        findsNWidgets(2),
        reason:
            'the panel renders the frame it was handed, not the one it '
            'was handed first',
      );
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
        reason:
            'the panel holds no content: everything it shows comes from the '
            'frame, and a field here would be a second source of truth',
      );
    });

    test('the panel asks for nothing', () {
      final String source = _sourceOf('panel/panel_page.dart');
      expect(
        RegExp(
          r'Session|CapabilitySet|capabilityRegistry|SharedMaterial|ModelTransport',
        ).allMatches(_stripComments(source)).toList(),
        isEmpty,
        reason:
            'the panel cannot ask which conversation is in front: that is '
            'the main window\'s to answer, and a second source of truth beside '
            'it is the drift ADR-0002 decision 2 exists to prevent',
      );
    });
  });

  group('a capture shows what it read', () {
    testWidgets('the transcript takes the empty state\'s place', (
      WidgetTester tester,
    ) async {
      // The first device run read 48 lines off a Feishu screen and the panel
      // showed the caveat about the sides and nothing else, which is what a
      // capture that found nothing looks like. ADR-0018.
      await pumpPanel(
        tester,
        PanelFrame(
          analysed: wechat,
          live: wechat,
          note: PanelNote(AppCopy.zh.text(CopyKey.panelNoteSidesGuessed)),
          transcript: const <PanelLine>[
            PanelLine(speaker: Speaker.me, text: '在吗'),
            PanelLine(speaker: Speaker.other, text: '在的'),
          ],
          appNames: appNames,
        ),
      );

      expect(find.text(AppCopy.zh.text(CopyKey.panelTranscriptLabel)), findsOneWidget);
      expect(find.text('我：在吗'), findsOneWidget);
      expect(find.text('对方：在的'), findsOneWidget);
      expect(
        find.text(AppCopy.zh.text(CopyKey.panelEmpty)),
        findsNothing,
        reason:
            'telling the user to read the conversation first, on a panel that '
            'is holding what it just read, is the sentence that made the '
            'capture look broken',
      );
    });

    testWidgets('a line nobody claimed is neither side', (
      WidgetTester tester,
    ) async {
      await pumpPanel(
        tester,
        PanelFrame(
          analysed: wechat,
          live: wechat,
          transcript: const <PanelLine>[
            PanelLine(speaker: Speaker.unknown, text: '嗯'),
          ],
          appNames: appNames,
        ),
      );

      expect(find.text('未定：嗯'), findsOneWidget);
    });

    testWidgets('no transcript keeps the empty state', (
      WidgetTester tester,
    ) async {
      await pumpPanel(tester, frame(analysed: wechat, live: wechat));

      expect(find.text(AppCopy.zh.text(CopyKey.panelEmpty)), findsOneWidget);
      expect(
        find.text(AppCopy.zh.text(CopyKey.panelTranscriptLabel)),
        findsNothing,
      );
    });
  });

  group('a verdict with no drafts', () {
    testWidgets('the batch stays on the panel', (WidgetTester tester) async {
      // ADR-0024. `RankingStatus.notNeeded` is the domain saying 「本轮建议不
      // 回复」 on purpose, and the panel used to answer it with a blank body: an
      // advice is not null, so the transcript's branch was skipped, and there
      // were no drafts to draw either — leaving the note and nothing else,
      // which is what made 「重新分析」 look like it had done nothing at all.
      await pumpPanel(
        tester,
        PanelFrame(
          analysed: wechat,
          live: wechat,
          advice: adviceWithCandidates(const <String>[]),
          note: PanelNote(AppCopy.zh.text(CopyKey.panelNoteReviewed)),
          transcript: const <PanelLine>[
            PanelLine(speaker: Speaker.me, text: '在吗'),
            PanelLine(speaker: Speaker.other, text: '在的'),
          ],
          appNames: appNames,
        ),
      );

      expect(
        find.text(AppCopy.zh.text(CopyKey.panelTranscriptLabel)),
        findsOneWidget,
      );
      expect(find.text('我：在吗'), findsOneWidget);
      expect(find.text('对方：在的'), findsOneWidget);
      expect(
        find.text(AppCopy.zh.text(CopyKey.panelEmpty)),
        findsNothing,
        reason:
            'a batch the user just confirmed is the one thing on the panel that '
            'is theirs; an analysis that produced no drafts is not a reason to '
            'take it away',
      );
    });
  });

  group('a batch is reviewed before it is analysed', () {
    const List<PanelLine> batch = <PanelLine>[
      PanelLine(speaker: Speaker.me, text: '在吗'),
      PanelLine(speaker: Speaker.other, text: '在的'),
    ];

    PanelFrame reviewing({List<PanelLine> lines = batch}) => PanelFrame(
      analysed: wechat,
      live: wechat,
      note: PanelNote(AppCopy.zh.text(CopyKey.panelNoteSidesGuessed)),
      transcript: lines,
      reviewing: true,
      appNames: appNames,
    );

    testWidgets('the form takes the body, with the batch in it', (
      WidgetTester tester,
    ) async {
      // The report behind ADR-0022: a whole-frame capture landed on the panel as
      // read-only text under a note asking the user to check the sides, with no
      // way to check them and no way past the gate.
      //
      // Sized to the Android overlay on purpose — the form is the one thing the
      // panel has to fit that a Row of buttons did not, and an unbounded test
      // surface would hide an overflow that ships.
      await pumpPanel(tester, reviewing(), panelSize: const Size(300, 380));

      expect(
        find.text(AppCopy.zh.text(CopyKey.panelReviewTitle)),
        findsOneWidget,
      );
      expect(find.text('在吗'), findsOneWidget);
      expect(find.text('在的'), findsOneWidget);
      expect(
        find.text(AppCopy.zh.text(CopyKey.panelTranscriptLabel)),
        findsNothing,
        reason:
            'the read-only reading of the same batch, behind an editable one, '
            'is the panel talking over itself',
      );
      expect(
        find.text(AppCopy.zh.text(CopyKey.panelNoteSidesGuessed)),
        findsOneWidget,
        reason:
            'the caveat stays: it is the sentence that says what the user is '
            'being asked to check',
      );
    });

    testWidgets('each row starts from the side the geometry guessed', (
      WidgetTester tester,
    ) async {
      // ADR-0019's guess is a starting point, not a question the user starts
      // from scratch: most whole-frame reads are right about most lines.
      await pumpPanel(tester, reviewing());

      expect(
        tester
            .widget<SegmentedButton<Speaker>>(
              find.byKey(const ValueKey<String>('panel-review-speaker-0')),
            )
            .selected,
        <Speaker>{Speaker.me},
      );
      expect(
        tester
            .widget<SegmentedButton<Speaker>>(
              find.byKey(const ValueKey<String>('panel-review-speaker-1')),
            )
            .selected,
        <Speaker>{Speaker.other},
      );
    });

    testWidgets('the side has a third answer, which is no answer', (
      WidgetTester tester,
    ) async {
      // A toggle would force a choice between two sides, and ADR-0015 makes
      // admitting there is no author better than inventing one.
      await pumpPanel(tester, reviewing());

      final Finder third = find.descendant(
        of: find.byKey(const ValueKey<String>('panel-review-speaker-0')),
        matching: find.text(AppCopy.zh.text(CopyKey.panelSpeakerUnknown)),
      );
      expect(third, findsOneWidget);

      await tester.tap(third);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<SegmentedButton<Speaker>>(
              find.byKey(const ValueKey<String>('panel-review-speaker-0')),
            )
            .selected,
        <Speaker>{Speaker.unknown},
      );
    });

    testWidgets('the bottom row offers confirm and cancel, not a reanalyse', (
      WidgetTester tester,
    ) async {
      final InMemoryPanelChannel channel = await pumpPanel(tester, reviewing());

      expect(find.byKey(const Key('panel-review-confirm')), findsOneWidget);
      expect(find.byKey(const Key('panel-review-cancel')), findsOneWidget);
      expect(
        find.byKey(const Key('panel-recognise-once')),
        findsOneWidget,
        reason:
            're-photographing is the answer to a capture that read badly, and '
            'it is the same button rather than a second one beside it',
      );
      expect(
        find.text(AppCopy.zh.text(CopyKey.panelActionReanalyse)),
        findsNothing,
        reason:
            'ADR-0022 decision 10: the gate refuses an unconfirmed batch every '
            'time, and a button that cannot succeed is a button the user will '
            'press',
      );
      expect(channel.sent, isEmpty);
    });

    testWidgets('confirm sends the batch as the user left it', (
      WidgetTester tester,
    ) async {
      final InMemoryPanelChannel channel = await pumpPanel(tester, reviewing());

      // Both halves of what the form is for: the side was guessed wrong, and a
      // character came back wrong.
      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey<String>('panel-review-speaker-1')),
          matching: find.text(AppCopy.zh.text(CopyKey.panelSpeakerMe)),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey<String>('panel-review-text-1')),
        '在的，刚看到',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('panel-review-confirm')));
      await tester.pumpAndSettle();

      expect(channel.sent.last.kind, PanelCommandKind.confirmTranscript);
      expect(
        channel.sent.last.lines?.map(
          (PanelLine line) => '${line.speaker.name}:${line.text}',
        ),
        <String>['me:在吗', 'me:在的，刚看到'],
      );
    });

    testWidgets('a line that is not there can be deleted', (
      WidgetTester tester,
    ) async {
      final InMemoryPanelChannel channel = await pumpPanel(tester, reviewing());

      await tester.tap(
        find.byKey(const ValueKey<String>('panel-review-delete-1')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('panel-review-confirm')));
      await tester.pumpAndSettle();

      expect(
        channel.sent.last.lines?.map((PanelLine line) => line.text),
        <String>['在吗'],
      );
    });

    testWidgets('a bubble split in two can be folded back into one', (
      WidgetTester tester,
    ) async {
      final InMemoryPanelChannel channel = await pumpPanel(tester, reviewing());

      await tester.tap(
        find.byKey(const ValueKey<String>('panel-review-merge-1')),
      );
      await tester.pumpAndSettle();

      expect(find.text('在吗 在的'), findsOneWidget);
      await tester.tap(find.byKey(const Key('panel-review-confirm')));
      await tester.pumpAndSettle();
      expect(
        channel.sent.last.lines?.map(
          (PanelLine line) => '${line.speaker.name}:${line.text}',
        ),
        <String>['me:在吗 在的'],
        reason:
            'the upper line keeps the speaker: a split that was not a split is '
            'one message, and the user is folding the two halves back together',
      );
    });

    testWidgets('the first line has nothing above it to fold into', (
      WidgetTester tester,
    ) async {
      await pumpPanel(tester, reviewing());

      expect(
        tester
            .widget<IconButton>(
              find.byKey(const ValueKey<String>('panel-review-merge-0')),
            )
            .onPressed,
        isNull,
      );
    });

    testWidgets('emptying every line says so and disables confirm', (
      WidgetTester tester,
    ) async {
      await pumpPanel(tester, reviewing());

      await tester.enterText(
        find.byKey(const ValueKey<String>('panel-review-text-0')),
        '',
      );
      await tester.enterText(
        find.byKey(const ValueKey<String>('panel-review-text-1')),
        '   ',
      );
      await tester.pumpAndSettle();

      expect(
        find.text(AppCopy.zh.text(CopyKey.panelReviewNothingLeft)),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('panel-review-confirm')))
            .onPressed,
        isNull,
        reason:
            'the command would be an empty batch, which the runtime refuses '
            'anyway — disabling it here is the first reading of the same rule',
      );
    });

    testWidgets('cancel asks to drop the batch rather than confirm it', (
      WidgetTester tester,
    ) async {
      final InMemoryPanelChannel channel = await pumpPanel(tester, reviewing());

      await tester.tap(find.byKey(const Key('panel-review-cancel')));
      await tester.pumpAndSettle();

      expect(channel.sent.last.kind, PanelCommandKind.cancelReview);
      expect(channel.sent.last.lines, isNull);
    });

    testWidgets('the form wins over a draft already on screen', (
      WidgetTester tester,
    ) async {
      // The review is a state rather than a section: the user is being asked a
      // question, and a candidate card behind it is the panel talking over
      // itself.
      await pumpPanel(
        tester,
        PanelFrame(
          analysed: wechat,
          live: wechat,
          advice: adviceWith('好呀'),
          transcript: batch,
          reviewing: true,
          appNames: appNames,
        ),
      );

      expect(find.byType(CandidateCard), findsNothing);
      expect(
        find.text(AppCopy.zh.text(CopyKey.panelReviewTitle)),
        findsOneWidget,
      );
    });

    testWidgets('the host is asked for a taller window while the form is up', (
      WidgetTester tester,
    ) async {
      // The panel cannot resize itself and does not try: the window is the
      // host's, and on Android it is the host's own 380dp overlay with no
      // `adjustResize`, which puts the keyboard over the form.
      final List<bool> asked = <bool>[];
      Future<void> record(bool reviewing) async => asked.add(reviewing);

      await pumpPanel(
        tester,
        frame(analysed: wechat, live: wechat),
        onReviewChanged: record,
      );
      expect(asked, isEmpty);

      // A batch lands, and with it the review.
      await pumpPanel(tester, reviewing(), onReviewChanged: record);
      expect(asked, <bool>[true]);

      // And the room is given back when the state ends.
      await pumpPanel(
        tester,
        frame(analysed: wechat, live: wechat),
        onReviewChanged: record,
      );
      expect(asked, <bool>[true, false]);
    });

    testWidgets('a panel that starts with the form up asks for the room too', (
      WidgetTester tester,
    ) async {
      // The window was recreated while a review was outstanding. No frame change
      // will come to say so, so the ask has to happen on the first build.
      final List<bool> asked = <bool>[];
      await pumpPanel(
        tester,
        reviewing(),
        onReviewChanged: (bool reviewing) async => asked.add(reviewing),
      );

      expect(asked, <bool>[true]);
    });

    testWidgets('the standing 核对 is how the user gets back in', (
      WidgetTester tester,
    ) async {
      // ADR-0022 decision 12: a wrong character noticed after the fact should
      // not cost a second photograph of the screen.
      final InMemoryPanelChannel channel = await pumpPanel(
        tester,
        PanelFrame(
          analysed: wechat,
          live: wechat,
          transcript: batch,
          appNames: appNames,
        ),
      );

      final Finder open = find.byKey(const Key('panel-review-open'));
      expect(open, findsOneWidget);
      await tester.tap(open);
      await tester.pumpAndSettle();

      expect(channel.sent.last.kind, PanelCommandKind.openReview);
    });

    testWidgets('a refusal carries the way into the form', (
      WidgetTester tester,
    ) async {
      // ADR-0022 decision 13. 「当前对话全部待核对」 with nothing to act on is the
      // sentence the report was stuck on; the sentence alone tells the user what
      // is wrong and leaves them to find the surface that fixes it.
      final InMemoryPanelChannel channel = await pumpPanel(
        tester,
        PanelFrame(
          analysed: wechat,
          live: wechat,
          note: const PanelNote(
            '当前对话全部待核对，请先确认说话人和原文，再生成回复',
            remedy: EnterReview(),
          ),
          transcript: batch,
          appNames: appNames,
        ),
      );

      final Finder remedy = find.byKey(const Key('panel-note-remedy'));
      expect(remedy, findsOneWidget);
      expect(
        find.text(AppCopy.zh.text(CopyKey.panelActionGoReview)),
        findsOneWidget,
      );
      await tester.tap(remedy);
      await tester.pumpAndSettle();

      expect(channel.sent.last.kind, PanelCommandKind.openReview);
    });

    testWidgets('nothing read yet keeps the standing button away', (
      WidgetTester tester,
    ) async {
      await pumpPanel(tester, frame(analysed: wechat, live: wechat));

      expect(find.byKey(const Key('panel-review-open')), findsNothing);
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

    expect(
      find.byType(PanelPage),
      findsNWidgets(2),
      reason:
          'one showing the analysed conversation, one showing the same '
          'analysis after the user has moved on',
    );
    expect(find.text('浏览中 · 只读'), findsOneWidget);
    expect(find.text('正在看'), findsOneWidget);
  });
}

/// Where the panel is sitting, read out of the transform it is drawn under.
Matrix4 _landing(WidgetTester tester) =>
    tester.widget<Transform>(find.byKey(const Key('panel-landing'))).transform;

/// The panel in the shell a test drives it from.
///
/// Split out from [pumpPanel] so a test can pump the *same* position twice and
/// let `didUpdateWidget` run, which is the path a real republish takes — the
/// review is entered by a frame change, not by the panel deciding anything.
Widget panelIn(
  PanelFrame frame,
  InMemoryPanelChannel channel, {
  AppCopy copy = AppCopy.zh,
  bool initialExpanded = true,
  VoidCallback? onDragStart,
  Future<void> Function(bool reviewing)? onReviewChanged,
  Size? panelSize,
}) => CopyScope(
  copy: copy,
  child: MaterialApp(
    theme: buildTheme(),
    home: Scaffold(
      body: SingleChildScrollView(
        child: SizedBox(
          width: panelSize?.width,
          height: panelSize?.height,
          child: PanelPage(
            frame: frame,
            onCommand: channel.send,
            initialExpanded: initialExpanded,
            onDragStart: onDragStart,
            onReviewChanged: onReviewChanged,
          ),
        ),
      ),
    ),
  ),
);

Future<InMemoryPanelChannel> pumpPanel(
  WidgetTester tester,
  PanelFrame frame, {
  AppCopy copy = AppCopy.zh,
  bool initialExpanded = true,
  VoidCallback? onDragStart,
  Future<void> Function(bool reviewing)? onReviewChanged,
  Size? panelSize,
  InMemoryPanelChannel? channel,
}) async {
  final InMemoryPanelChannel target = channel ?? InMemoryPanelChannel();
  if (channel == null) {
    addTearDown(target.dispose);
  }

  await tester.pumpWidget(
    panelIn(
      frame,
      target,
      copy: copy,
      initialExpanded: initialExpanded,
      onDragStart: onDragStart,
      onReviewChanged: onReviewChanged,
      panelSize: panelSize,
    ),
  );
  await tester.pumpAndSettle();
  return target;
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
