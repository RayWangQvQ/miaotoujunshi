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
/// conversation — as revised by ADR-0026: an app the system cannot name shows its
/// package name rather than a placeholder, so a header is never empty while a
/// window is in front. Only NONE (no window) drops to the placeholder 「未知应用」;
/// an app that is named but a person who is not drops to 「未知人」 instead.
///
/// ADR-0028 moved the resolution to the platform and pointed the header at
/// [PanelView.header]: the analysed conversation once there is one, and the one
/// in front until then — which is what lets an application this build has no
/// adapter for be named at all.
void main() {
  const ConversationRef wechat = ConversationRef(
    packageName: 'com.tencent.mm',
    appName: '微信',
    title: '张三',
  );
  const ConversationRef qq = ConversationRef(
    packageName: 'com.tencent.mobileqq',
    appName: 'QQ',
    title: '李四',
  );
  const ConversationRef unnamed = ConversationRef(
    packageName: 'com.tencent.mm',
    appName: '微信',
  );
  const ConversationRef stranger = ConversationRef(
    packageName: 'com.example.unknown',
  );
  const ConversationRef douyin = ConversationRef(
    packageName: 'com.ss.android.ugc.aweme',
    appName: '抖音',
  );
  // A name with no package behind it: the review entered it by hand once, and
  // a later review must not ask for it again (ADR-0030 — the app is already
  // named).
  const ConversationRef namedNoPackage = ConversationRef(
    packageName: '',
    appName: '微信',
  );

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

    testWidgets('a resolved name is shown, not the package', (
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
            'a package with a resolved name shows the name, not the package. '
            'ADR-0026 falls back to the package only when no name was resolved: '
            '$onScreen',
      );
    });

    testWidgets('an app with no name and a conversation with no title', (
      WidgetTester tester,
    ) async {
      await pumpPanel(
        tester,
        frame(analysed: stranger, live: stranger, advice: adviceWith('好')),
      );

      // ADR-0026: an app with no resolved name shows its package name, not a
      // neutral placeholder. `com.example.unknown` is the label here, and the
      // missing half is the person, so the placeholder is 未知人.
      expect(find.text('com.example.unknown · 未知人'), findsOneWidget);
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
      expect(find.text('微信 · 未知人'), findsOneWidget);
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

    testWidgets('the app in front is named before there is any analysis', (
      WidgetTester tester,
    ) async {
      // ADR-0028, and the report it answers: opening the ball in Douyin read
      // 「未知应用」. The header printed the analysed conversation, and a build
      // with no adapter for an app never analyses one — no adapter means no tree
      // reading, which means no analysis, which meant never a name. The app half
      // now names the current app while the person half is still missing.
      await pumpPanel(
        tester,
        frame(analysed: ConversationRef.none, live: douyin),
      );

      expect(find.text('抖音 · 未知人'), findsOneWidget);
      expect(
        find.text(AppCopy.zh.text(CopyKey.panelStatusNotAnalysed)),
        findsOneWidget,
      );
    });

    testWidgets('with nothing in front at all the placeholder stands', (
      WidgetTester tester,
    ) async {
      // The one case ADR-0026 leaves the placeholder for: no window, no package.
      await pumpPanel(
        tester,
        frame(analysed: ConversationRef.none, live: ConversationRef.none),
      );

      expect(
        find.text(AppCopy.zh.text(CopyKey.panelLabelUnrecognised)),
        findsOneWidget,
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
      expect(find.text('第一条'), findsOneWidget);

      await tester.drag(
        find.byKey(const Key('panel-scroll')),
        const Offset(0, -1000),
      );
      await tester.pumpAndSettle();

      // The last candidate has scrolled into view. `hitTestable` rather than a
      // bare `find.text`, because an off-screen candidate is still laid out; and
      // `findsWidgets` rather than `findsOneWidget`, because how many of the
      // card are on-screen at once depends on the type scale.
      expect(find.text('第四条').hitTestable(), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the candidate draft is clamped to a body line', (
      WidgetTester tester,
    ) async {
      await pumpPanel(
        tester,
        frame(analysed: wechat, live: wechat, advice: adviceWith('好')),
      );

      // The panel clamps its type a step down (ADR-0025): `bodyLarge` — the
      // candidate draft — reads at `bodyMedium`, so a 16px headline does not
      // land on a 300dp overlay. The draft sits inside the card.
      final Text draft = tester.widget<Text>(
        find.descendant(
          of: find.byType(CandidateCard),
          matching: find.text('好'),
        ),
      );
      expect(
        draft.style?.fontSize,
        14.0,
        reason: 'no text on the panel may read larger than a body line',
      );
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
        findsOneWidget,
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
      //
      // The slice starts at the `State` class rather than at the top of the
      // file, because the widget's own parameters *are* the frame: `PanelFrame
      // frame` is the one thing the panel is handed, and everything it shows
      // comes out of it. Slicing this way is also what lets the same rule be
      // registered against a second panel module by name — see the review
      // module's test below — instead of by widening the scan to the whole
      // directory, which would be red on arrival: `protocol.dart`, `session.dart`
      // and `window_channel.dart` all carry a `PanelFrame` on purpose, because
      // that is the value the panel is handed and the value the wire carries.
      expect(
        _contentFields
            .allMatches(_stripComments(_stateClassOf('panel/panel_page.dart')))
            .toList(),
        isEmpty,
        reason:
            'the panel holds no content: everything it shows comes from the '
            'frame, and a field here would be a second source of truth',
      );
    });

    test('the panel asks for nothing', () {
      expect(
        _outsideIdentifiers
            .allMatches(_stripComments(_sourceOf('panel/panel_page.dart')))
            .toList(),
        isEmpty,
        reason:
            'the panel cannot ask which conversation is in front: that is '
            'the main window\'s to answer, and a second source of truth beside '
            'it is the drift ADR-0002 decision 2 exists to prevent',
      );
    });

    test('the review module holds nothing and asks for nothing either', () {
      // Registered by name, for the same reason the panel's own state is
      // scanned: the review's rules moved out of the widget into a module, and a
      // module in this directory that quietly grew a field holding an analysis
      // or a frame would be the second source of truth the two tests above
      // exist to prevent. A file with no `State` class is scanned whole, because
      // there is no part of it that is only a surface.
      //
      // `PanelLine` is deliberately not on the content list: the rows *are* the
      // surface, and this module remembers their signature rather than their
      // content. Adding a panel module means registering it here.
      final String source = _stripComments(
        _sourceOf('panel/review_session.dart'),
      );
      expect(
        _contentFields.allMatches(source).toList(),
        isEmpty,
        reason: 'the review decides about the batch; it does not hold it',
      );
      expect(
        _outsideIdentifiers.allMatches(source).toList(),
        isEmpty,
        reason: 'the review cannot ask which conversation is in front either',
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
        ),
      );

      expect(find.text(AppCopy.zh.text(CopyKey.panelTranscriptLabel)), findsOneWidget);
      expect(find.text('我：在吗\n对方：在的'), findsOneWidget);
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
        ),
      );

      expect(
        find.text(AppCopy.zh.text(CopyKey.panelTranscriptLabel)),
        findsOneWidget,
      );
      expect(find.text('我：在吗\n对方：在的'), findsOneWidget);
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
        );

    testWidgets('the form takes the body, with the batch as one block', (
      WidgetTester tester,
    ) async {
      // The report behind ADR-0022: a whole-frame capture landed on the panel as
      // read-only text under a note asking the user to check the sides, with no
      // way to check them and no way past the gate. ADR-0025 made the edit one
      // block of text rather than a row per line.
      //
      // Sized to the Android overlay on purpose — the form is the one thing the
      // panel has to fit that a Row of buttons did not, and an unbounded test
      // surface would hide an overflow that ships.
      await pumpPanel(tester, reviewing(), panelSize: const Size(300, 380));

      expect(
        find.text(AppCopy.zh.text(CopyKey.panelReviewTitle)),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('panel-review-block')),
        findsOneWidget,
      );
      final TextField block = tester.widget<TextField>(
        find.byKey(const Key('panel-review-block')),
      );
      expect(block.controller!.text, '我：在吗\n对方：在的');
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

    testWidgets('the block starts from the side the geometry guessed', (
      WidgetTester tester,
    ) async {
      // ADR-0019's guess is a starting point, not a question the user starts
      // from scratch: most whole-frame reads are right about most lines.
      await pumpPanel(tester, reviewing());

      final TextField block = tester.widget<TextField>(
        find.byKey(const Key('panel-review-block')),
      );
      expect(block.controller!.text, '我：在吗\n对方：在的');
    });

    testWidgets('the side still has a third answer, which is no answer', (
      WidgetTester tester,
    ) async {
      // A two-way toggle would force a choice between two sides, and ADR-0015
      // makes admitting there is no author better than inventing one. The block
      // carries that third state as a prefix, and a button sets it.
      await pumpPanel(
        tester,
        reviewing(lines: const <PanelLine>[
          PanelLine(speaker: Speaker.unknown, text: '嗯'),
        ]),
      );

      final TextField block = tester.widget<TextField>(
        find.byKey(const Key('panel-review-block')),
      );
      expect(block.controller!.text, '未定：嗯');
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
      // character came back wrong — edited straight in the block.
      await tester.enterText(
        find.byKey(const Key('panel-review-block')),
        '我：在吗\n我：在的，刚看到',
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

    testWidgets('an unnamed conversation cannot be confirmed until named', (
      WidgetTester tester,
    ) async {
      // ADR-0030: the person must be named before the batch can be confirmed,
      // so the round that follows has both halves. The refusal is said at the
      // confirm, the moment it can be fixed.
      final InMemoryPanelChannel channel = await pumpPanel(
        tester,
        PanelFrame(
          analysed: unnamed,
          live: unnamed,
          transcript: batch,
          reviewing: true,
        ),
      );

      await tester.enterText(
        find.byKey(const Key('panel-review-block')),
        '我：在吗\n对方：在的',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('panel-review-confirm')));
      await tester.pumpAndSettle();

      expect(
        channel.sent,
        isEmpty,
        reason: 'the confirm is refused until the person is named',
      );
      expect(
        find.text(AppCopy.zh.text(CopyKey.panelReviewPersonRequired)),
        findsOneWidget,
      );

      await tester.enterText(
        find.byKey(const Key('panel-review-title')),
        '张三',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('panel-review-confirm')));
      await tester.pumpAndSettle();

      expect(channel.sent.last.kind, PanelCommandKind.confirmTranscript);
      expect(channel.sent.last.title, '张三');
    });

    testWidgets('an already-named app is not asked for again', (
      WidgetTester tester,
    ) async {
      // The app is named even with no package behind it (a review entered it by
      // hand once), so the field is not shown at all rather than left for the
      // user to type again.
      await pumpPanel(
        tester,
        PanelFrame(
          analysed: namedNoPackage,
          live: namedNoPackage,
          transcript: batch,
          reviewing: true,
        ),
      );

      expect(find.byKey(const Key('panel-review-app')), findsNothing);
    });

    testWidgets('a missing line is a carriage return, not a button', (
      WidgetTester tester,
    ) async {
      // ADR-0022's row form had a delete and a merge but no insert; a line the
      // recogniser dropped could only be recovered by re-photographing. In a
      // block it is just another line typed.
      final InMemoryPanelChannel channel = await pumpPanel(tester, reviewing());

      await tester.enterText(
        find.byKey(const Key('panel-review-block')),
        '我：在吗\n对方：在的\n对方：刚看到',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('panel-review-confirm')));
      await tester.pumpAndSettle();

      expect(
        channel.sent.last.lines?.map((PanelLine line) => line.text),
        <String>['在吗', '在的', '刚看到'],
      );
    });

    testWidgets('the speaker buttons rewrite the caret\'s line', (
      WidgetTester tester,
    ) async {
      final InMemoryPanelChannel channel = await pumpPanel(tester, reviewing());

      // Focus the block, then put the caret on the second line and flip it to
      // 我. The caret is read straight off the controller, so the field does not
      // need to rebuild for the button to act on it.
      await tester.tap(find.byKey(const Key('panel-review-block')));
      await tester.pumpAndSettle();
      final TextField field = tester.widget<TextField>(
        find.byKey(const Key('panel-review-block')),
      );
      field.controller!.selection = const TextSelection.collapsed(
        offset: '我：在吗\n'.length + 1,
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey<String>('panel-review-set-me')),
      );
      await tester.pumpAndSettle();

      final TextField rewritten = tester.widget<TextField>(
        find.byKey(const Key('panel-review-block')),
      );
      expect(rewritten.controller!.text, '我：在吗\n我：在的');

      await tester.tap(find.byKey(const Key('panel-review-confirm')));
      await tester.pumpAndSettle();
      expect(
        channel.sent.last.lines?.map(
          (PanelLine line) => '${line.speaker.name}:${line.text}',
        ),
        <String>['me:在吗', 'me:在的'],
      );
    });

    testWidgets('the speaker buttons stay off until the block has focus', (
      WidgetTester tester,
    ) async {
      await pumpPanel(tester, reviewing());

      expect(
        tester
            .widget<OutlinedButton>(
              find.byKey(const ValueKey<String>('panel-review-set-other')),
            )
            .onPressed,
        isNull,
        reason:
            'with no caret there is no line to act on, and guessing "the last '
            'one" would be an intention the user did not state',
      );
    });

    testWidgets('tapping a shortcut keeps the caret, not kills it', (
      WidgetTester tester,
    ) async {
      // The bug this pins: on a real device a tap on a shortcut button is a tap
      // *outside* the field, which used to fire the field's `onTapOutside` and
      // unfocus the block — flipping `hasFocus` to false and disabling the very
      // button the finger was on, in the same frame. The whole form now shares
      // one `TextFieldTapRegion`, so the button reads the caret instead of
      // dismissing it.
      final List<bool> focusChanges = <bool>[];
      await pumpPanel(
        tester,
        reviewing(),
        onInputFocusChanged: (bool focusable) async =>
            focusChanges.add(focusable),
      );

      await tester.tap(find.byKey(const Key('panel-review-block')));
      await tester.pumpAndSettle();
      final TextField field = tester.widget<TextField>(
        find.byKey(const Key('panel-review-block')),
      );
      field.controller!.selection = const TextSelection.collapsed(
        offset: '我：在吗\n'.length + 1,
      );
      await tester.pumpAndSettle();
      focusChanges.clear();

      // The tap itself must not release the input focus, and must still act.
      await tester.tap(
        find.byKey(const ValueKey<String>('panel-review-set-me')),
      );
      await tester.pumpAndSettle();

      expect(
        focusChanges,
        isNot(contains(false)),
        reason: 'a shortcut tap must not dismiss the caret it acts on',
      );
      final TextField rewritten = tester.widget<TextField>(
        find.byKey(const Key('panel-review-block')),
      );
      expect(rewritten.controller!.text, '我：在吗\n我：在的');
    });

    testWidgets('删行 deletes the caret\'s physical line and its newline', (
      WidgetTester tester,
    ) async {
      await pumpPanel(tester, reviewing());

      await tester.tap(find.byKey(const Key('panel-review-block')));
      await tester.pumpAndSettle();
      final TextField field = tester.widget<TextField>(
        find.byKey(const Key('panel-review-block')),
      );
      // Caret on the second line.
      field.controller!.selection = const TextSelection.collapsed(
        offset: '我：在吗\n'.length + 1,
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('panel-review-delete-line')));
      await tester.pumpAndSettle();

      final TextField rewritten = tester.widget<TextField>(
        find.byKey(const Key('panel-review-block')),
      );
      expect(rewritten.controller!.text, '我：在吗');
      expect(
        rewritten.controller!.selection,
        const TextSelection.collapsed(offset: '我：在吗'.length),
        reason:
            'the last line goes with its preceding newline, so the caret '
            'lands at the end of the surviving text',
      );
    });

    testWidgets('删行 stays off until focused, and off again when empty', (
      WidgetTester tester,
    ) async {
      await pumpPanel(tester, reviewing());

      // Not focused: nothing to act on.
      expect(
        tester
            .widget<OutlinedButton>(
              find.byKey(const Key('panel-review-delete-line')),
            )
            .onPressed,
        isNull,
      );

      // Focus, then empty the block: the button disables with it.
      await tester.enterText(
        find.byKey(const Key('panel-review-block')),
        '   ',
      );
      await tester.tap(find.byKey(const Key('panel-review-block')));
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<OutlinedButton>(
              find.byKey(const Key('panel-review-delete-line')),
            )
            .onPressed,
        isNull,
        reason: 'there is no line left to delete',
      );
    });

    testWidgets('未定 is a prefix, not a button', (
      WidgetTester tester,
    ) async {
      await pumpPanel(
        tester,
        reviewing(lines: const <PanelLine>[
          PanelLine(speaker: Speaker.unknown, text: '嗯'),
        ]),
      );

      expect(
        find.byKey(const ValueKey<String>('panel-review-set-unknown')),
        findsNothing,
        reason:
            'ADR-0015 keeps 未定 as a speaker, but the way to reach it is the '
            'prefix or inheritance, not a third shortcut that only says "no '
            'author"',
      );
      final TextField block = tester.widget<TextField>(
        find.byKey(const Key('panel-review-block')),
      );
      expect(block.controller!.text, '未定：嗯');
    });

    testWidgets('emptying the block says so and disables confirm', (
      WidgetTester tester,
    ) async {
      await pumpPanel(tester, reviewing());

      await tester.enterText(
        find.byKey(const Key('panel-review-block')),
        '   \n\n  ',
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
        ),
      );

      expect(find.byType(CandidateCard), findsNothing);
      expect(
        find.text(AppCopy.zh.text(CopyKey.panelReviewTitle)),
        findsOneWidget,
      );
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
  Future<void> Function(bool focusable)? onInputFocusChanged,
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
            onInputFocusChanged: onInputFocusChanged,
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
  Future<void> Function(bool focusable)? onInputFocusChanged,
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
      onInputFocusChanged: onInputFocusChanged,
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

/// A field of one of the content types the panel must never keep.
///
/// Two-space indent: a field of a `State` class, and not a local variable inside
/// `build`, which is indented further and is where `advice` is legitimately
/// named. `PanelLine` is deliberately absent — the rows are the surface.
final RegExp _contentFields = RegExp(
  r'^ {2}(?:late )?final\s+(?:Advice|Snapshot|ConversationRef|PanelFrame|Candidate|Trend|Profile)\b',
  multiLine: true,
);

/// The identifiers the panel may not name at all.
///
/// Word-bounded, and that is load-bearing rather than tidiness: the review's own
/// module is called `ReviewSession`, and a bare `Session` alternation would
/// report the panel for naming the thing it is supposed to own.
final RegExp _outsideIdentifiers = RegExp(
  r'\b(?:Session|CapabilitySet|capabilityRegistry|SharedMaterial|ModelTransport)\b',
);

/// The body of the first `State` class in a panel widget: the part of it that
/// must hold nothing but the surface.
///
/// A file with no `State` class comes back whole, because every part of such a
/// file is subject to the same rule.
String _stateClassOf(String relative) {
  final String source = _sourceOf(relative);
  final RegExpMatch? start = RegExp(
    r'class \w+ extends State<\w+> \{',
  ).firstMatch(source);
  return start == null ? source : source.substring(start.end);
}
