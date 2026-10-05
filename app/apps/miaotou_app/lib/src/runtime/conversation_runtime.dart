import 'dart:async';

import 'package:flutter/foundation.dart';
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
  /// guess in pure Dart where a fixture can pin them. The panel comes off first:
  /// it floats over the very pixels being captured (ADR-0012).
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
      final String? target = await capabilities.screenCapture
          .findTargetWindow();
      final CaptureOutcome outcome;
      await capabilities.floatingPanel.hideForCapture();
      try {
        outcome = await capabilities.screenCapture.capture(
          targetWindowId: target,
        );
      } finally {
        await capabilities.floatingPanel.restoreAfterCapture();
      }
      if (outcome is! CaptureOk) {
        _publish(note: copy.text(CopyKey.runtimeCaptureFailed));
        return;
      }
      final List<OcrLine> recognised = await capabilities.ocr.recognize(
        outcome.frame,
        languages: const <String>['zh-Hans'],
      );
      final RecognisedCapture capture = groupRecognisedLines(
        recognised,
        frame: outcome.frame,
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
    } on Object {
      _publish(note: copy.text(CopyKey.runtimeCaptureFailed));
    } finally {
      _recognising = false;
    }
  }

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
