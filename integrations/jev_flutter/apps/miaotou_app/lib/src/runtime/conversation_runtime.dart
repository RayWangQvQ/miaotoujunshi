import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:miaotou_capabilities/miaotou_capabilities.dart';
import 'package:miaotou_domain/miaotou_domain.dart';

import '../design/copy.dart';
import '../panel/protocol.dart';
import '../panel/session.dart';
import 'model_settings.dart';
import 'model_transport.dart';

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
  Advice? _advice;
  SharedMaterial? _material;
  bool _analysing = false;
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
      case PanelCommandKind.copy:
        unawaited(_copy(command.text));
      case PanelCommandKind.fill:
        unawaited(_fill(command.text));
      case PanelCommandKind.details:
      case PanelCommandKind.close:
        break;
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
      final ChatUiSnapshot? current =
          await capabilities.uiTreeReader.readActiveChat() ?? _latest;
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
      source: 'accessibility',
      lines: <CapturedLine>[
        for (final ChatLine line in input.lines)
          CapturedLine(speaker: line.speaker, text: line.text),
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
