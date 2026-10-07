import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miaotou_app/src/design/copy.dart';
import 'package:miaotou_app/src/panel/protocol.dart';
import 'package:miaotou_app/src/panel/session.dart';
import 'package:miaotou_app/src/runtime/conversation_runtime.dart';
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
      panel.current.note?.text,
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
      await _until(() => panel.current.note?.text == 'failed');

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
      permissions: memory.permissions,
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
    expect(panel.current.note?.text, AppCopy.zh.text(CopyKey.runtimeNoConversation));
  });

  test(
    'a port that refuses the node tree still starts, captures and analyses',
    () async {
      // macOS and Windows answer `UiTreeReader` by refusing it outright
      // (ADR-0009 decision 2): they read pixels and recover the words through
      // OCR, so both members throw `UnsupportedError` rather than returning
      // nothing. That refusal is a fact about the platform, and this test is
      // about the runtime treating it as one.
      //
      // It did not. `start()` subscribed to `snapshots` unconditionally, and the
      // getter throws synchronously — so the exception left `main()` before
      // `runApp`, and the application came up with no window at all. A debug
      // session on macOS ended at "Failed to foreground app" with a lost
      // connection; the stack ran `main` → `start` → `MacosUiTreeReader
      // .snapshots`. `_readTree` and `_subscribeToPushedReads` are the two
      // halves of the answer: the refusal becomes "this port has no tree", and
      // everything else in the file goes on asking one question.
      //
      // The three assertions below are the three things that were broken. A
      // refusal is not a failure, so no note is published for it — the empty
      // state already says what to do and the note would name a failure that
      // did not happen. The capture path is the way in on these ports, so it
      // still works. And an analysis refuses a batch that has not been reviewed
      // *as a review*, not as "the analysis failed", which is what the old
      // `on Object` did with the reader's refusal.
      final InMemoryCapabilities memory = InMemoryCapabilities(
        captureOutcome: CaptureOk(_frame()),
        ocrLines: _twoSidedScreen,
      );
      addTearDown(memory.dispose);
      final PanelSession panel = PanelSession();
      addTearDown(panel.dispose);
      final ConversationRuntime runtime = ConversationRuntime(
        capabilities: _withUiTreeReader(memory, const _DesktopUiTreeReader()),
        panel: panel,
        copy: AppCopy.zh,
        clipboardWrite: (_) {},
        analyzer: (ChatUiSnapshot input, ModelSettings settings) async {
          checkAnalysable(_snapshotOf(input), '关系背景');
          return _advice('可以呀，你想去哪？');
        },
      );
      addTearDown(runtime.dispose);

      await expectLater(runtime.start(), completes);
      expect(
        panel.current.note,
        isNull,
        reason: 'the refusal is about the platform, not about this session',
      );
      expect(panel.current.analysed, ConversationRef.none);

      panel.receive(const PanelCommand(PanelCommandKind.recogniseOnce));
      await _until(() => panel.current.reviewing);
      expect(panel.current.transcript, hasLength(2));

      // With no tree to re-read, the capture is the batch in play — and the
      // refusal that comes back is the review's, carrying its way out.
      panel.receive(const PanelCommand(PanelCommandKind.reanalyse));
      await _until(() => panel.current.note?.remedy == const EnterReview());
      expect(
        panel.current.note?.text,
        isNot(AppCopy.zh.text(CopyKey.runtimeAnalysisFailed)),
        reason: 'the reader refusing is not the analysis failing',
      );

      panel.receive(
        const PanelCommand(
          PanelCommandKind.confirmTranscript,
          lines: <PanelLine>[
            PanelLine(speaker: Speaker.me, text: '在吗'),
            PanelLine(speaker: Speaker.other, text: '在的'),
          ],
        ),
      );
      await _until(
        () =>
            !panel.current.reviewing &&
            panel.current.note?.text == AppCopy.zh.text(CopyKey.panelNoteReviewed),
      );

      panel.receive(const PanelCommand(PanelCommandKind.reanalyse));
      await _until(() => panel.current.advice != null);
    },
  );

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

  test('what a capture read reaches the panel, not just that it read', () async {
    // The device run that started this: 48 lines came back off a Feishu screen
    // and the panel showed only the caveat about the sides. A successful read
    // and a read that found nothing looked the same to the user, because the
    // frame had nowhere to put the lines.
    final InMemoryCapabilities capabilities = InMemoryCapabilities(
      captureOutcome: CaptureOk(_frame()),
      ocrLines: _twoSidedScreen,
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
    // Waiting on the review rather than on a non-empty transcript is the whole
    // point since ADR-0022 decision 17: `start()` reads the tree and puts those
    // lines on the panel too, so "the panel has a transcript" is already true
    // before this command has been handled at all, and an assertion written
    // against that would be racing the capture it means to describe.
    await _until(() => panel.current.reviewing);

    expect(
      panel.current.transcript.map((PanelLine line) => line.speaker),
      <Speaker>[Speaker.me, Speaker.other],
      reason: 'the right half of the frame is the user, the left is the other',
    );
    expect(
      panel.current.transcript.map((PanelLine line) => line.text),
      <String>['在吗', '在的'],
    );
    expect(
      panel.current.reviewing,
      isTrue,
      reason: 'ADR-0022 decision 7: a whole-frame capture goes straight into the '
          'review. Every line of one carries the marker, so the first analysis '
          'of it is refused every time — presenting that refusal as the panel\'s '
          'opening offer is a button that cannot succeed.',
    );
  });

  test('a capture is refused until it is reviewed, and then it is not', () async {
    // The report ADR-0022 closes, walked end to end: 「识别一次」 on an
    // application with no adapter — the registry answers nothing, which is the
    // only case this command exists for — and the flow stopped dead on
    // 「当前对话全部待核对」 with no surface to answer it on.
    //
    // The refusal itself is correct and stays: ML Kit's Chinese recogniser
    // reports no per-line score, so the engine cannot vouch for a line it read
    // off a screenshot, every line of a capture carries the marker, and a
    // transcript where *every* line is doubtful is one nobody should be asked to
    // answer. What was missing was the other half — a person saying "that is
    // what the screen said" — and this is that half.
    final InMemoryCapabilities memory = InMemoryCapabilities(
      captureOutcome: CaptureOk(_frame()),
      ocrLines: _twoSidedScreen,
    );
    addTearDown(memory.dispose);
    final PanelSession panel = PanelSession();
    addTearDown(panel.dispose);
    ChatUiSnapshot? analysed;
    final ConversationRuntime runtime = ConversationRuntime(
      capabilities: _withUiTreeReader(memory, _NoAdapterUiTreeReader()),
      panel: panel,
      copy: AppCopy.zh,
      clipboardWrite: (_) {},
      analyzer: (ChatUiSnapshot input, ModelSettings settings) async {
        // The domain's own gate, asked about the snapshot the runtime handed
        // over, rather than a stand-in for it. A double that merely recorded its
        // input would let this pass while the real gate still refused.
        checkAnalysable(_snapshotOf(input), '关系背景');
        // Recorded *after* the gate, so this is "the batch the analysis agreed
        // to work on" and not "the batch it was offered" — which is the whole
        // difference the first assertion below turns on.
        analysed = input;
        return _advice('可以呀，你想去哪？');
      },
    );
    addTearDown(runtime.dispose);
    await runtime.start();

    panel.receive(const PanelCommand(PanelCommandKind.recogniseOnce));
    await _until(() => panel.current.reviewing);

    // Asking for an analysis right here is what the user did, and it is refused
    // — but the refusal now carries the way out instead of being a full stop
    // (ADR-0022 decision 13).
    panel.receive(const PanelCommand(PanelCommandKind.reanalyse));
    await _until(() => panel.current.note?.remedy == const EnterReview());
    expect(
      panel.current.note?.text,
      '当前对话全部待核对，请先确认说话人和原文，再生成回复',
      reason: 'the refusal the report named, unchanged',
    );
    expect(analysed, isNull);

    // 「去核对」, and the user fixes the sides: 在的 was read as the other party
    // and is their own.
    panel.receive(const PanelCommand(PanelCommandKind.openReview));
    await _until(() => panel.current.reviewing);
    panel.receive(
      const PanelCommand(
        PanelCommandKind.confirmTranscript,
        lines: <PanelLine>[
          PanelLine(speaker: Speaker.me, text: '在吗'),
          PanelLine(speaker: Speaker.me, text: '在的'),
        ],
      ),
    );
    await _until(
      () =>
          !panel.current.reviewing &&
          panel.current.note?.text == AppCopy.zh.text(CopyKey.panelNoteReviewed),
    );

    // And the same command the panel refused a moment ago now goes through.
    panel.receive(const PanelCommand(PanelCommandKind.reanalyse));
    await _until(() => panel.current.advice != null);

    expect(
      analysed?.lines.map((ChatLine line) => line.speaker),
      <Speaker>[Speaker.me, Speaker.me],
      reason: 'the analysis reads the batch the user confirmed — the sides they '
          'corrected — not a fresh read of the same screen',
    );
    expect(
      analysed?.lines.map((ChatLine line) => line.text),
      <String>['在吗', '在的'],
    );
    expect(
      analysed?.reviewed,
      isTrue,
      reason: 'the confirmation is the fact the gate was waiting for',
    );
  });

  test('a confirmed batch is never told to go and confirm itself', () async {
    // ADR-0024. The remedy on a refusal is decided by asking the gate what it
    // would say about the lines being analysed — and the runtime used to render
    // those lines itself, which kept `[OCR待核对]` on a batch the user had just
    // confirmed. A refusal that no review can fix — a background that is too
    // long — then offered 「去核对」, sending the user back through a door they
    // had already walked through.
    final InMemoryCapabilities memory = InMemoryCapabilities(
      captureOutcome: CaptureOk(_frame()),
      ocrLines: _twoSidedScreen,
    );
    addTearDown(memory.dispose);
    final PanelSession panel = PanelSession();
    addTearDown(panel.dispose);
    final ConversationRuntime runtime = ConversationRuntime(
      capabilities: _withUiTreeReader(memory, _NoAdapterUiTreeReader()),
      panel: panel,
      copy: AppCopy.zh,
      clipboardWrite: (_) {},
      analyzer: (_, _) async => throw const DomainException('关系背景过长'),
    );
    addTearDown(runtime.dispose);
    await runtime.start();

    panel.receive(const PanelCommand(PanelCommandKind.recogniseOnce));
    await _until(() => panel.current.reviewing);

    // Before the review the refusal does carry the way out (ADR-0022 dec. 13).
    panel.receive(const PanelCommand(PanelCommandKind.reanalyse));
    await _until(() => panel.current.note?.remedy == const EnterReview());

    panel.receive(const PanelCommand(PanelCommandKind.openReview));
    await _until(() => panel.current.reviewing);
    panel.receive(
      const PanelCommand(
        PanelCommandKind.confirmTranscript,
        lines: <PanelLine>[
          PanelLine(speaker: Speaker.me, text: '在吗'),
          PanelLine(speaker: Speaker.me, text: '在的'),
        ],
      ),
    );
    await _until(
      () =>
          panel.current.note?.text == AppCopy.zh.text(CopyKey.panelNoteReviewed),
    );

    panel.receive(const PanelCommand(PanelCommandKind.reanalyse));
    await _until(() => panel.current.note?.text == '关系背景过长');
    expect(
      panel.current.note?.remedy,
      isNull,
      reason: 'a review cannot shorten a background, and a batch the user has '
          'already confirmed is not asking to be confirmed again',
    );
  });

  test('a conversation-identity event does not end a review in progress', () async {
    // Android's `AndroidConversationEvent` maps to `ChatUiSnapshot(lines: const
    // [])`: it fires when the foreground flips or the read-only flag changes,
    // and it carries no words at all. It must move the panel's "current
    // conversation" and nothing else — the batch being reviewed is still the
    // batch on the screen.
    //
    // It used to end the review: `_acceptSnapshot` treated every pushed read as
    // a fresh read and published `reviewing: false` with an empty transcript,
    // so tapping a line to edit it — and the accessibility event that tap
    // caused — wiped the batch out from under the user.
    final InMemoryCapabilities memory = InMemoryCapabilities(
      captureOutcome: CaptureOk(_frame()),
      ocrLines: _twoSidedScreen,
    );
    addTearDown(memory.dispose);
    final PanelSession panel = PanelSession();
    addTearDown(panel.dispose);
    final ConversationRuntime runtime = ConversationRuntime(
      capabilities: memory.toSet(),
      panel: panel,
      copy: AppCopy.zh,
      clipboardWrite: (_) {},
      analyzer: (_, _) async => _advice('unused'),
    );
    addTearDown(runtime.dispose);
    await runtime.start();

    panel.receive(const PanelCommand(PanelCommandKind.recogniseOnce));
    await _until(() => panel.current.reviewing);
    expect(panel.current.transcript, hasLength(2));

    // The identity event: the user is still in the same conversation, the
    // service just re-announced the foreground with no new text.
    memory.uiTreeReader.push(
      ChatUiSnapshot(
        conversation: conversation,
        lines: const <ChatLine>[],
        capturedAt: DateTime.now(),
      ),
    );
    await _until(() => panel.current.live == conversation);

    expect(
      panel.current.reviewing,
      isTrue,
      reason: 'an event with no words cannot end a review: the batch being '
          'edited is still the batch on the screen',
    );
    expect(
      panel.current.transcript.map((PanelLine line) => line.text),
      <String>['在吗', '在的'],
      reason: 'the transcript is not replaced by an empty read',
    );
  });

  test('a refused frame reaches the panel in the platform\'s own words', () async {
    // The platform writes these sentences to be shown unchanged, and the panel is
    // the only channel: a generic replacement would leave the user with a
    // sentence that fits every failure and therefore diagnoses none.
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
          panel.current.note?.text != AppCopy.zh.text(CopyKey.runtimeRecognising),
    );

    expect(panel.current.note?.text, contains('window is not visible'));
    expect(
      panel.current.note?.text,
      isNot(AppCopy.zh.text(CopyKey.runtimeCaptureFailed)),
      reason: 'the platform said why; repeating a generic sentence buries it',
    );
    expect(
      capabilities.ocr.languageCalls,
      isEmpty,
      reason: 'nothing was read, so nothing should have been asked to read it',
    );
  });

  test('an absent accessibility service is named, not described in general', () async {
    // This is what 「拿不到画面」 cost the first time: the Android bridge cannot
    // take a picture without its accessibility service, so it raises this code
    // before any capture machinery runs. The generic sentence tells the user to
    // check accessibility without telling them that is what is wrong, and the
    // first device run read as a broken capture rather than a switched-off
    // service.
    final InMemoryCapabilities capabilities = InMemoryCapabilities(
      captureThrows: PlatformException(
        code: 'accessibility_service_unavailable',
        message: 'Enable the Miaotou accessibility service.',
      ),
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
    await _until(
      () =>
          panel.current.note != null &&
          panel.current.note?.text != AppCopy.zh.text(CopyKey.runtimeRecognising),
    );

    expect(panel.current.note?.text, AppCopy.zh.text(CopyKey.runtimeCaptureServiceOff));
    // And the way out of it. ADR-0021 decision 8: naming the cause was the first
    // half of the repair, and a note that names it without carrying the
    // permission is a sentence the user still has to translate into a page.
    expect(
      panel.current.note?.remedy,
      const OpenPermissionPage(PermissionKind.accessibility),
    );
    expect(
      capabilities.ocr.languageCalls,
      isEmpty,
      reason: 'there was never a frame to read',
    );
  });

  test('an unnamed platform error keeps the generic sentence', () async {
    // The bridge's other codes are written for a developer, so they are not
    // shown: only the one that has a remedy of its own is spelled out.
    final InMemoryCapabilities capabilities = InMemoryCapabilities(
      captureThrows: PlatformException(code: 'android_control_capture_failed'),
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
    await _until(
      () =>
          panel.current.note != null &&
          panel.current.note?.text != AppCopy.zh.text(CopyKey.runtimeRecognising),
    );

    expect(panel.current.note?.text, AppCopy.zh.text(CopyKey.runtimeCaptureFailed));
    expect(
      panel.current.note?.remedy,
      isNull,
      reason: 'a defect has no page to open; offering one would send the user to '
          'a setting that is already correct',
    );
  });
}

/// A frame the double answers with. The pixels are empty because nothing reads
/// them: the OCR double answers from its own list, and the geometry that decides
/// the sides comes from the frame's dimensions.
CaptureFrame _frame() => CaptureFrame(
  pixels: Uint8List(0),
  width: 1080,
  height: 2400,
  scaleX: 1,
  scaleY: 1,
  originX: 0,
  originY: 0,
);

/// Two lines off one screen, one on each side: the user's on the right, the
/// other party's on the left.
const List<OcrLine> _twoSidedScreen = <OcrLine>[
  OcrLine(
    text: '在吗',
    bounds: ScreenRect(left: 700, top: 700, right: 900, bottom: 740),
    confidence: 1,
  ),
  OcrLine(
    text: '在的',
    bounds: ScreenRect(left: 40, top: 900, right: 240, bottom: 940),
    confidence: 1,
  ),
];

/// The domain snapshot the runtime would build for an analyser, rebuilt here so
/// a test can ask the gate the same question a device asks it.
///
/// The confidence is non-finite rather than null, and that is load-bearing: a
/// batch read off a screenshot gets `double.nan` because ML Kit reports no
/// per-line score, which is what puts the marker on every line and what makes
/// the gate refuse. Handing null over instead would leave the transcript
/// unmarked and let a test pass for a reason that never happens.
Snapshot _snapshotOf(ChatUiSnapshot input) => Snapshot.fromCaptured(
  title: input.conversation.title,
  source: 'ocr',
  lines: <CapturedLine>[
    for (final ChatLine line in input.lines)
      CapturedLine(
        speaker: line.speaker,
        text: line.text,
        confidence: double.nan,
      ),
  ],
  reviewed: input.reviewed,
);

/// The double's eleven, with the tree reader swapped for one that answers
/// nothing.
CapabilitySet _withUiTreeReader(InMemoryCapabilities memory, UiTreeReader reader) =>
    CapabilitySet(
      screenCapture: memory.screenCapture,
      uiTreeReader: reader,
      ocr: memory.ocr,
      textInject: memory.textInject,
      floatingPanel: memory.floatingPanel,
      permissions: memory.permissions,
      sharedPayload: memory.payload,
      preferences: memory.preferences,
      secretStore: memory.secretStore,
      knowledgeStore: memory.knowledgeStore,
      memoryStore: memory.memoryStore,
    );

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

/// An application the adapter registry does not know.
///
/// Null rather than an error, and that distinction is the whole reason
/// 「识别一次」 exists: a null answer is "there is no tree here", which is a
/// normal fact about an unknown application, where an error is the platform
/// failing to answer. It is also what makes the capture the only batch in play —
/// with nothing to re-read, an analysis of this conversation is an analysis of
/// the capture, which is the path the report was on.
final class _NoAdapterUiTreeReader implements UiTreeReader {
  @override
  Future<ChatUiSnapshot?> readActiveChat() async => null;

  @override
  Stream<ChatUiSnapshot> get snapshots => const Stream<ChatUiSnapshot>.empty();
}

/// macOS and Windows, which refuse the node tree permanently rather than
/// answering it with nothing (ADR-0009 decision 2).
///
/// Both members go through the real `unsupportedOnThisPlatform`, so what this
/// double throws is what a device throws. That matters more here than in most
/// doubles: the whole defect was a caller that could not tell a refusal from an
/// answer, and a stand-in that threw something else would test the wrong thing.
///
/// **`snapshots` throws from the getter, synchronously** — that is the shape
/// the real ports have, and it is why the failure surfaced as an exception out
/// of `main` rather than as an errored stream nobody was listening to yet.
final class _DesktopUiTreeReader implements UiTreeReader {
  const _DesktopUiTreeReader();

  static const String _reason =
      'the desktop ports read pixels, not accessibility nodes; the words come '
      'back through Ocr';

  @override
  Future<ChatUiSnapshot?> readActiveChat() async => unsupportedOnThisPlatform(
    platform: 'macOS',
    member: 'UiTreeReader.readActiveChat',
    reason: _reason,
  );

  @override
  Stream<ChatUiSnapshot> get snapshots => unsupportedOnThisPlatform(
    platform: 'macOS',
    member: 'UiTreeReader.snapshots',
    reason: _reason,
  );
}
