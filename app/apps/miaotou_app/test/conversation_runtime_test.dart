import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:miaotou_app/src/design/copy.dart';
import 'package:miaotou_app/src/panel/protocol.dart';
import 'package:miaotou_app/src/panel/session.dart';
import 'package:miaotou_app/src/runtime/conversation_runtime.dart';
import 'package:miaotou_app/src/runtime/model_settings.dart';
import 'package:miaotou_capabilities/miaotou_capabilities.dart';
import 'package:miaotou_capabilities/testing.dart';
import 'package:miaotou_domain/miaotou_domain.dart';

void main() {
  const ConversationRef conversation = ConversationRef(
    packageName: 'com.ss.android.lark',
    title: '测试会话',
  );
  final ChatUiSnapshot snapshot = ChatUiSnapshot(
    conversation: conversation,
    lines: const <ChatLine>[ChatLine(speaker: Speaker.other, text: '周末有空吗')],
    capturedAt: DateTime.utc(2025),
  );

  test(
    'capture, analysis, copy, and verified fill form one runtime loop',
    () async {
      final InMemoryCapabilities capabilities = InMemoryCapabilities(
        targetWindow: '7',
      );
      addTearDown(capabilities.dispose);
      final PanelSession panel = PanelSession();
      addTearDown(panel.dispose);
      final List<String> copied = <String>[];
      var analyses = 0;
      final ConversationRuntime runtime = ConversationRuntime(
        capabilities: capabilities.toSet(),
        panel: panel,
        copy: AppCopy.zh,
        clipboardWrite: copied.add,
        analyzer: (ChatUiSnapshot input, ModelSettings settings) async {
          analyses++;
          expect(input.signature(), snapshot.signature());
          return _advice('可以呀，你想去哪？');
        },
      );
      addTearDown(runtime.dispose);
      await runtime.start();

      capabilities.uiTreeReader.push(snapshot);
      await _until(() => panel.current.live == conversation);
      expect(
        panel.current.analysed,
        conversation,
        reason:
            'before the first analysis the header still names the captured '
            'conversation instead of showing the unidentified placeholder',
      );

      panel.receive(const PanelCommand(PanelCommandKind.analyseCurrent));
      await _until(() => panel.current.advice != null);
      expect(analyses, 1);
      expect(panel.current.analysed, conversation);

      panel.receive(
        const PanelCommand(
          PanelCommandKind.copy,
          candidateIndex: 0,
          text: 'edited copy',
        ),
      );
      await _until(() => copied.isNotEmpty);
      expect(copied, <String>['edited copy']);

      panel.receive(
        const PanelCommand(
          PanelCommandKind.fill,
          candidateIndex: 0,
          text: 'edited fill',
        ),
      );
      await _until(() => capabilities.textInject.injected.isNotEmpty);
      expect(capabilities.textInject.injected, <String>['edited fill']);
      expect(capabilities.textInject.targets, <String>['7']);
    },
  );

  test('switching conversations makes fill refuse without writing', () async {
    final InMemoryCapabilities capabilities = InMemoryCapabilities(
      targetWindow: '7',
    );
    addTearDown(capabilities.dispose);
    final PanelSession panel = PanelSession();
    addTearDown(panel.dispose);
    final ConversationRuntime runtime = ConversationRuntime(
      capabilities: capabilities.toSet(),
      panel: panel,
      copy: AppCopy.zh,
      clipboardWrite: (_) {},
      analyzer: (_, _) async => _advice('first'),
    );
    addTearDown(runtime.dispose);
    await runtime.start();
    capabilities.uiTreeReader.push(snapshot);
    await _until(() => panel.current.live == conversation);
    panel.receive(const PanelCommand(PanelCommandKind.analyseCurrent));
    await _until(() => panel.current.advice != null);

    capabilities.uiTreeReader.push(
      ChatUiSnapshot(
        conversation: const ConversationRef(
          packageName: 'com.tencent.mm',
          title: '另一个会话',
        ),
        lines: const <ChatLine>[ChatLine(speaker: Speaker.other, text: '你好')],
        capturedAt: DateTime.utc(2025, 1, 2),
      ),
    );
    await _until(() => panel.current.live != conversation);
    panel.receive(
      const PanelCommand(
        PanelCommandKind.fill,
        candidateIndex: 0,
        text: 'must not land',
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(capabilities.textInject.injected, isEmpty);
    expect(
      panel.current.note,
      AppCopy.zh.text(CopyKey.runtimeConversationChanged),
    );
  });

  test(
    'a failed reanalysis clears advice from the previous conversation',
    () async {
      final InMemoryCapabilities capabilities = InMemoryCapabilities();
      addTearDown(capabilities.dispose);
      final PanelSession panel = PanelSession();
      addTearDown(panel.dispose);
      final List<Advice?> published = <Advice?>[];
      var analyses = 0;
      final ConversationRuntime runtime = ConversationRuntime(
        capabilities: capabilities.toSet(),
        panel: panel,
        copy: AppCopy.zh,
        clipboardWrite: (_) {},
        onAdvice: published.add,
        analyzer: (_, _) async {
          analyses++;
          if (analyses > 1) {
            throw const DomainException('failed');
          }
          return _advice('first');
        },
      );
      addTearDown(runtime.dispose);
      await runtime.start();
      capabilities.uiTreeReader.push(snapshot);
      panel.receive(const PanelCommand(PanelCommandKind.analyseCurrent));
      await _until(() => panel.current.advice != null);

      panel.receive(const PanelCommand(PanelCommandKind.reanalyse));
      await _until(() => panel.current.note == 'failed');

      expect(panel.current.advice, isNull);
      expect(published, hasLength(2));
      expect(published.first, isNotNull);
      expect(published.last, isNull);
    },
  );

  test('the main runtime starts while accessibility is unavailable', () async {
    final InMemoryCapabilities memory = InMemoryCapabilities();
    addTearDown(memory.dispose);
    final CapabilitySet capabilities = CapabilitySet(
      screenCapture: memory.screenCapture,
      uiTreeReader: _UnavailableUiTreeReader(),
      ocr: memory.ocr,
      textInject: memory.textInject,
      floatingPanel: memory.floatingPanel,
      sharedPayload: memory.payload,
      preferences: memory.preferences,
      secretStore: memory.secretStore,
      knowledgeStore: memory.knowledgeStore,
      memoryStore: memory.memoryStore,
    );
    final PanelSession panel = PanelSession();
    addTearDown(panel.dispose);
    final ConversationRuntime runtime = ConversationRuntime(
      capabilities: capabilities,
      panel: panel,
      copy: AppCopy.zh,
      clipboardWrite: (_) {},
      analyzer: (_, _) async => _advice('unused'),
    );
    addTearDown(runtime.dispose);

    await expectLater(runtime.start(), completes);

    expect(panel.current.analysed, ConversationRef.none);
    expect(panel.current.note, AppCopy.zh.text(CopyKey.runtimeNoConversation));
  });

  test('recogniseOnce asks for the screen, not for a window handle', () async {
    // It exists for applications the adapter registry does not know, so there is
    // no window to name. Naming one is also actively wrong: the handle describes
    // whichever window is active, which while the panel is up is liable to be the
    // panel itself, and it is stale by the time the panel comes off — exactly the
    // mismatch Android's capture refuses with -3 「目标窗口已经切换」.
    final InMemoryCapabilities capabilities = InMemoryCapabilities(
      targetWindow: '7',
    );
    addTearDown(capabilities.dispose);
    final PanelSession panel = PanelSession();
    addTearDown(panel.dispose);
    final ConversationRuntime runtime = ConversationRuntime(
      capabilities: capabilities.toSet(),
      panel: panel,
      copy: AppCopy.zh,
      clipboardWrite: (_) {},
      analyzer: (_, _) async => _advice('unused'),
    );
    addTearDown(runtime.dispose);
    await runtime.start();

    panel.receive(const PanelCommand(PanelCommandKind.recogniseOnce));
    await _until(() => capabilities.screenCapture.captureCalls.isNotEmpty);

    expect(capabilities.screenCapture.captureCalls, <String?>[null]);
  });

  test('a refused frame reaches the panel in the platform\'s own words', () async {
    // The platform writes these sentences to be shown unchanged, and the panel is
    // the only channel: a generic replacement would leave the user with a
    // sentence that fits every failure and therefore diagnoses none. The
    // accessibility-unavailable case keeps the generic one, because there the
    // platform declined to answer at all.
    final InMemoryCapabilities capabilities = InMemoryCapabilities();
    addTearDown(capabilities.dispose);
    capabilities.screenCapture.outcome = const CaptureFailed(
      code: 6,
      message: 'window is not visible or is protected',
    );
    final PanelSession panel = PanelSession();
    addTearDown(panel.dispose);
    final ConversationRuntime runtime = ConversationRuntime(
      capabilities: capabilities.toSet(),
      panel: panel,
      copy: AppCopy.zh,
      clipboardWrite: (_) {},
      analyzer: (_, _) async => _advice('unused'),
    );
    addTearDown(runtime.dispose);
    await runtime.start();

    panel.receive(const PanelCommand(PanelCommandKind.recogniseOnce));
    await _until(
      () =>
          panel.current.note != null &&
          panel.current.note != AppCopy.zh.text(CopyKey.runtimeRecognising),
    );

    expect(panel.current.note, contains('window is not visible'));
    expect(
      panel.current.note,
      isNot(AppCopy.zh.text(CopyKey.runtimeCaptureFailed)),
      reason: 'the platform said why; repeating a generic sentence buries it',
    );
    expect(
      capabilities.ocr.languageCalls,
      isEmpty,
      reason: 'nothing was read, so nothing should have been asked to read it',
    );
  });
}

Advice _advice(String text) => Advice(
  support: 'support',
  facts: const <String>['fact'],
  hypotheses: const <String>[],
  unknowns: const <String>[],
  intent: 'intent',
  intentConfidence: 0.8,
  strategy: '澄清',
  recommendation: 'recommendation',
  nextStep: 'next',
  stopCondition: 'stop',
  question: 'question',
  candidates: <Candidate>[
    Candidate(text: text, reason: 'reason', tradeoff: 'tradeoff', weight: 100),
  ],
  rankingStatus: RankingStatus.single,
);

Future<void> _until(bool Function() condition) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    if (condition()) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  throw TimeoutException('condition did not become true');
}

final class _UnavailableUiTreeReader implements UiTreeReader {
  @override
  Future<ChatUiSnapshot?> readActiveChat() =>
      Future<ChatUiSnapshot?>.error(StateError('service unavailable'));

  @override
  Stream<ChatUiSnapshot> get snapshots => const Stream<ChatUiSnapshot>.empty();
}
