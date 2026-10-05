import 'dart:async';

import 'package:flutter/services.dart';
import 'package:miaotou_capabilities/miaotou_capabilities.dart';
import 'package:miaotou_domain/miaotou_domain.dart';

import '../design/copy.dart';
import '../panel/protocol.dart';
import '../panel/session.dart';
import 'model_settings.dart';
import 'model_transport.dart';
import 'manual_recognition.dart';

typedef ConversationAnalyzer = Future<Advice> Function(
  ChatUiSnapshot snapshot,
  ModelSettings settings,
);

final class ConversationRuntime {
  ConversationRuntime({
    required this.capabilities,
    required this.panel,
    required this.copy,
    required this.clipboardWrite,
    this.onAdvice,
    ConversationAnalyzer? analyzer,
  }) : _customAnalyzer = analyzer;

  final CapabilitySet capabilities;
  final PanelSession panel;
  final AppCopy copy;
  final FutureOr<void> Function(String text) clipboardWrite;
  final ValueChanged<Advice?>? onAdvice;
  final ConversationAnalyzer? _customAnalyzer;

  StreamSubscription<ChatUiSnapshot>? _snapshotSubscription;
  StreamSubscription<PanelCommand>? _commandSubscription;
  ChatUiSnapshot? _latest;
  ChatUiSnapshot? _analysedSnapshot;

  /// How [_latest] was obtained, for the transcript's own `source` field.
  ///
  /// Today it distinguishes the one path whose provenance we know for certain —
  /// a manual whole-frame capture, which is OCR by construction (ADR-0018) — from
  /// everything else. An event the platform pushes is called `accessibility`
  /// whether or not the retained service reached it through its own OCR
  /// fallback, because the wire carries no provenance; that gap predates this
  /// field and is recorded rather than papered over.
  String _latestSource = 'accessibility';

  /// The source of the snapshot a running analysis is reading.
  ///
  /// A field rather than a parameter because [ConversationAnalyzer] is the
  /// public seam a test substitutes, and widening it to carry provenance would
  /// push a platform detail through every caller to reach one of them.
  String _sourceOfCurrent = 'accessibility';
  Advice? _advice;
  SharedMaterial? _material;
  bool _analysing = false;
  bool _recognising = false;
  bool _pendingAutomaticAnalysis = false;
  bool _disposed = false;

  Future<void> start() async {
    _snapshotSubscription = capabilities.uiTreeReader.snapshots.listen(
      _acceptSnapshot,
      onError: (_) {
        _publish(note: copy.text(CopyKey.runtimeNoConversation));
      },
    );
    _commandSubscription = panel.commands.listen(_handleCommand);
    try {
      final ChatUiSnapshot? initial = await capabilities.uiTreeReader
          .readActiveChat();
      if (initial != null) {
        _acceptSnapshot(initial);
      }
    } on Object {
      _publish(note: copy.text(CopyKey.runtimeNoConversation));
    }
  }

  void _acceptSnapshot(ChatUiSnapshot snapshot) {
    if (_disposed) {
      return;
    }
    final String previousSignature = _latest?.signature() ?? '';
    _latest = snapshot;
    _latestSource = 'accessibility';
    _publish(
      analysed: _analysedSnapshot == null ? snapshot.conversation : null,
      live: snapshot.conversation,
      note: snapshot.note,
    );
    if (snapshot.signature() == previousSignature) {
      return;
    }
    unawaited(_autoAnalyzeIfEnabled());
  }

  Future<void> _autoAnalyzeIfEnabled() async {
    final ModelSettings settings = await ModelSettings.load(
      capabilities.preferences,
      capabilities.secretStore,
    );
    if (settings.autoAnalyze) {
      await _analyze(manual: false);
    }
  }

  void _handleCommand(PanelCommand command) {
    switch (command.kind) {
      case PanelCommandKind.analyseCurrent:
      case PanelCommandKind.reanalyse:
        unawaited(_analyze(manual: true));
      case PanelCommandKind.recogniseOnce:
        unawaited(_recogniseOnce());
      case PanelCommandKind.copy:
        unawaited(_copy(command.text));
      case PanelCommandKind.fill:
        unawaited(_fill(command.text));
      case PanelCommandKind.details:
      case PanelCommandKind.close:
        break;
    }
  }

  /// Photographs whatever is in front and reads the whole frame (ADR-0018).
  ///
  /// Composed from contract members rather than handed to the platform, which is
  /// what keeps ADR-0009's boundary intact and puts the grouping and the side
  /// guess in pure Dart where a fixture can pin them.
  ///
  /// No window handle is passed, and the panel is not hidden here.
  ///
  /// `capture(null)` asks for the screen, which is the only question this command
  /// can ask: it exists for applications the adapter registry does not know, so
  /// there is no window to name. `findTargetWindow` answers a per-window question
  /// and answers it with the window that is *active*, which while the panel is up
  /// is liable to be the panel itself. Worse, a handle taken before the panel
  /// comes off is stale by the time it arrives: Android's `capture` refuses a
  /// handle that no longer matches the live window (-3, 「目标窗口已经切换」), and
  /// hiding is exactly what changes it. The retired port's manual path passed no
  /// handle either.
  ///
  /// Hiding the panel belongs to the implementation for the same reason the rate
  /// limit does (ADR-0009): macOS hides and restores inside its own `capture`,
  /// Android's native `ScreenCapture` does, and both restore in a `finally` that
  /// a failure here cannot reach. Doing it at this level hid the panel twice and,
  /// by invalidating the handle, was most of why this command failed.
  ///
  /// This is the only way in for an application with no adapter, so a failure
  /// here has to say why rather than leave the user with an unchanged panel.
  Future<void> _recogniseOnce() async {
    if (_recognising || _disposed) {
      return;
    }
    _recognising = true;
    _publish(note: copy.text(CopyKey.runtimeRecognising));
    try {
      switch (await capabilities.screenCapture.capture()) {
        case CaptureFailed(:final String message):
          _publish(note: _refusal(message));
        case CaptureOk(:final CaptureFrame frame):
          await _readFrame(frame);
      }
    } on PlatformException catch (failure) {
      _publish(note: _platformRefusal(failure));
    } on Object {
      // The platform declining to answer at all — a channel that is gone, a
      // bridge that never attached — rather than declining this particular
      // frame.
      _publish(note: copy.text(CopyKey.runtimeCaptureFailed));
    } finally {
      _recognising = false;
    }
  }

  /// The reading half of [_recogniseOnce], once a frame is in hand.
  ///
  /// Separate from the capture so the two failures stay distinguishable: a frame
  /// we could not take and a frame we could not read both end in the panel, and
  /// the panel is the only channel there is — nothing writes these to a log.
  Future<void> _readFrame(CaptureFrame frame) async {
    final List<OcrLine> recognised;
    try {
      recognised = await capabilities.ocr.recognize(
        frame,
        languages: const <String>['zh-Hans'],
      );
    } on Object {
      _publish(note: copy.text(CopyKey.runtimeRecogniseFailed));
      return;
    }
    final RecognisedCapture capture = groupRecognisedLines(
      recognised,
      frame: frame,
    );
    if (capture.lines.isEmpty) {
      _publish(note: copy.text(CopyKey.runtimeNothingRecognised));
      return;
    }
    final ChatUiSnapshot snapshot = ChatUiSnapshot(
      conversation: _latest?.conversation ?? ConversationRef.none,
      lines: capture.lines,
      capturedAt: DateTime.now(),
      note: copy.text(
        capture.sidesSplit
            ? CopyKey.panelNoteSidesGuessed
            : CopyKey.panelNoteSidesNotSplit,
      ),
    );
    _latest = snapshot;
    _latestSource = 'ocr';
    _publish(
      analysed: snapshot.conversation,
      live: snapshot.conversation,
      note: snapshot.note,
    );
  }

  /// The platform's own words for a frame that was refused.
  ///
  /// Android's `ScreenCapture` writes these to be shown unchanged — they name the
  /// cause and, where there is one, the remedy — and [CaptureFailed.code] is
  /// deliberately untranslated, so passing the sentence through keeps both the
  /// taxonomy and the advice. A sentence of our own here would be the only thing
  /// standing between the user and the reason.
  String _refusal(String reason) => copy
      .text(CopyKey.runtimeCaptureRefused)
      .replaceAll('{reason}', reason);

  /// The one platform error that has a remedy of its own.
  ///
  /// The contract reserves exceptions for the platform being unable to answer
  /// at all, and on Android that is nearly always the accessibility service
  /// being off — the bridge cannot take a picture without it, so it raises this
  /// code before any capture machinery runs. Answering with the generic
  /// sentence would name a symptom the user cannot act on («确认已开启无障碍»
  /// when the panel cannot tell them *that* is what is wrong), which is what
  /// cost a code-reading session the first time this happened.
  ///
  /// Every other platform error keeps the generic sentence: the bridge's
  /// messages are written for a developer, not for the panel.
  String _platformRefusal(PlatformException failure) =>
      failure.code == _serviceUnavailable
          ? copy.text(CopyKey.runtimeCaptureServiceOff)
          : copy.text(CopyKey.runtimeCaptureFailed);

  /// `MiaotouAndroidPlugin.withCaptureService`, which is the only place in the
  /// three ports that raises it.
  static const String _serviceUnavailable = 'accessibility_service_unavailable';

  Future<void> _analyze({required bool manual}) async {
    if (_analysing) {
      if (!manual) {
        _pendingAutomaticAnalysis = true;
      }
      return;
    }
    _analysing = true;
    try {
      final ChatUiSnapshot? read = await capabilities.uiTreeReader
          .readActiveChat();
      final ChatUiSnapshot? current = read ?? _latest;
      // A fresh tree read is a tree read; falling back to [_latest] means the
      // foreground application has no adapter, so the snapshot in hand is
      // whatever produced it — including a manual capture.
      _sourceOfCurrent = read == null ? _latestSource : 'accessibility';
      if (current == null || current.lines.isEmpty) {
        _publish(note: copy.text(CopyKey.runtimeNoConversation));
        return;
      }
      _latest = current;
      final bool hadAdvice = _advice != null;
      _advice = null;
      _analysedSnapshot = null;
      if (hadAdvice) {
        onAdvice?.call(null);
      }
      _publish(
        analysed: current.conversation,
        live: current.conversation,
        note: copy.text(CopyKey.runtimeAnalysing),
      );
      final ModelSettings settings = await ModelSettings.load(
        capabilities.preferences,
        capabilities.secretStore,
      );
      if (_customAnalyzer == null && !settings.isReady) {
        _publish(
          analysed: current.conversation,
          live: current.conversation,
          note: copy.text(CopyKey.runtimeConfigureModels),
        );
        return;
      }
      final Advice result = await (_customAnalyzer ?? _analyzeDomain)(
        current,
        settings,
      );
      _analysedSnapshot = current;
      _advice = result;
      onAdvice?.call(result);
      _publish(
        analysed: current.conversation,
        live: _latest?.conversation ?? current.conversation,
        advice: result,
        note: current.note,
      );
    } on DomainException catch (error) {
      _publish(note: error.message);
    } on Object {
      _publish(note: copy.text(CopyKey.runtimeAnalysisFailed));
    } finally {
      _analysing = false;
      if (_pendingAutomaticAnalysis) {
        _pendingAutomaticAnalysis = false;
        unawaited(_analyze(manual: false));
      }
    }
  }

  Future<Advice> _analyzeDomain(
    ChatUiSnapshot input,
    ModelSettings settings,
  ) async {
    final SharedMaterial material = _material ??= await SharedMaterial.load(
      capabilities.sharedPayload,
    );
    final Snapshot snapshot = Snapshot.fromCaptured(
      title: input.conversation.title,
      source: _sourceOfCurrent,
      lines: <CapturedLine>[
        for (final ChatLine line in input.lines)
          CapturedLine(
            speaker: line.speaker,
            text: line.text,
            // A photographed line is neither unscored nor trustworthy. The
            // domain reads a null confidence as "not from OCR" and a non-finite
            // one as below the threshold, and the second is the truth here: ML
            // Kit's Chinese recogniser reports no per-line score at all, so the
            // engine cannot vouch for this text and must not be made to.
            confidence: _sourceOfCurrent == 'ocr' ? double.nan : null,
          ),
      ],
    );
    final Profile profile =
        Profile.empty(
              id: input.conversation.toString(),
              label: input.conversation.title ?? '',
            )
            .withValue('goal', settings.goal)
            .withValue('background', settings.relationshipBackground);
    final String scene = material.vocabulary.relationship.sceneFor(
      profile.goal,
    );
    final ReplyPreferences preferences = material.vocabulary.reply.resolve(
      tone: settings.tone,
      length: settings.length,
      count: settings.candidateCount,
    );
    final StrategyRoute? strategyRoute = switch (settings.strategyProvider) {
      StrategyProvider.none => null,
      StrategyProvider.jev => StrategyRoute(
        engine: StrategyEngine.jev,
        model: settings.strategyModel,
      ),
      StrategyProvider.deepseek => StrategyRoute(
        engine: StrategyEngine.deepseek,
        model: settings.strategyModel,
      ),
    };
    final ConfiguredModelTransport transport = ConfiguredModelTransport(
      settings,
      copy: copy,
    );
    try {
      return await analyzeSnapshot(
        transport: transport,
        material: material,
        snapshot: snapshot,
        scene: scene,
        background: buildBackground(
          profile: profile,
          snapshotText: snapshot.transcript,
        ),
        replyModel: settings.replyModel,
        strategyRoute: strategyRoute,
        preferences: preferences,
      );
    } finally {
      transport.close();
    }
  }

  Future<void> _copy(String? text) async {
    if (text == null || text.isEmpty) {
      return;
    }
    await clipboardWrite(text);
    _publish(note: copy.text(CopyKey.runtimeCopied));
  }

  Future<void> _fill(String? text) async {
    final ChatUiSnapshot? analysed = _analysedSnapshot;
    if (text == null || text.isEmpty || analysed == null) {
      return;
    }
    final ChatUiSnapshot? current = await capabilities.uiTreeReader
        .readActiveChat();
    if (current == null ||
        current.conversation != analysed.conversation ||
        current.signature() != analysed.signature()) {
      _publish(
        live: current?.conversation ?? _latest?.conversation,
        note: copy.text(CopyKey.runtimeConversationChanged),
      );
      return;
    }
    final String? target = await capabilities.screenCapture.findTargetWindow();
    if (target == null) {
      _publish(note: copy.text(CopyKey.runtimeConversationChanged));
      return;
    }
    final InjectResult result = await capabilities.textInject.inject(
      text,
      target: InjectTarget(windowId: target),
    );
    if (result.verifiedLanding && result.observedText == text) {
      _publish(note: copy.text(CopyKey.runtimeFilled));
      return;
    }
    await clipboardWrite(text);
    _publish(note: copy.text(CopyKey.runtimeFillUnverified));
  }

  void _publish({
    ConversationRef? analysed,
    ConversationRef? live,
    Advice? advice,
    String? note,
  }) {
    final PanelFrame current = panel.current;
    panel.publish(
      PanelFrame(
        analysed: analysed ?? current.analysed,
        live: live ?? _latest?.conversation ?? current.live,
        advice: advice ?? _advice,
        note: note,
        appNames: current.appNames,
      ),
    );
  }

  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    await _snapshotSubscription?.cancel();
    await _commandSubscription?.cancel();
  }
}
