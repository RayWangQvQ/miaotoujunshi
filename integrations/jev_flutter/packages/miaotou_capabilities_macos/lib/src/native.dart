import 'dart:async';

import 'package:flutter/services.dart';
import 'package:miaotou_capabilities/miaotou_capabilities.dart';

/// Everything this port needs macOS to do for it, as one seam.
///
/// The boundary is a single method channel rather than a plugin class per
/// capability, for one reason: the panel is a **second Flutter engine in a second
/// `NSPanel`**, and that engine is created by the same native code that has to
/// place the window and read the drag back. Splitting it across four plugin
/// classes would mean four objects holding one window between them.
///
/// Everything above this file is pure Dart and testable without a device; this is
/// the line where the tests stop.
abstract interface class MacosNative {
  /// The chat window to capture, or null when there is none in front.
  Future<String?> findTargetWindow();

  /// One frame of [targetWindowId], or of the screen when it is null.
  Future<CaptureOutcome> capture({String? targetWindowId});

  Future<List<OcrLine>> recognize(CaptureFrame frame, {required List<String> languages});

  Future<InjectResult> inject(String text, {required InjectTarget target});

  /// Where the panel is, and how big the screen it is on is.
  ///
  /// Needed before the panel can be placed from Dart: snapping a window to an
  /// edge is arithmetic over a rectangle, and this is the only way to get one.
  Future<PanelGeometry> panelGeometry();

  /// Shows or re-places the panel. [at] wins over [placement] when it is given.
  Future<void> showPanel({required PanelPlacement placement, ScreenRect? at});

  /// Takes the panel off screen and reports whether it was on screen, so a
  /// capture can give back exactly what it took.
  Future<bool> hidePanel();

  /// Puts the panel back **where it was**.
  ///
  /// Not the same as asking to show it again: a show resolves an anchor or an
  /// offset, and a panel that was never dragged has neither, so restoring through
  /// it would move the window to the corner the moment the first capture ended.
  Future<void> restorePanel();

  /// Lets the panel take keyboard focus — and no more than that. This is the
  /// switch between "a field the user can type into" and "a ball that must never
  /// take the caret out of the chat".
  Future<void> setPanelFocusable(bool value);

  /// What the panel reports, richer than [PanelEvent] on purpose: the drag needs
  /// the window's size to be snapped, and the contract's [PanelDragged] has no
  /// room for one.
  Stream<NativePanelEvent> get events;
}

/// The panel's own rectangle and the screen it sits on.
final class PanelGeometry {
  const PanelGeometry({required this.screen, required this.window});

  final ScreenRect screen;
  final ScreenRect window;
}

/// What the native panel says, before it is reduced to the contract's three
/// events.
sealed class NativePanelEvent {
  const NativePanelEvent();
}

/// A finished drag: the whole rectangle, so the edge can be found from it.
final class NativePanelDragged extends NativePanelEvent {
  const NativePanelDragged({required this.window, required this.screen});

  final ScreenRect window;
  final ScreenRect screen;
}

final class NativePanelTapped extends NativePanelEvent {
  const NativePanelTapped(this.action);

  final String action;
}

final class NativePanelReadOnly extends NativePanelEvent {
  const NativePanelReadOnly(this.readOnly);

  final bool readOnly;
}

/// The real seam: one method channel, one event channel, one name.
///
/// The name is part of the contract between this Dart and the Swift beside it and
/// is asserted by `native_channel_test.dart`, because the failure mode of a
/// renamed method is a `MissingPluginException` at run time on a machine where
/// nobody is watching.
final class MethodChannelMacosNative implements MacosNative {
  MethodChannelMacosNative({
    MethodChannel? channel,
    EventChannel? events,
  })  : _channel = channel ?? const MethodChannel(methodChannelName),
        _events = events ?? const EventChannel(eventChannelName);

  /// Shared with the Swift side. See `macos/Classes/MiaotouMacosPlugin.swift`.
  static const String methodChannelName = 'miaotoujunshi/macos';

  /// Events flow the other way, on their own channel, so a Dart-initiated call
  /// can never be mistaken for a window-initiated one.
  static const String eventChannelName = 'miaotoujunshi/macos/events';

  final MethodChannel _channel;
  final EventChannel _events;
  StreamController<NativePanelEvent>? _controller;

  @override
  Future<String?> findTargetWindow() async =>
      await _channel.invokeMethod<String>('findTargetWindow');

  @override
  Future<CaptureOutcome> capture({String? targetWindowId}) async {
    final Map<Object?, Object?>? reply =
        await _channel.invokeMapMethod<Object?, Object?>('capture', <String, Object?>{
      'windowId': targetWindowId,
    });
    if (reply == null) {
      return const CaptureFailed(code: 1, message: '截屏失败：原生层没有回答');
    }
    if (reply['ok'] != true) {
      return CaptureFailed(
        code: (reply['code'] as int?) ?? 1,
        message: (reply['message'] as String?) ?? '截屏失败',
      );
    }
    final Uint8List pixels = (reply['pixels']! as Uint8List);
    return CaptureOk(
      CaptureFrame(
        pixels: pixels,
        width: (reply['width']! as int),
        height: (reply['height']! as int),
        scaleX: (reply['scaleX']! as num).toDouble(),
        scaleY: (reply['scaleY']! as num).toDouble(),
        originX: (reply['originX']! as num).toDouble(),
        originY: (reply['originY']! as num).toDouble(),
      ),
    );
  }

  @override
  Future<List<OcrLine>> recognize(
    CaptureFrame frame, {
    required List<String> languages,
  }) async {
    final List<Object?>? reply = await _channel.invokeListMethod<Object?>(
      'recognize',
      <String, Object?>{
        'pixels': frame.pixels,
        'width': frame.width,
        'height': frame.height,
        'languages': languages,
      },
    );
    if (reply == null) {
      return const <OcrLine>[];
    }
    return <OcrLine>[
      for (final Object? raw in reply)
        () {
          final Map<Object?, Object?> line = raw! as Map<Object?, Object?>;
          return OcrLine(
            text: line['text']! as String,
            confidence: (line['confidence']! as num).toDouble(),
            bounds: ScreenRect(
              left: (line['left']! as num).toDouble(),
              top: (line['top']! as num).toDouble(),
              right: (line['right']! as num).toDouble(),
              bottom: (line['bottom']! as num).toDouble(),
            ),
          );
        }(),
    ];
  }

  @override
  Future<InjectResult> inject(String text, {required InjectTarget target}) async {
    final Map<Object?, Object?>? reply =
        await _channel.invokeMapMethod<Object?, Object?>('inject', <String, Object?>{
      'text': text,
      'windowId': target.windowId,
    });
    if (reply == null) {
      return const InjectResult.unverified('原生层没有回答');
    }
    if (reply['verified'] != true) {
      return InjectResult.unverified((reply['reason'] as String?) ?? '无法确认草稿是否落入');
    }
    return InjectResult.verified((reply['text'] as String?) ?? '');
  }

  @override
  Future<PanelGeometry> panelGeometry() async {
    final Map<Object?, Object?> reply =
        await _channel.invokeMapMethod<Object?, Object?>('panelGeometry') ??
            const <Object?, Object?>{};
    return PanelGeometry(
      screen: _rect(reply['screen']),
      window: _rect(reply['window']),
    );
  }

  @override
  Future<void> showPanel({required PanelPlacement placement, ScreenRect? at}) async {
    await _channel.invokeMethod<void>('panel.show', <String, Object?>{
      'anchor': placement.anchor.name,
      'dx': placement.dx,
      'dy': placement.dy,
      if (at != null) ...<String, Object?>{
        'left': at.left,
        'top': at.top,
        'width': at.width,
        'height': at.height,
      },
    });
  }

  @override
  Future<bool> hidePanel() async =>
      await _channel.invokeMethod<bool>('panel.hide') ?? false;

  @override
  Future<void> restorePanel() => _channel.invokeMethod<void>('panel.restore');

  @override
  Future<void> setPanelFocusable(bool value) =>
      _channel.invokeMethod<void>('panel.focusable', <String, Object?>{'value': value});

  @override
  Stream<NativePanelEvent> get events {
    _controller ??= _startListening();
    return _controller!.stream;
  }

  StreamController<NativePanelEvent> _startListening() {
    final StreamController<NativePanelEvent> controller =
        StreamController<NativePanelEvent>.broadcast();
    _controller = controller;
    _events.receiveBroadcastStream().listen(
      (Object? raw) {
        final Map<Object?, Object?> event = raw! as Map<Object?, Object?>;
        switch (event['kind'] as String?) {
          case 'dragged':
            controller.add(NativePanelDragged(
              window: _rect(event['window']),
              screen: _rect(event['screen']),
            ));
          case 'tapped':
            controller.add(NativePanelTapped(event['action']! as String));
          case 'readOnly':
            controller.add(NativePanelReadOnly(event['value'] == true));
        }
      },
      onError: controller.addError,
    );
    return controller;
  }

  static ScreenRect _rect(Object? raw) {
    if (raw is! Map) {
      return ScreenRect.empty;
    }
    return ScreenRect(
      left: (raw['left'] as num?)?.toDouble() ?? 0,
      top: (raw['top'] as num?)?.toDouble() ?? 0,
      right: (raw['right'] as num?)?.toDouble() ?? 0,
      bottom: (raw['bottom'] as num?)?.toDouble() ?? 0,
    );
  }
}
