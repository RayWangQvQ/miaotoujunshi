import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miaotou_app/panel_main.dart';
import 'package:miaotou_app/src/panel/panel_page.dart';
import 'package:miaotou_app/src/panel/protocol.dart';
import 'package:miaotou_app/src/panel/session.dart';
import 'package:miaotou_app/src/panel/window_channel.dart';
import 'package:miaotou_capabilities/miaotou_capabilities.dart';
import 'package:miaotou_domain/miaotou_domain.dart';

void main() {
  const ConversationRef conversation = ConversationRef(
    packageName: 'com.tencent.mm',
    title: '张三',
  );
  const Advice advice = Advice(
    support: '听起来你有些为难',
    facts: <String>['这周很忙'],
    hypotheses: <String>['可能需要空间'],
    unknowns: <String>['下周是否有空'],
    intent: '暂缓安排',
    intentConfidence: 0.72,
    strategy: '降压',
    recommendation: '先确认时间',
    nextStep: '等对方回复',
    stopCondition: '对方拒绝',
    question: '',
    candidates: <Candidate>[
      Candidate(text: '那你先忙', reason: '降低压力', tradeoff: '推进较慢', weight: 100),
    ],
    rankingStatus: RankingStatus.single,
  );

  test('the complete shared frame survives the window wire codec', () {
    const PanelFrame before = PanelFrame(
      analysed: conversation,
      live: conversation,
      advice: advice,
      note: PanelNote(
        'OCR 待核对',
        remedy: OpenPermissionPage(PermissionKind.accessibility),
      ),
      transcript: <PanelLine>[
        PanelLine(speaker: Speaker.me, text: '在吗'),
        PanelLine(speaker: Speaker.other, text: '在的'),
        PanelLine(speaker: Speaker.unknown, text: '？'),
      ],
      appNames: <String, String>{'com.tencent.mm': '微信'},
    );

    final PanelFrame after = PanelWireCodec.decodeFrame(
      PanelWireCodec.encodeFrame(before),
    );

    expect(after.analysed, conversation);
    expect(after.live, conversation);
    expect(after.advice?.candidates.single.text, '那你先忙');
    expect(after.advice?.rankingStatus, RankingStatus.single);
    expect(after.note?.text, 'OCR 待核对');
    expect(
      after.note?.remedy,
      const OpenPermissionPage(PermissionKind.accessibility),
      reason: 'the remedy is the whole reason a note is a PanelNote rather than a '
          'string; losing it on the wire leaves the panel with a sentence and no '
          'button (ADR-0021 decision 8)',
    );
    expect(
      after.transcript.map((PanelLine line) => line.speaker),
      <Speaker>[Speaker.me, Speaker.other, Speaker.unknown],
      reason: 'a side that does not survive the wire comes back as the wrong '
          'speaker rather than as an error',
    );
    expect(
      after.transcript.map((PanelLine line) => line.text),
      <String>['在吗', '在的', '？'],
    );
    expect(after.appNames, <String, String>{'com.tencent.mm': '微信'});
  });

  test('a note with nothing to press crosses without a remedy', () {
    const PanelFrame before = PanelFrame(
      analysed: conversation,
      note: PanelNote('OCR 未分边，把全部消息当作对方所说'),
    );

    final PanelFrame after = PanelWireCodec.decodeFrame(
      PanelWireCodec.encodeFrame(before),
    );

    expect(after.note?.text, 'OCR 未分边，把全部消息当作对方所说');
    expect(
      after.note?.remedy,
      isNull,
      reason: 'the remedy is optional on the wire, and a decoder that invented '
          'one would put a 去开启 button under a caveat about OCR',
    );
  });

  test('every shared command survives the window wire codec', () {
    for (final PanelCommandKind kind in PanelCommandKind.values) {
      final bool opensAPage = kind == PanelCommandKind.openPermissionSettings;
      final bool carriesBatch = kind == PanelCommandKind.confirmTranscript;
      final PanelCommand before = PanelCommand(
        kind,
        candidateIndex: kind == PanelCommandKind.fill ? 2 : null,
        text: kind == PanelCommandKind.fill ? '改过的回复' : null,
        permission: opensAPage ? PermissionKind.overlay : null,
        lines: carriesBatch
            ? const <PanelLine>[
                PanelLine(speaker: Speaker.me, text: '在吗'),
                PanelLine(speaker: Speaker.unknown, text: '？'),
              ]
            : null,
      );
      final PanelCommand after = PanelWireCodec.decodeCommand(
        PanelWireCodec.encodeCommand(before),
      );
      expect(after.kind, kind);
      expect(after.candidateIndex, before.candidateIndex);
      expect(after.text, before.text);
      expect(
        after.permission,
        before.permission,
        reason: 'a command to open a page that arrives without one opens nothing',
      );
      expect(
        after.lines?.map((PanelLine line) => line.speaker).toList(),
        before.lines?.map((PanelLine line) => line.speaker).toList(),
        reason: 'ADR-0022: the confirmation carries what the user said, and a '
            'side that does not survive the wire comes back as the wrong one',
      );
      expect(
        after.lines?.map((PanelLine line) => line.text).toList(),
        before.lines?.map((PanelLine line) => line.text).toList(),
      );
    }
  });

  test('the review state and its way out survive the codec', () {
    // ADR-0022 decision 13: the refusal that asks for a confirmation carries
    // the way to give one, and both halves of that have to cross the window.
    const PanelFrame before = PanelFrame(
      analysed: conversation,
      transcript: <PanelLine>[PanelLine(speaker: Speaker.other, text: '在吗')],
      note: PanelNote('当前对话全部待核对', remedy: EnterReview()),
      reviewing: true,
    );

    final PanelFrame after = PanelWireCodec.decodeFrame(
      PanelWireCodec.encodeFrame(before),
    );

    expect(after.reviewing, isTrue);
    expect(after.note?.remedy, const EnterReview());
    expect(after.transcript.single.text, '在吗');
  });

  test('an unreviewed frame crosses without the flag', () {
    final PanelFrame after = PanelWireCodec.decodeFrame(
      PanelWireCodec.encodeFrame(const PanelFrame(analysed: conversation)),
    );
    expect(
      after.reviewing,
      isFalse,
      reason: 'the flag is absent when it is false, so an older neighbour still '
          'decodes — and absence has to mean false rather than an error',
    );
  });

  test('the main-engine panel session owns live frames and commands', () async {
    final PanelSession session = PanelSession();
    final Future<PanelFrame> nextFrame = session.frames.first;
    final Future<PanelCommand> nextCommand = session.commands.first;
    const PanelFrame frame = PanelFrame(analysed: conversation, advice: advice);
    const PanelCommand command = PanelCommand(PanelCommandKind.details);

    session.publish(frame);
    session.receive(command);

    expect(await nextFrame, same(frame));
    expect(await nextCommand, same(command));
    expect(session.current, same(frame));
    await session.dispose();
  });

  test('malformed window payloads fail explicitly', () {
    expect(
      () => PanelWireCodec.decodeCommand(<String, Object?>{'kind': 'launch'}),
      throwsFormatException,
    );
    expect(
      () => PanelWireCodec.decodeFrame(<String, Object?>{'analysed': 'bad'}),
      throwsFormatException,
    );
  });

  testWidgets('collapsing the shared panel produces the floating ball', (
    WidgetTester tester,
  ) async {
    final InMemoryPanelChannel channel = InMemoryPanelChannel();
    await tester.pumpWidget(PanelApp(channel: channel));
    channel.push(
      const PanelFrame(
        analysed: conversation,
        live: conversation,
        advice: advice,
        appNames: <String, String>{'com.tencent.mm': '微信'},
      ),
    );
    await tester.pump();

    await tester.tap(find.byIcon(Icons.expand_less));
    await tester.pump();

    expect(find.byKey(const Key('panel-ball')), findsOneWidget);
    expect(find.byType(PanelPage), findsOneWidget);
    channel.dispose();
  });

  testWidgets('the editable draft enables focus and crosses in a command', (
    WidgetTester tester,
  ) async {
    final InMemoryPanelChannel channel = InMemoryPanelChannel();
    final List<bool> focusChanges = <bool>[];
    await tester.pumpWidget(
      PanelApp(
        channel: channel,
        onInputFocusChanged: (bool focusable) async {
          focusChanges.add(focusable);
        },
      ),
    );
    channel.push(
      const PanelFrame(
        analysed: conversation,
        live: conversation,
        advice: advice,
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey<String>('panel-draft-0')));
    await tester.enterText(
      find.byKey(const ValueKey<String>('panel-draft-0')),
      '用系统输入法编辑',
    );
    await tester.tap(find.text('填入'));
    await tester.pump();

    expect(focusChanges, contains(true));
    expect(channel.sent.single.kind, PanelCommandKind.fill);
    expect(channel.sent.single.text, '用系统输入法编辑');
    channel.dispose();
  });

  test('the Windows runner registers plugins in the second engine', () {
    final String source = File('windows/runner/flutter_window.cpp')
        .readAsStringSync();
    expect(source, contains('DesktopMultiWindowSetWindowCreatedCallback'));
    expect(
      source,
      contains('RegisterPlugins(flutter_view_controller->engine())'),
    );
  });

  test('the Android overlay keeps every gate-A rendering invariant', () {
    final String source = File(
      '../../packages/miaotou_capabilities_android/android/src/main/kotlin/'
      'com/miaotoujunshi/capabilities/android/AndroidOverlayHost.kt',
    ).readAsStringSync();

    expect(source, contains('FlutterEngineGroup'));
    expect(source, contains('TYPE_APPLICATION_OVERLAY'));
    expect(source, contains('PixelFormat.TRANSLUCENT'));
    expect(source, contains('FlutterTextureView'));
    expect(source, contains('attachToFlutterEngine'));
    expect(source, contains('appIsResumed'));
    expect(source, contains('setAutomaticallyRegisterPlugins(false)'));
    expect(source, contains('FLAG_NOT_FOCUSABLE'));
    expect(source, contains('FLAG_NOT_TOUCH_MODAL'));
    expect(source, contains('alpha = 1.0f'));
    expect(source, contains('SAFE_EXPANDED_TOP_DP'));
  });

  test('the appearance survives the window wire codec', () {
    for (final int percent in <int>[
      PanelAppearance.minOpacity,
      PanelAppearance.defaultOpacity,
      PanelAppearance.maxOpacity,
    ]) {
      final PanelAppearance before = PanelAppearance.percent(percent);
      expect(
        PanelWireCodec.decodeAppearance(PanelWireCodec.encodeAppearance(before)),
        before,
      );
    }
  });

  test('an appearance outside the range arrives clamped, not refused', () {
    expect(
      PanelWireCodec.decodeAppearance(<String, Object?>{'opacity': 900}).opacity,
      PanelAppearance.maxOpacity,
      reason: 'the range is this build\'s. A value from a build that opened it '
          'further is still a percentage, and refusing it would leave the panel '
          'on the default with nothing said',
    );
  });

  test('a malformed appearance fails explicitly', () {
    expect(
      () => PanelWireCodec.decodeAppearance(<String, Object?>{'opacity': '80%'}),
      throwsFormatException,
    );
    expect(() => PanelWireCodec.decodeAppearance('80'), throwsFormatException);
  });

  testWidgets('the panel paints the fill the main window pushed', (
    WidgetTester tester,
  ) async {
    final InMemoryPanelChannel channel = InMemoryPanelChannel();
    addTearDown(channel.dispose);
    await tester.pumpWidget(PanelApp(channel: channel));
    await tester.pump();

    expect(
      _fillAlpha(tester),
      closeTo(PanelAppearance.defaultOpacity / 100, 0.0001),
      reason: 'the panel engine has no store, so before the first push it '
          'paints the default rather than waiting to be told',
    );

    channel.pushAppearance(const PanelAppearance(opacity: 60));
    // Two pumps rather than one: the controller is a broadcast one, so the
    // value arrives on a microtask and the rebuild lands on the frame after it.
    await tester.pumpAndSettle();
    expect(_fillAlpha(tester), closeTo(0.6, 0.0001));

    channel.pushAppearance(const PanelAppearance(opacity: 100));
    await tester.pumpAndSettle();
    expect(_fillAlpha(tester), closeTo(1, 0.0001));
  });

  test('the macOS panel protocol is named the same on both sides', () {
    final String source = File(
      '../../packages/miaotou_capabilities_macos/macos/'
      'miaotou_capabilities_macos/Sources/miaotou_capabilities_macos/'
      'FloatingPanelHost.swift',
    ).readAsStringSync();

    expect(
      source,
      contains('"$macosPanelProtocolChannelName"'),
      reason: 'the host owns both ends of the macOS relay, so this name is '
          'written in two languages; a rename on one side is a panel that '
          'receives nothing at all',
    );
    expect(
      source,
      contains('"${PanelEngineBootstrap.macosChannelName}"'),
      reason: 'the bootstrap is how the macOS panel engine learns which side '
          'it is, and the Dart side asserts the same string',
    );
    expect(
      source,
      contains('entrypoint = "panelMain"'),
      reason: 'the entrypoint is a name looked up at runtime',
    );
    expect(
      File('lib/main.dart').readAsStringSync(),
      contains("@pragma('vm:entry-point')\nvoid panelMain()"),
      reason: 'an unannotated entrypoint is tree-shaken out of a release build, '
          'and the macOS panel engine then starts with no Dart at all',
    );
  });

  test('the Android host caches the appearance the way it caches the frame', () {
    const String kotlin =
        '../../packages/miaotou_capabilities_android/android/src/main/kotlin/'
        'com/miaotoujunshi/capabilities/android/';
    final String host = File('${kotlin}AndroidOverlayHost.kt').readAsStringSync();
    final String plugin =
        File('${kotlin}MiaotouAndroidPlugin.kt').readAsStringSync();

    expect(
      host,
      contains('latestAppearance'),
      reason: 'the panel engine reaches Dart after the host starts it, so a '
          'value pushed in between has to be held — the same treatment the '
          'frame has always had',
    );
    expect(host, contains('fun publishAppearance'));
    expect(
      plugin,
      contains('"appearance" ->'),
      reason: 'the main engine\'s relay has to accept the second down-stream, '
          'or the push fails as not-implemented',
    );
    expect(
      host,
      isNot(contains('getSharedPreferences')),
      reason: 'the placement is one key in the application\'s Preferences now; '
          'a store here would be the second shape of the same setting that '
          'ADR-0020 retires',
    );
  });

  test('the Windows panel no longer writes a placement file', () {
    // Comments out, because the file explains in prose what it used to do, and
    // the point of the test is what it does now.
    final String code = _stripComments(
      File(
        '../../packages/miaotou_capabilities_windows/lib/src/panel.dart',
      ).readAsStringSync(),
    );

    expect(
      code,
      isNot(contains('dart:io')),
      reason: 'where the panel was left is one key in the application\'s '
          'Preferences now, written from the [PanelDragged] event this file '
          'already emits (ADR-0020 decision 4). A store beside the window is '
          'the second shape of the same setting, and it is what put this value '
          'into three formats on three ports.',
    );
    expect(code, isNot(contains('WindowsPanelPosition')));
    expect(code, isNot(contains('panel-placement.json')));
  });
}

/// The alpha the panel's one fill token is drawn at.
double _fillAlpha(WidgetTester tester) => tester
    .widget<MaterialApp>(find.byType(MaterialApp))
    .theme!
    .cardTheme
    .color!
    .a;

/// Comments out, so that a name quoted in a doc comment is not read as a name
/// the file still uses. Block comments go first, then line comments.
String _stripComments(String source) {
  final String noBlocks = source.replaceAll(
    RegExp(r'/\*.*?\*/', dotAll: true),
    '',
  );
  return noBlocks
      .split('\n')
      .map((String line) => line.replaceAll(RegExp(r'//.*'), ''))
      .join('\n');
}

