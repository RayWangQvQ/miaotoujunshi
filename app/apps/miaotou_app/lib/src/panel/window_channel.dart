import 'dart:async';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/services.dart';
import 'package:miaotou_capabilities/miaotou_capabilities.dart';
import 'package:miaotou_domain/miaotou_domain.dart';

import 'protocol.dart';

const String _windowsChannelName = 'miaotoujunshi/windows/panel-protocol';
const String _androidChannelName = 'miaotoujunshi/android/panel-protocol';

/// The macOS panel protocol's channel name.
///
/// **Public, and the only one of the three that is.** The two desktop ports and
/// Android each write their channel name down once; macOS writes this one twice
/// — here and in `FloatingPanelHost.swift` — because the host owns both ends of
/// the relay. `panel_window_test.dart` reads this constant and the Swift to keep
/// the two in step, which it cannot do with a private name.
const String macosPanelProtocolChannelName =
    'miaotoujunshi/macos/panel-protocol';

/// Which of the two engines this process is.
enum PanelEngineRole { main, panel }

/// Asks the host which side of the panel this process is.
///
/// Android and macOS both start the panel engine **in this process**, on a fresh
/// `FlutterEngine`, and both run the same `main` the main window does — so the
/// application cannot tell the two apart by itself and asks. Windows answers the
/// same question from `desktop_multi_window`'s window arguments, which already
/// carry the kind, and therefore has no bootstrap at all.
final class PanelEngineBootstrap {
  PanelEngineBootstrap({
    required this.channelName,
    MethodChannel? channel,
    this.retryDelay = const Duration(milliseconds: 20),
    this.attempts = 20,
  }) : _channel = channel ?? MethodChannel(channelName);

  static const String androidChannelName =
      'miaotoujunshi/android/panel-bootstrap';
  static const String macosChannelName = 'miaotoujunshi/macos/panel-bootstrap';

  final String channelName;
  final MethodChannel _channel;
  final Duration retryDelay;
  final int attempts;

  /// Which engine this is.
  ///
  /// Retried, because the host registers its end of this channel in the same
  /// breath as it starts the engine: `createAndRunEngine` can reach Dart before
  /// the `MethodChannel` on the other side exists, and losing that race is not a
  /// reason to fail to start.
  Future<PanelEngineRole> role() async {
    Object? lastError;
    for (int attempt = 0; attempt < attempts; attempt++) {
      try {
        final String? raw = await _channel.invokeMethod<String>('whichEngine');
        return switch (raw) {
          'main' => PanelEngineRole.main,
          'panel' => PanelEngineRole.panel,
          _ => throw StateError('the panel host reported unknown engine "$raw"'),
        };
      } on MissingPluginException catch (error) {
        lastError = error;
        await Future<void>.delayed(retryDelay);
      }
    }
    throw StateError(
      'the panel host did not register its bootstrap channel on '
      '"$channelName" after $attempts attempts: $lastError',
    );
  }

  /// Tells the Android host that the panel engine has resumed.
  ///
  /// **Android only.** An engine the host started without a window does not get
  /// the resume callback on its own, so the host has to drive the second
  /// engine's lifecycle channel by hand. The macOS host does not implement this
  /// and is never asked.
  Future<void> markResumed() => _channel.invokeMethod<void>('appResumed');
}

/// The two values that go down, held until the panel engine says it is up.
///
/// A panel engine is a second isolate that starts when its window is created, so
/// a value pushed immediately after `show` can arrive before anything on the far
/// side is listening. Android's Kotlin host has always held the frame for that
/// reason; the desktop ports hold it on this side instead, which is the same
/// behaviour with the buffer where the two channels are.
final class PanelDownlink {
  PanelDownlink(this._send);

  final Future<void> Function(String method, Object? arguments) _send;

  PanelFrame? _frame;
  PanelAppearance? _appearance;

  Future<void> pushFrame(PanelFrame value) {
    _frame = value;
    return _send('frame', PanelWireCodec.encodeFrame(value));
  }

  Future<void> pushAppearance(PanelAppearance value) {
    _appearance = value;
    return _send('appearance', PanelWireCodec.encodeAppearance(value));
  }

  /// The panel engine has registered its handlers: give it both values, whether
  /// or not an earlier push got through.
  ///
  /// Unconditional rather than "only if something was missed", because a push
  /// that quietly failed and a push that arrived are not distinguishable from
  /// here — and sending the current value twice is a rebuild, while losing it is
  /// a panel painted with the wrong fill until the user drags the slider again.
  Future<void> flush() async {
    final PanelFrame? frame = _frame;
    if (frame != null) {
      await _send('frame', PanelWireCodec.encodeFrame(frame));
    }
    final PanelAppearance? appearance = _appearance;
    if (appearance != null) {
      await _send('appearance', PanelWireCodec.encodeAppearance(appearance));
    }
  }
}

final class AndroidPanelMainChannel implements PanelMainChannel {
  AndroidPanelMainChannel({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(_androidChannelName);

  final MethodChannel _channel;
  final StreamController<PanelCommand> _commands =
      StreamController<PanelCommand>.broadcast();

  @override
  Stream<PanelCommand> get commands => _commands.stream;

  @override
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

  @override
  Future<void> push(PanelFrame frame) =>
      _channel.invokeMethod<void>('frame', PanelWireCodec.encodeFrame(frame));

  /// No buffer here: the Android host holds both values in Kotlin and replays
  /// them when the panel engine reports that it is ready.
  @override
  Future<void> pushAppearance(PanelAppearance appearance) => _channel
      .invokeMethod<void>('appearance', PanelWireCodec.encodeAppearance(appearance));
}

final class AndroidPanelViewChannel implements PanelViewChannel {
  AndroidPanelViewChannel({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(_androidChannelName);

  final MethodChannel _channel;
  final StreamController<PanelFrame> _frames =
      StreamController<PanelFrame>.broadcast();
  final StreamController<PanelAppearance> _appearance =
      StreamController<PanelAppearance>.broadcast();

  @override
  Future<void> initialize() async {
    _channel.setMethodCallHandler((MethodCall call) async {
      switch (call.method) {
        case 'frame':
          _frames.add(PanelWireCodec.decodeFrame(call.arguments));
        case 'appearance':
          _appearance.add(PanelWireCodec.decodeAppearance(call.arguments));
        default:
          throw MissingPluginException('Unknown main-engine call ${call.method}');
      }
    });
    await _channel.invokeMethod<void>('panelReady');
  }

  @override
  Future<void> setExpanded(bool expanded) => _channel.invokeMethod<void>(
    'setExpanded',
    <String, Object?>{'value': expanded},
  );

  @override
  Future<void> startDragging() => _channel.invokeMethod<void>('startDragging');

  @override
  Future<void> setFocusable(bool focusable) => _channel.invokeMethod<void>(
    'setFocusable',
    <String, Object?>{'value': focusable},
  );

  @override
  Stream<PanelFrame> get frames => _frames.stream;

  @override
  Stream<PanelAppearance> get appearance => _appearance.stream;

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

final class WindowsPanelMainChannel implements PanelMainChannel {
  WindowsPanelMainChannel({WindowMethodChannel? channel})
    : _channel = channel ?? const WindowMethodChannel(_windowsChannelName);

  final WindowMethodChannel _channel;
  final StreamController<PanelCommand> _commands =
      StreamController<PanelCommand>.broadcast();

  late final PanelDownlink _downlink = PanelDownlink(
    (String method, Object? arguments) =>
        _channel.invokeMethod<void>(method, arguments),
  );

  @override
  Stream<PanelCommand> get commands => _commands.stream;

  @override
  Future<void> initialize() => _channel.setMethodCallHandler((
    MethodCall call,
  ) async {
    switch (call.method) {
      case 'command':
        _commands.add(PanelWireCodec.decodeCommand(call.arguments));
      case 'panelReady':
        await _downlink.flush();
      default:
        throw MissingPluginException('Unknown panel call ${call.method}');
    }
  });

  @override
  Future<void> push(PanelFrame frame) => _downlink.pushFrame(frame);

  @override
  Future<void> pushAppearance(PanelAppearance appearance) =>
      _downlink.pushAppearance(appearance);
}

final class WindowsPanelViewChannel implements PanelChannel {
  WindowsPanelViewChannel({WindowMethodChannel? channel})
    : _channel = channel ?? const WindowMethodChannel(_windowsChannelName);

  final WindowMethodChannel _channel;
  final StreamController<PanelFrame> _frames =
      StreamController<PanelFrame>.broadcast();
  final StreamController<PanelAppearance> _appearance =
      StreamController<PanelAppearance>.broadcast();

  @override
  Stream<PanelFrame> get frames => _frames.stream;

  @override
  Stream<PanelAppearance> get appearance => _appearance.stream;

  /// Windows' view channel has no window semantics to carry — the binding above
  /// supplies those — so this is [PanelChannel]'s seam plus `panelReady` and
  /// nothing else.
  Future<void> initialize() async {
    await _channel.setMethodCallHandler((MethodCall call) async {
      switch (call.method) {
        case 'frame':
          _frames.add(PanelWireCodec.decodeFrame(call.arguments));
        case 'appearance':
          _appearance.add(PanelWireCodec.decodeAppearance(call.arguments));
        default:
          throw MissingPluginException(
            'Unknown main-window call ${call.method}',
          );
      }
    });
    // The main window has been holding both values since it showed this window.
    // Without this the first frame — and the appearance beside it — is lost,
    // because the main window's push happens before this handler exists.
    await _channel.invokeMethod<void>('panelReady');
  }

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

/// The main window's end of the macOS panel protocol.
///
/// macOS is Android's shape rather than Windows': the host owns the second
/// engine, so it owns both channel ends and relays between them, which is why
/// the buffering lives in Dart here rather than in Kotlin.
final class MacosPanelMainChannel implements PanelMainChannel {
  MacosPanelMainChannel({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(macosPanelProtocolChannelName);

  final MethodChannel _channel;
  final StreamController<PanelCommand> _commands =
      StreamController<PanelCommand>.broadcast();

  late final PanelDownlink _downlink = PanelDownlink(
    (String method, Object? arguments) =>
        _channel.invokeMethod<void>(method, arguments),
  );

  @override
  Stream<PanelCommand> get commands => _commands.stream;

  @override
  Future<void> initialize() async {
    _channel.setMethodCallHandler((MethodCall call) async {
      switch (call.method) {
        case 'command':
          _commands.add(PanelWireCodec.decodeCommand(call.arguments));
        case 'panelReady':
          await _downlink.flush();
        default:
          throw MissingPluginException('Unknown panel call ${call.method}');
      }
    });
  }

  @override
  Future<void> push(PanelFrame frame) => _downlink.pushFrame(frame);

  @override
  Future<void> pushAppearance(PanelAppearance appearance) =>
      _downlink.pushAppearance(appearance);
}

final class MacosPanelViewChannel implements PanelViewChannel {
  MacosPanelViewChannel({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(macosPanelProtocolChannelName);

  final MethodChannel _channel;
  final StreamController<PanelFrame> _frames =
      StreamController<PanelFrame>.broadcast();
  final StreamController<PanelAppearance> _appearance =
      StreamController<PanelAppearance>.broadcast();

  @override
  Future<void> initialize() async {
    _channel.setMethodCallHandler((MethodCall call) async {
      switch (call.method) {
        case 'frame':
          _frames.add(PanelWireCodec.decodeFrame(call.arguments));
        case 'appearance':
          _appearance.add(PanelWireCodec.decodeAppearance(call.arguments));
        default:
          throw MissingPluginException('Unknown main-engine call ${call.method}');
      }
    });
    await _channel.invokeMethod<void>('panelReady');
  }

  @override
  Future<void> setExpanded(bool expanded) => _channel.invokeMethod<void>(
    'setExpanded',
    <String, Object?>{'value': expanded},
  );

  @override
  Future<void> startDragging() => _channel.invokeMethod<void>('startDragging');

  @override
  Future<void> setFocusable(bool focusable) => _channel.invokeMethod<void>(
    'setFocusable',
    <String, Object?>{'value': focusable},
  );

  @override
  Stream<PanelFrame> get frames => _frames.stream;

  @override
  Stream<PanelAppearance> get appearance => _appearance.stream;

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
        if (frame.note != null) 'note': _encodeNote(frame.note!),
        if (frame.transcript.isNotEmpty)
          'transcript': <Map<String, Object?>>[
            for (final PanelLine line in frame.transcript) _encodeLine(line),
          ],
        if (frame.reviewing) 'reviewing': true,
        'appNames': frame.appNames,
      };

  static PanelFrame decodeFrame(Object? value) {
    final Map<Object?, Object?> map = _map(value, 'panel frame');
    return PanelFrame(
      analysed: _decodeReference(map['analysed']),
      live: map['live'] == null ? null : _decodeReference(map['live']),
      advice: map['advice'] == null ? null : _decodeAdvice(map['advice']),
      note: map['note'] == null ? null : _decodeNote(map['note']),
      transcript: _decodeTranscript(map['transcript']),
      appNames: _stringMap(map['appNames'], 'appNames'),
      reviewing: _flag(map['reviewing'], 'reviewing'),
    );
  }

  /// The note and its optional way out, as one value.
  ///
  /// A map rather than two keys, so a note without a remedy crosses as a note
  /// rather than as a note plus an absent field the far side has to remember to
  /// read.
  static Map<String, Object?> _encodeNote(PanelNote note) => <String, Object?>{
    'text': note.text,
    if (note.remedy != null) 'remedy': _encodeRemedy(note.remedy!),
  };

  static PanelNote _decodeNote(Object? value) {
    final Map<Object?, Object?> map = _map(value, 'panel note');
    final Object? remedy = map['remedy'];
    return PanelNote(
      _string(map, 'text'),
      remedy: remedy == null ? null : _decodeRemedy(remedy),
    );
  }

  /// A way out of a note, as one map.
  ///
  /// A named shape per variant rather than a bare string, because
  /// [OpenPermissionPage] carries a value of its own and a decoder that read
  /// only the name would have to guess the rest. An unknown name is an error
  /// rather than a null, so a build that has drifted from its neighbour says so
  /// instead of drawing no button.
  static Map<String, Object?> _encodeRemedy(PanelRemedy remedy) =>
      switch (remedy) {
        OpenPermissionPage(:final PermissionKind kind) => <String, Object?>{
          'kind': 'permission',
          'permission': kind.name,
        },
        EnterReview() => const <String, Object?>{'kind': 'review'},
      };

  static PanelRemedy _decodeRemedy(Object? value) {
    final Map<Object?, Object?> map = _map(value, 'panel remedy');
    return switch (_string(map, 'kind')) {
      'permission' => OpenPermissionPage(_decodeKind(map['permission'])),
      'review' => const EnterReview(),
      final String other => throw FormatException('unknown remedy $other'),
    };
  }

  /// How the panel paints itself, as one whole percentage.
  ///
  /// Decoded through [PanelAppearance.percent] rather than a bare constructor,
  /// so a value from a future release that widened the range lands clamped
  /// instead of drawing at an alpha the fill token cannot hold.
  static Map<String, Object?> encodeAppearance(PanelAppearance appearance) =>
      <String, Object?>{'opacity': appearance.opacity};

  static PanelAppearance decodeAppearance(Object? value) {
    final Map<Object?, Object?> map = _map(value, 'panel appearance');
    final Object? opacity = map['opacity'];
    if (opacity is! int) {
      throw const FormatException('panel appearance opacity must be an integer');
    }
    return PanelAppearance.percent(opacity);
  }

  static List<PanelLine> _decodeTranscript(Object? value) {
    if (value == null) {
      return const <PanelLine>[];
    }
    if (value is! List<Object?>) {
      throw const FormatException('panel transcript must be a list');
    }
    return <PanelLine>[for (final Object? raw in value) _decodeLine(raw)];
  }

  static PanelLine _decodeLine(Object? value) {
    final Map<Object?, Object?> map = _map(value, 'panel line');
    final String speaker = _string(map, 'speaker');
    return PanelLine(
      speaker: Speaker.values.firstWhere(
        (Speaker candidate) => candidate.name == speaker,
        orElse: () => throw FormatException('unknown speaker $speaker'),
      ),
      text: _string(map, 'text'),
    );
  }

  /// One line going down, and one line coming back up in a confirmed batch.
  static Map<String, Object?> _encodeLine(PanelLine line) => <String, Object?>{
    'speaker': line.speaker.name,
    'text': line.text,
  };

  static Map<String, Object?> encodeCommand(PanelCommand command) =>
      <String, Object?>{
        'kind': command.kind.name,
        if (command.candidateIndex != null)
          'candidateIndex': command.candidateIndex,
        if (command.text != null) 'text': command.text,
        if (command.permission != null) 'permission': command.permission!.name,
        if (command.lines != null)
          'lines': <Map<String, Object?>>[
            for (final PanelLine line in command.lines!) _encodeLine(line),
          ],
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
    final Object? rawPermission = map['permission'];
    final Object? rawLines = map['lines'];
    List<PanelLine>? lines;
    if (rawLines != null) {
      if (rawLines is! List<Object?>) {
        throw const FormatException('lines must be a list');
      }
      lines = <PanelLine>[
        for (final Object? raw in rawLines) _decodeLine(raw),
      ];
    }
    return PanelCommand(
      commandKind,
      candidateIndex: rawIndex as int?,
      text: rawText as String?,
      permission: rawPermission == null ? null : _decodeKind(rawPermission),
      lines: lines,
    );
  }

  /// A permission kind by name, either on the way down or on the way back up.
  ///
  /// Shared because the same vocabulary crosses in both directions: a note says
  /// which page would fix it, and the command that opens the page names the same
  /// one. An unknown name is an error rather than a null, so a build that has
  /// drifted from its neighbour says so instead of opening nothing.
  static PermissionKind _decodeKind(Object? value) =>
      PermissionKind.values.firstWhere(
        (PermissionKind candidate) => candidate.name == value,
        orElse: () => throw FormatException('unknown permission kind $value'),
      );

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

  /// A flag that is absent when it is false.
  ///
  /// Absent is false rather than an error, which is what lets an older frame
  /// from a neighbour that has not been rebuilt yet still decode. A value that
  /// is present and is not a bool is an error, because that is drift rather
  /// than a default.
  static bool _flag(Object? value, String name) {
    if (value == null) {
      return false;
    }
    if (value is! bool) {
      throw FormatException('$name must be a bool');
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
