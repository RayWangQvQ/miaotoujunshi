import 'dart:async';

import 'package:flutter/services.dart';
import 'package:miaotou_capabilities/miaotou_capabilities.dart';

/// The Android window operations below the [FloatingPanel] contract.
abstract interface class AndroidPanelNative {
  Future<void> showPanel(PanelPlacement placement);

  Future<bool> hidePanel();

  Future<void> restorePanel();

  Future<void> setPanelFocusable(bool value);

  Stream<AndroidPanelEvent> get panelEvents;
}

sealed class AndroidPanelEvent {
  const AndroidPanelEvent();
}

final class AndroidPanelDragged extends AndroidPanelEvent {
  const AndroidPanelDragged({required this.x, required this.y});

  final double x;
  final double y;
}

final class AndroidPanelTapped extends AndroidPanelEvent {
  const AndroidPanelTapped(this.action);

  final String action;
}

final class AndroidPanelReadOnly extends AndroidPanelEvent {
  const AndroidPanelReadOnly(this.readOnly);

  final bool readOnly;
}

/// The method/event-channel seam implemented by the hand-written Kotlin plugin.
final class MethodChannelAndroidPanelNative implements AndroidPanelNative {
  MethodChannelAndroidPanelNative({
    MethodChannel? channel,
    EventChannel? events,
  }) : _channel = channel ?? const MethodChannel(methodChannelName),
       _events = events ?? const EventChannel(eventChannelName);

  static const String methodChannelName = 'miaotoujunshi/android/panel';
  static const String eventChannelName = 'miaotoujunshi/android/panel/events';
  static const String bootstrapChannelName =
      'miaotoujunshi/android/panel-bootstrap';
  static const String protocolChannelName =
      'miaotoujunshi/android/panel-protocol';

  final MethodChannel _channel;
  final EventChannel _events;

  @override
  Future<void> showPanel(PanelPlacement placement) =>
      _channel.invokeMethod<void>('show', <String, Object?>{
        'anchor': placement.anchor.name,
        'dx': placement.dx,
        'dy': placement.dy,
        if (placement.width != null) 'width': placement.width,
        if (placement.height != null) 'height': placement.height,
      });

  @override
  Future<bool> hidePanel() async =>
      await _channel.invokeMethod<bool>('hide') ?? false;

  @override
  Future<void> restorePanel() => _channel.invokeMethod<void>('restore');

  @override
  Future<void> setPanelFocusable(bool value) => _channel.invokeMethod<void>(
    'focusable',
    <String, Object?>{'value': value},
  );

  @override
  late final Stream<AndroidPanelEvent> panelEvents = _events
      .receiveBroadcastStream()
      .map(_decodeEvent);

  static AndroidPanelEvent _decodeEvent(Object? raw) {
    if (raw is! Map<Object?, Object?>) {
      throw const FormatException('Android panel event must be a map');
    }
    return switch (raw['kind']) {
      'dragged' => AndroidPanelDragged(
        x: _number(raw, 'x'),
        y: _number(raw, 'y'),
      ),
      'tapped' => AndroidPanelTapped(_string(raw, 'action')),
      'readOnly' => AndroidPanelReadOnly(raw['value'] == true),
      final Object? kind => throw FormatException(
        'unknown Android panel event $kind',
      ),
    };
  }

  static double _number(Map<Object?, Object?> map, String key) {
    final Object? value = map[key];
    if (value is! num) {
      throw FormatException('$key must be a number');
    }
    return value.toDouble();
  }

  static String _string(Map<Object?, Object?> map, String key) {
    final Object? value = map[key];
    if (value is! String) {
      throw FormatException('$key must be a string');
    }
    return value;
  }
}
