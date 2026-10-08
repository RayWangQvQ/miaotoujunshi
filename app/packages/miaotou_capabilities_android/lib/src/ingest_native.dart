import 'dart:async';

import 'package:flutter/services.dart';
import 'package:miaotou_capabilities/miaotou_capabilities.dart';

sealed class AndroidIngestEvent {
  const AndroidIngestEvent();
}

final class AndroidSnapshotEvent extends AndroidIngestEvent {
  const AndroidSnapshotEvent(this.snapshot);

  final ChatUiSnapshot snapshot;
}

/// The service saw the foreground application change, and this is whose
/// conversation it is now.
///
/// It carries the reference and nothing a screen would print: the label's
/// fallback order is the domain's rule, and the service's job is only to have
/// resolved the app's *display name* onto the reference while it had the
/// `Context` to ask with (ADR-0028).
final class AndroidConversationEvent extends AndroidIngestEvent {
  const AndroidConversationEvent({
    required this.current,
    required this.bound,
    required this.readOnly,
  });

  final ConversationRef current;
  final ConversationRef? bound;

  /// Computed by the accessibility service. The panel must only render it.
  final bool readOnly;
}

final class AndroidCaptureErrorEvent extends AndroidIngestEvent {
  const AndroidCaptureErrorEvent({required this.code, required this.message});

  final int code;
  final String message;
}

enum AndroidOverlayFlag { visible, focusable }

abstract interface class AndroidIngestNative {
  Stream<AndroidIngestEvent> get events;

  Future<ChatUiSnapshot?> readActiveChat();

  Future<void> bindConversation(ConversationRef conversation);

  Future<void> setOverlayFlag(AndroidOverlayFlag flag, bool value);

  Future<void> hideForCapture();

  Future<void> restoreAfterCapture();

  Future<String?> findTargetWindow();

  Future<CaptureOutcome> capture({String? targetWindowId});

  Future<List<OcrLine>> recognize(
    CaptureFrame frame, {
    required List<String> languages,
  });

  Future<InjectResult> inject(String text, {required InjectTarget target});
}

final class MethodChannelAndroidIngestNative implements AndroidIngestNative {
  MethodChannelAndroidIngestNative({
    MethodChannel? control,
    EventChannel? ingest,
  }) : _control = control ?? const MethodChannel(controlChannelName),
       _ingest = ingest ?? const EventChannel(ingestChannelName);

  static const String controlChannelName = 'miaotou/control';
  static const String ingestChannelName = 'miaotou/ingest';

  final MethodChannel _control;
  final EventChannel _ingest;

  @override
  late final Stream<AndroidIngestEvent> events = _ingest
      .receiveBroadcastStream()
      .map(_decodeEvent);

  @override
  Future<ChatUiSnapshot?> readActiveChat() async {
    final Object? raw = await _control.invokeMethod<Object?>('readActiveChat');
    return raw == null ? null : _decodeSnapshot(_map(raw, 'snapshot'));
  }

  @override
  Future<void> bindConversation(ConversationRef conversation) =>
      _control.invokeMethod<void>(
        'bindConversation',
        _encodeConversation(conversation),
      );

  @override
  Future<void> setOverlayFlag(AndroidOverlayFlag flag, bool value) =>
      _control.invokeMethod<void>('setOverlayFlag', <String, Object?>{
        'flag': flag.name,
        'value': value,
      });

  @override
  Future<void> hideForCapture() =>
      _control.invokeMethod<void>('hideForCapture');

  @override
  Future<void> restoreAfterCapture() => _control.invokeMethod<void>('restore');

  @override
  Future<String?> findTargetWindow() =>
      _control.invokeMethod<String>('findTargetWindow');

  @override
  Future<CaptureOutcome> capture({String? targetWindowId}) async {
    final Map<Object?, Object?> raw = _map(
      await _control.invokeMethod<Object?>('capture', <String, Object?>{
        'targetWindowId': ?targetWindowId,
      }),
      'capture outcome',
    );
    if (raw['ok'] != true) {
      return CaptureFailed(
        code: _integer(raw, 'code'),
        message: _string(raw, 'message'),
      );
    }
    final Uint8List pixels = switch (raw['pixels']) {
      final Uint8List bytes => bytes,
      final List<int> bytes => Uint8List.fromList(bytes),
      _ => throw const FormatException('capture pixels must be bytes'),
    };
    return CaptureOk(
      CaptureFrame(
        pixels: pixels,
        width: _integer(raw, 'width'),
        height: _integer(raw, 'height'),
        scaleX: _number(raw, 'scaleX'),
        scaleY: _number(raw, 'scaleY'),
        originX: _number(raw, 'originX'),
        originY: _number(raw, 'originY'),
      ),
    );
  }

  @override
  Future<List<OcrLine>> recognize(
    CaptureFrame frame, {
    required List<String> languages,
  }) async {
    final List<Object?> raw = _list(
      await _control.invokeMethod<Object?>('recognize', <String, Object?>{
        'pixels': frame.pixels,
        'width': frame.width,
        'height': frame.height,
        'scaleX': frame.scaleX,
        'scaleY': frame.scaleY,
        'originX': frame.originX,
        'originY': frame.originY,
        'languages': languages,
      }),
      'OCR lines',
    );
    return raw
        .map((Object? value) {
          final Map<Object?, Object?> line = _map(value, 'OCR line');
          return OcrLine(
            text: _string(line, 'text'),
            bounds: _decodeRect(_map(line['bounds'], 'OCR bounds')),
            confidence: _number(line, 'confidence'),
          );
        })
        .toList(growable: false);
  }

  @override
  Future<InjectResult> inject(
    String text, {
    required InjectTarget target,
  }) async {
    final Map<Object?, Object?> raw = _map(
      await _control.invokeMethod<Object?>('inject', <String, Object?>{
        'text': text,
        'targetWindowId': target.windowId,
      }),
      'inject result',
    );
    return raw['verifiedLanding'] == true
        ? InjectResult.verified(_string(raw, 'observedText'))
        : InjectResult.unverified(_nullableString(raw, 'reason'));
  }

  static AndroidIngestEvent _decodeEvent(Object? value) {
    final Map<Object?, Object?> raw = _map(value, 'ingest event');
    return switch (raw['kind']) {
      'snapshot' => AndroidSnapshotEvent(
        _decodeSnapshot(_map(raw['snapshot'], 'snapshot')),
      ),
      'conversation' => AndroidConversationEvent(
        current: _decodeConversation(_map(raw['current'], 'current')),
        bound: raw['bound'] == null
            ? null
            : _decodeConversation(_map(raw['bound'], 'bound')),
        readOnly: raw['readOnly'] == true,
      ),
      'captureError' => AndroidCaptureErrorEvent(
        code: _integer(raw, 'code'),
        message: _string(raw, 'message'),
      ),
      final Object? kind => throw FormatException(
        'unknown Android ingest event $kind',
      ),
    };
  }

  static ChatUiSnapshot _decodeSnapshot(Map<Object?, Object?> raw) =>
      ChatUiSnapshot(
        conversation: _decodeConversation(
          _map(raw['conversation'], 'conversation'),
        ),
        lines: _list(raw['lines'], 'lines')
            .map((Object? value) {
              final Map<Object?, Object?> line = _map(value, 'chat line');
              return ChatLine(
                speaker: _speaker(_string(line, 'speaker')),
                text: _string(line, 'text'),
                bounds: line['bounds'] == null
                    ? null
                    : _decodeRect(_map(line['bounds'], 'line bounds')),
              );
            })
            .toList(growable: false),
        unreadBubbles: _list(raw['unreadBubbles'], 'unread bubbles')
            .map((Object? value) {
              final Map<Object?, Object?> bubble = _map(value, 'unread bubble');
              return UnreadBubble(
                bounds: _decodeRect(_map(bubble['bounds'], 'bubble bounds')),
                speaker: _speaker(_string(bubble, 'speaker')),
              );
            })
            .toList(growable: false),
        capturedAt: DateTime.fromMillisecondsSinceEpoch(
          _integer(raw, 'capturedAtMs'),
          isUtc: true,
        ),
        note: _nullableString(raw, 'note'),
      );

  static Map<String, Object?> _encodeConversation(ConversationRef ref) =>
      <String, Object?>{
        'packageName': ref.packageName,
        if (ref.appName != null) 'appName': ref.appName,
        if (ref.title != null) 'title': ref.title,
      };

  static ConversationRef _decodeConversation(Map<Object?, Object?> raw) =>
      ConversationRef(
        packageName: _string(raw, 'packageName'),
        appName: _nullableString(raw, 'appName'),
        title: _nullableString(raw, 'title'),
      );

  static ScreenRect _decodeRect(Map<Object?, Object?> raw) => ScreenRect(
    left: _number(raw, 'left'),
    top: _number(raw, 'top'),
    right: _number(raw, 'right'),
    bottom: _number(raw, 'bottom'),
  );

  static Speaker _speaker(String value) => switch (value) {
    'me' => Speaker.me,
    'other' => Speaker.other,
    'unknown' => Speaker.unknown,
    _ => throw FormatException('unknown speaker $value'),
  };

  static Map<Object?, Object?> _map(Object? value, String name) {
    if (value is! Map<Object?, Object?>) {
      throw FormatException('$name must be a map');
    }
    return value;
  }

  static List<Object?> _list(Object? value, String name) {
    if (value is! List<Object?>) {
      throw FormatException('$name must be a list');
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

  static String? _nullableString(Map<Object?, Object?> map, String key) {
    final Object? value = map[key];
    if (value == null || value is String) {
      return value as String?;
    }
    throw FormatException('$key must be a string or null');
  }

  static int _integer(Map<Object?, Object?> map, String key) {
    final Object? value = map[key];
    if (value is! int) {
      throw FormatException('$key must be an integer');
    }
    return value;
  }

  static double _number(Map<Object?, Object?> map, String key) {
    final Object? value = map[key];
    if (value is! num) {
      throw FormatException('$key must be a number');
    }
    return value.toDouble();
  }
}
