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
      note: 'OCR 待核对',
      appNames: <String, String>{'com.tencent.mm': '微信'},
    );

    final PanelFrame after = PanelWireCodec.decodeFrame(
      PanelWireCodec.encodeFrame(before),
    );

    expect(after.analysed, conversation);
    expect(after.live, conversation);
    expect(after.advice?.candidates.single.text, '那你先忙');
    expect(after.advice?.rankingStatus, RankingStatus.single);
    expect(after.note, 'OCR 待核对');
    expect(after.appNames, <String, String>{'com.tencent.mm': '微信'});
  });

  test('every shared command survives the window wire codec', () {
    for (final PanelCommandKind kind in PanelCommandKind.values) {
      final PanelCommand before = PanelCommand(
        kind,
        candidateIndex: kind == PanelCommandKind.fill ? 2 : null,
        text: kind == PanelCommandKind.fill ? '改过的回复' : null,
      );
      final PanelCommand after = PanelWireCodec.decodeCommand(
        PanelWireCodec.encodeCommand(before),
      );
      expect(after.kind, kind);
      expect(after.candidateIndex, before.candidateIndex);
      expect(after.text, before.text);
    }
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
}
