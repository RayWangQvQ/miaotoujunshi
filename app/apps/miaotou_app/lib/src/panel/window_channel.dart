import 'dart:async';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/services.dart';
import 'package:miaotou_capabilities/miaotou_capabilities.dart';
import 'package:miaotou_domain/miaotou_domain.dart';

import 'protocol.dart';

const String _channelName = 'miaotoujunshi/windows/panel-protocol';
const String _androidBootstrapName = 'miaotoujunshi/android/panel-bootstrap';
const String _androidChannelName = 'miaotoujunshi/android/panel-protocol';

enum AndroidPanelEngineRole { main, panel }

final class AndroidPanelBootstrap {
  AndroidPanelBootstrap({
    MethodChannel? channel,
    this.retryDelay = const Duration(milliseconds: 20),
    this.attempts = 20,
  }) : _channel = channel ?? const MethodChannel(_androidBootstrapName);

  final MethodChannel _channel;
  final Duration retryDelay;
  final int attempts;

  Future<AndroidPanelEngineRole> role() async {
    Object? lastError;
    for (int attempt = 0; attempt < attempts; attempt++) {
      try {
        final String? raw = await _channel.invokeMethod<String>('whichEngine');
        return switch (raw) {
          'main' => AndroidPanelEngineRole.main,
          'panel' => AndroidPanelEngineRole.panel,
          _ => throw StateError(
            'the Android host reported unknown engine "$raw"',
          ),
        };
      } on MissingPluginException catch (error) {
        lastError = error;
        await Future<void>.delayed(retryDelay);
      }
    }
    throw StateError(
      'the Android panel host did not register its bootstrap channel after '
      '$attempts attempts: $lastError',
    );
  }

  Future<void> markResumed() => _channel.invokeMethod<void>('appResumed');
}

final class AndroidPanelMainChannel {
  AndroidPanelMainChannel({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(_androidChannelName);

  final MethodChannel _channel;
  final StreamController<PanelCommand> _commands =
      StreamController<PanelCommand>.broadcast();

  Stream<PanelCommand> get commands => _commands.stream;

  Future<void> initialize() async {
    _channel.setMethodCallHandler((MethodCall call) async {
      if (call.method != 'command') {
        throw MissingPluginException(
          'Unknown Android panel call ${call.method}',
        );
      }
      _commands.add(PanelWireCodec.decodeCommand(call.arguments));
    });
  }

  Future<void> push(PanelFrame frame) =>
      _channel.invokeMethod<void>('frame', PanelWireCodec.encodeFrame(frame));
}

final class AndroidPanelViewChannel implements PanelChannel {
  AndroidPanelViewChannel({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(_androidChannelName);

  final MethodChannel _channel;
  final StreamController<PanelFrame> _frames =
      StreamController<PanelFrame>.broadcast();

  Future<void> initialize() async {
    _channel.setMethodCallHandler((MethodCall call) async {
      if (call.method != 'frame') {
        throw MissingPluginException('Unknown main-engine call ${call.method}');
      }
      _frames.add(PanelWireCodec.decodeFrame(call.arguments));
    });
    await _channel.invokeMethod<void>('panelReady');
  }

  Future<void> setExpanded(bool expanded) => _channel.invokeMethod<void>(
    'setExpanded',
    <String, Object?>{'value': expanded},
  );

  Future<void> startDragging() => _channel.invokeMethod<void>('startDragging');

  Future<void> setFocusable(bool focusable) => _channel.invokeMethod<void>(
    'setFocusable',
    <String, Object?>{'value': focusable},
  );

  @override
  Stream<PanelFrame> get frames => _frames.stream;

  @override
  void send(PanelCommand command) {
    unawaited(
      _channel.invokeMethod<void>(
        'command',
        PanelWireCodec.encodeCommand(command),
      ),
    );
  }
}

final class WindowsPanelMainChannel {
  WindowsPanelMainChannel({WindowMethodChannel? channel})
    : _channel = channel ?? const WindowMethodChannel(_channelName);

  final WindowMethodChannel _channel;
  final StreamController<PanelCommand> _commands =
      StreamController<PanelCommand>.broadcast();

  Stream<PanelCommand> get commands => _commands.stream;

  Future<void> initialize() =>
      _channel.setMethodCallHandler((MethodCall call) async {
        if (call.method != 'command') {
          throw MissingPluginException('Unknown panel call ${call.method}');
        }
        _commands.add(PanelWireCodec.decodeCommand(call.arguments));
      });

  Future<void> push(PanelFrame frame) =>
      _channel.invokeMethod<void>('frame', PanelWireCodec.encodeFrame(frame));
}

final class WindowsPanelViewChannel implements PanelChannel {
  WindowsPanelViewChannel({WindowMethodChannel? channel})
    : _channel = channel ?? const WindowMethodChannel(_channelName);

  final WindowMethodChannel _channel;
  final StreamController<PanelFrame> _frames =
      StreamController<PanelFrame>.broadcast();

  Future<void> initialize() => _channel.setMethodCallHandler((
    MethodCall call,
  ) async {
    if (call.method != 'frame') {
      throw MissingPluginException('Unknown main-window call ${call.method}');
    }
    _frames.add(PanelWireCodec.decodeFrame(call.arguments));
  });

  @override
  Stream<PanelFrame> get frames => _frames.stream;

  @override
  void send(PanelCommand command) {
    unawaited(
      _channel.invokeMethod<void>(
        'command',
        PanelWireCodec.encodeCommand(command),
      ),
    );
  }
}

final class PanelWireCodec {
  const PanelWireCodec._();

  static Map<String, Object?> encodeFrame(PanelFrame frame) =>
      <String, Object?>{
        'analysed': _encodeReference(frame.analysed),
        if (frame.live != null) 'live': _encodeReference(frame.live!),
        if (frame.advice != null) 'advice': frame.advice!.toJson(),
        if (frame.note != null) 'note': frame.note,
        'appNames': frame.appNames,
      };

  static PanelFrame decodeFrame(Object? value) {
    final Map<Object?, Object?> map = _map(value, 'panel frame');
    return PanelFrame(
      analysed: _decodeReference(map['analysed']),
      live: map['live'] == null ? null : _decodeReference(map['live']),
      advice: map['advice'] == null ? null : _decodeAdvice(map['advice']),
      note: map['note'] as String?,
      appNames: _stringMap(map['appNames'], 'appNames'),
    );
  }

  static Map<String, Object?> encodeCommand(PanelCommand command) =>
      <String, Object?>{
        'kind': command.kind.name,
        if (command.candidateIndex != null)
          'candidateIndex': command.candidateIndex,
        if (command.text != null) 'text': command.text,
      };

  static PanelCommand decodeCommand(Object? value) {
    final Map<Object?, Object?> map = _map(value, 'panel command');
    final String kind = _string(map, 'kind');
    final PanelCommandKind commandKind = PanelCommandKind.values.firstWhere(
      (PanelCommandKind candidate) => candidate.name == kind,
      orElse: () => throw FormatException('unknown panel command $kind'),
    );
    final Object? rawIndex = map['candidateIndex'];
    if (rawIndex != null && rawIndex is! int) {
      throw const FormatException('candidateIndex must be an integer');
    }
    final Object? rawText = map['text'];
    if (rawText != null && rawText is! String) {
      throw const FormatException('text must be a string');
    }
    return PanelCommand(
      commandKind,
      candidateIndex: rawIndex as int?,
      text: rawText as String?,
    );
  }

  static Map<String, Object?> _encodeReference(ConversationRef reference) =>
      <String, Object?>{
        'packageName': reference.packageName,
        if (reference.title != null) 'title': reference.title,
      };

  static ConversationRef _decodeReference(Object? value) {
    final Map<Object?, Object?> map = _map(value, 'conversation reference');
    return ConversationRef(
      packageName: _string(map, 'packageName'),
      title: map['title'] as String?,
    );
  }

  static Advice _decodeAdvice(Object? value) {
    final Map<Object?, Object?> map = _map(value, 'advice');
    final Object? rawCandidates = map['candidates'];
    if (rawCandidates is! List<Object?>) {
      throw const FormatException('advice candidates must be a list');
    }
    final String? rawRanking = map['ranking_status'] as String?;
    return Advice(
      support: _string(map, 'support'),
      facts: _strings(map['facts'], 'facts'),
      hypotheses: _strings(map['hypotheses'], 'hypotheses'),
      unknowns: _strings(map['unknowns'], 'unknowns'),
      intent: map['intent'] as String?,
      intentConfidence: (map['intent_confidence'] as num?)?.toDouble(),
      strategy: _string(map, 'strategy'),
      recommendation: _string(map, 'recommendation'),
      nextStep: _string(map, 'next_step'),
      stopCondition: _string(map, 'stop_condition'),
      question: _string(map, 'question'),
      candidates: <Candidate>[
        for (final Object? raw in rawCandidates) _decodeCandidate(raw),
      ],
      rankingStatus: rawRanking == null
          ? null
          : RankingStatus.values.firstWhere(
              (RankingStatus status) => status.wireName == rawRanking,
              orElse: () =>
                  throw FormatException('unknown ranking status $rawRanking'),
            ),
      strategyDecision: map['strategy_decision'] == null
          ? null
          : _decodeStrategyDecision(map['strategy_decision']),
    );
  }

  static Candidate _decodeCandidate(Object? value) {
    final Map<Object?, Object?> map = _map(value, 'candidate');
    return Candidate(
      text: _string(map, 'text'),
      reason: _string(map, 'reason'),
      tradeoff: _string(map, 'tradeoff'),
      weight: map['weight'] as int?,
    );
  }

  static StrategyDecision _decodeStrategyDecision(Object? value) {
    final Map<Object?, Object?> map = _map(value, 'strategy decision');
    final String method = _string(map, 'method');
    return StrategyDecision(
      strategy: _string(map, 'strategy'),
      confidence: (map['confidence'] as num?)?.toDouble(),
      probabilities: <String, double>{
        for (final MapEntry<String, Object?> entry in _stringObjectMap(
          map['probabilities'],
          'probabilities',
        ).entries)
          entry.key: (entry.value as num).toDouble(),
      },
      model: _string(map, 'model'),
      method: StrategyMethod.values.firstWhere(
        (StrategyMethod candidate) => candidate.wireName == method,
        orElse: () => throw FormatException('unknown strategy method $method'),
      ),
      evidence: _stringObjectMap(map['evidence'], 'evidence'),
    );
  }

  static Map<Object?, Object?> _map(Object? value, String name) {
    if (value is! Map<Object?, Object?>) {
      throw FormatException('$name must be a map');
    }
    return value;
  }

  static String _string(Map<Object?, Object?> map, String key) {
    final Object? value = map[key];
    if (value is! String) {
      throw FormatException('$key must be a string');
    }
    return value;
  }

  static List<String> _strings(Object? value, String name) {
    if (value is! List<Object?> ||
        value.any((Object? item) => item is! String)) {
      throw FormatException('$name must be a string list');
    }
    return value.cast<String>();
  }

  static Map<String, String> _stringMap(Object? value, String name) {
    final Map<String, Object?> values = _stringObjectMap(value, name);
    if (values.values.any((Object? item) => item is! String)) {
      throw FormatException('$name values must be strings');
    }
    return values.cast<String, String>();
  }

  static Map<String, Object?> _stringObjectMap(Object? value, String name) {
    if (value is! Map<Object?, Object?> ||
        value.keys.any((Object? key) => key is! String)) {
      throw FormatException('$name must be a string-keyed map');
    }
    return value.cast<String, Object?>();
  }
}
