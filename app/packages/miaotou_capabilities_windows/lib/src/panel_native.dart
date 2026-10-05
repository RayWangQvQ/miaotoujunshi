import 'dart:async';
import 'dart:convert';
import 'dart:ffi' hide Size;

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/services.dart';
import 'package:miaotou_capabilities/miaotou_capabilities.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:window_manager/window_manager.dart';

const String windowsPanelArgumentKind = 'miaotou-panel';
const String _eventChannelPrefix = 'miaotoujunshi/windows/panel-events/';

sealed class NativeWindowsPanelEvent {
  const NativeWindowsPanelEvent();
}

final class NativeWindowsPanelDragged extends NativeWindowsPanelEvent {
  const NativeWindowsPanelDragged({required this.window, required this.screen});

  final ScreenRect window;
  final ScreenRect screen;
}

abstract interface class WindowsPanelNative {
  Future<PanelGeometry> panelGeometry();

  Future<void> showPanel({required PanelPlacement placement, ScreenRect? at});

  Future<bool> hidePanel();

  Future<void> restorePanel();

  Future<void> setPanelFocusable(bool value);

  Stream<NativeWindowsPanelEvent> get events;
}

final class PanelGeometry {
  const PanelGeometry({required this.screen, required this.window});

  final ScreenRect screen;
  final ScreenRect window;
}

/// Main-isolate end of the Windows panel window.
final class DesktopMultiWindowPanelNative implements WindowsPanelNative {
  DesktopMultiWindowPanelNative();

  final StreamController<NativeWindowsPanelEvent> _events =
      StreamController<NativeWindowsPanelEvent>.broadcast();
  WindowController? _controller;

  Future<WindowController> _window() async {
    final WindowController? existing = _controller;
    if (existing != null) {
      return existing;
    }
    final WindowController controller = await WindowController.create(
      const WindowConfiguration(
        hiddenAtLaunch: true,
        arguments: '{"kind":"miaotou-panel"}',
      ),
    );
    final WindowMethodChannel events = WindowMethodChannel(
      '$_eventChannelPrefix${controller.windowId}',
      mode: ChannelMode.unidirectional,
    );
    await events.setMethodCallHandler((MethodCall call) async {
      if (call.method != 'dragged') {
        throw MissingPluginException('Unknown panel event ${call.method}');
      }
      final Map<Object?, Object?> arguments =
          (call.arguments as Map<Object?, Object?>?) ?? <Object?, Object?>{};
      _events.add(
        NativeWindowsPanelDragged(
          window: _rect(arguments['window']),
          screen: _rect(arguments['screen']),
        ),
      );
    });
    _controller = controller;
    return controller;
  }

  @override
  Future<PanelGeometry> panelGeometry() async {
    final WindowController controller = await _window();
    final Map<Object?, Object?> result =
        (await controller.invokeMethod<Map<Object?, Object?>>('geometry')) ??
        <Object?, Object?>{};
    return PanelGeometry(
      screen: _rect(result['screen']),
      window: _rect(result['window']),
    );
  }

  @override
  Future<void> showPanel({
    required PanelPlacement placement,
    ScreenRect? at,
  }) async {
    final WindowController controller = await _window();
    await controller.invokeMethod<void>('showPanel', <String, Object?>{
      'anchor': placement.anchor.name,
      'dx': placement.dx,
      'dy': placement.dy,
      if (placement.width != null) 'width': placement.width,
      if (placement.height != null) 'height': placement.height,
      if (at != null) 'at': _rectMap(at),
    });
  }

  @override
  Future<bool> hidePanel() async {
    final WindowController controller = await _window();
    return await controller.invokeMethod<bool>('hidePanel') ?? false;
  }

  @override
  Future<void> restorePanel() async {
    final WindowController controller = await _window();
    await controller.invokeMethod<void>('restorePanel');
  }

  @override
  Future<void> setPanelFocusable(bool value) async {
    final WindowController controller = await _window();
    await controller.invokeMethod<void>('setFocusable', value);
  }

  @override
  Stream<NativeWindowsPanelEvent> get events => _events.stream;
}

/// Panel-isolate end of the native window contract.
final class WindowsPanelWindowBinding with WindowListener {
  WindowsPanelWindowBinding._(this.controller)
    : _events = WindowMethodChannel(
        '$_eventChannelPrefix${controller.windowId}',
        mode: ChannelMode.unidirectional,
      );

  final WindowController controller;
  final WindowMethodChannel _events;
  Rect? _lastVisibleBounds;
  Rect? _programmaticBounds;
  bool _focusable = false;

  static Future<WindowsPanelWindowBinding?> attachIfPanel() async {
    final WindowController controller =
        await WindowController.fromCurrentEngine();
    if (controller.arguments.isEmpty) {
      return null;
    }
    final Object? decoded = jsonDecode(controller.arguments);
    if (decoded is! Map<Object?, Object?> ||
        decoded['kind'] != windowsPanelArgumentKind) {
      return null;
    }
    final WindowsPanelWindowBinding binding = WindowsPanelWindowBinding._(
      controller,
    );
    await binding._initialize();
    return binding;
  }

  Future<void> _initialize() async {
    await windowManager.ensureInitialized();
    await windowManager.setAsFrameless();
    await windowManager.setAlwaysOnTop(true);
    await windowManager.setSkipTaskbar(true);
    await windowManager.setResizable(false);
    await windowManager.setBackgroundColor(const Color(0x00000000));
    await windowManager.setTitle('妙投军师');
    await windowManager.setSize(const Size(420, 620));
    await _setFocusable(false);
    windowManager.addListener(this);
    await controller.setWindowMethodHandler(_handleMethod);
  }

  Future<void> setExpanded(bool expanded) async {
    final Rect current = await windowManager.getBounds();
    final Rect screen = await _screenFor(current);
    final Size size = expanded ? const Size(420, 620) : const Size(56, 56);
    final bool attachedRight =
        (screen.right - current.right).abs() <
        (current.left - screen.left).abs();
    final double left = attachedRight
        ? screen.right - size.width
        : current.left.clamp(screen.left, screen.right - size.width);
    final double top = current.top.clamp(
      screen.top,
      screen.bottom - size.height,
    );
    await _setBounds(Rect.fromLTWH(left, top, size.width, size.height));
  }

  Future<void> startDragging() async {
    await windowManager.startDragging();
    await _reportDragged();
  }

  Future<void> setFocusable(bool focusable) => _setFocusable(focusable);

  Future<Object?> _handleMethod(MethodCall call) async {
    switch (call.method) {
      case 'geometry':
        return _geometry();
      case 'showPanel':
        await _show(
          (call.arguments as Map<Object?, Object?>?) ?? <Object?, Object?>{},
        );
      case 'hidePanel':
        return _hide();
      case 'restorePanel':
        await _restore();
      case 'setFocusable':
        await _setFocusable(call.arguments as bool? ?? false);
      default:
        throw MissingPluginException('Unknown panel method ${call.method}');
    }
    return null;
  }

  Future<Map<String, Object?>> _geometry() async {
    final Rect window = await windowManager.getBounds();
    final Rect screen = await _screenFor(window);
    return <String, Object?>{
      'window': _flutterRectMap(window),
      'screen': _flutterRectMap(screen),
    };
  }

  Future<void> _show(Map<Object?, Object?> arguments) async {
    final Rect current = await windowManager.getBounds();
    final Object? rawAt = arguments['at'];
    final Rect target;
    if (rawAt is Map<Object?, Object?>) {
      target = _flutterRect(rawAt);
    } else {
      final Rect screen = await _screenFor(current);
      final double width =
          (arguments['width'] as num?)?.toDouble() ?? current.width;
      final double height =
          (arguments['height'] as num?)?.toDouble() ?? current.height;
      target = _anchor(
        arguments['anchor'] as String? ?? PanelAnchor.topLeft.name,
        screen,
        Size(width, height),
        (arguments['dx'] as num?)?.toDouble() ?? 0,
        (arguments['dy'] as num?)?.toDouble() ?? 0,
      );
    }
    _lastVisibleBounds = target;
    await _setBounds(target);
    await windowManager.show(inactive: !_focusable);
  }

  Future<bool> _hide() async {
    final bool visible = await windowManager.isVisible();
    if (!visible) {
      return false;
    }
    _lastVisibleBounds = await windowManager.getBounds();
    await windowManager.hide();
    return true;
  }

  Future<void> _restore() async {
    final Rect? last = _lastVisibleBounds;
    if (last != null) {
      await _setBounds(last);
    }
    await windowManager.show(inactive: !_focusable);
  }

  Future<void> _setFocusable(bool value) async {
    _focusable = value;
    await _setNoActivate(await windowManager.getId(), !value);
    if (!value && await windowManager.isFocused()) {
      await windowManager.blur();
    }
  }

  @override
  void onWindowBlur() {
    unawaited(_setFocusable(false));
  }

  Future<void> _reportDragged() async {
    final Rect window = await windowManager.getBounds();
    if (window == _programmaticBounds) {
      _programmaticBounds = null;
      return;
    }
    final Rect screen = await _screenFor(window);
    await _events.invokeMethod<void>('dragged', <String, Object?>{
      'window': _flutterRectMap(window),
      'screen': _flutterRectMap(screen),
    });
  }

  Future<void> _setBounds(Rect bounds) async {
    _programmaticBounds = bounds;
    await windowManager.setBounds(bounds);
  }
}

Rect _anchor(String anchor, Rect screen, Size size, double dx, double dy) {
  final Offset base = switch (anchor) {
    'topRight' => Offset(screen.right - size.width, screen.top),
    'bottomLeft' => Offset(screen.left, screen.bottom - size.height),
    'bottomRight' => Offset(
      screen.right - size.width,
      screen.bottom - size.height,
    ),
    'free' => screen.topLeft,
    _ => screen.topLeft,
  };
  return (base + Offset(dx, dy)) & size;
}

Future<Rect> _screenFor(Rect window) async {
  final List<Display> displays = await screenRetriever.getAllDisplays();
  if (displays.isEmpty) {
    return Rect.zero;
  }
  final Offset centre = window.center;
  Display selected = displays.first;
  double bestDistance = double.infinity;
  for (final Display display in displays) {
    final Rect bounds = _displayRect(display);
    if (bounds.contains(centre)) {
      return bounds;
    }
    final double distance = (bounds.center - centre).distanceSquared;
    if (distance < bestDistance) {
      selected = display;
      bestDistance = distance;
    }
  }
  return _displayRect(selected);
}

Rect _displayRect(Display display) {
  final Offset position = display.visiblePosition ?? Offset.zero;
  final Size size = display.visibleSize ?? display.size;
  return position & size;
}

Map<String, Object?> _flutterRectMap(Rect rect) => <String, Object?>{
  'left': rect.left,
  'top': rect.top,
  'right': rect.right,
  'bottom': rect.bottom,
};

Rect _flutterRect(Map<Object?, Object?> map) => Rect.fromLTRB(
  (map['left'] as num).toDouble(),
  (map['top'] as num).toDouble(),
  (map['right'] as num).toDouble(),
  (map['bottom'] as num).toDouble(),
);

Map<String, Object?> _rectMap(ScreenRect rect) => <String, Object?>{
  'left': rect.left,
  'top': rect.top,
  'right': rect.right,
  'bottom': rect.bottom,
};

ScreenRect _rect(Object? value) {
  if (value is! Map<Object?, Object?>) {
    throw StateError('panel returned no rectangle');
  }
  return ScreenRect(
    left: (value['left'] as num).toDouble(),
    top: (value['top'] as num).toDouble(),
    right: (value['right'] as num).toDouble(),
    bottom: (value['bottom'] as num).toDouble(),
  );
}

typedef _GetWindowLongPtrNative = IntPtr Function(IntPtr window, Int32 index);
typedef _GetWindowLongPtrDart = int Function(int window, int index);
typedef _SetWindowLongPtrNative = IntPtr Function(
  IntPtr window,
  Int32 index,
  IntPtr value,
);
typedef _SetWindowLongPtrDart = int Function(int window, int index, int value);
typedef _SetWindowPosNative = Int32 Function(
  IntPtr window,
  IntPtr insertAfter,
  Int32 x,
  Int32 y,
  Int32 width,
  Int32 height,
  Uint32 flags,
);
typedef _SetWindowPosDart = int Function(
  int window,
  int insertAfter,
  int x,
  int y,
  int width,
  int height,
  int flags,
);

const int _gwlExStyle = -20;
const int _wsExNoActivate = 0x08000000;
const int _swpNoSize = 0x0001;
const int _swpNoMove = 0x0002;
const int _swpNoZOrder = 0x0004;
const int _swpNoActivate = 0x0010;
const int _swpFrameChanged = 0x0020;

Future<void> _setNoActivate(int window, bool value) async {
  final DynamicLibrary user32 = DynamicLibrary.open('user32.dll');
  final _GetWindowLongPtrDart getStyle = user32
      .lookupFunction<_GetWindowLongPtrNative, _GetWindowLongPtrDart>(
        'GetWindowLongPtrW',
      );
  final _SetWindowLongPtrDart setStyle = user32
      .lookupFunction<_SetWindowLongPtrNative, _SetWindowLongPtrDart>(
        'SetWindowLongPtrW',
      );
  final _SetWindowPosDart setPosition = user32
      .lookupFunction<_SetWindowPosNative, _SetWindowPosDart>('SetWindowPos');
  final int current = getStyle(window, _gwlExStyle);
  final int next = value
      ? current | _wsExNoActivate
      : current & ~_wsExNoActivate;
  setStyle(window, _gwlExStyle, next);
  setPosition(
    window,
    0,
    0,
    0,
    0,
    0,
    _swpNoSize | _swpNoMove | _swpNoZOrder | _swpNoActivate | _swpFrameChanged,
  );
}
