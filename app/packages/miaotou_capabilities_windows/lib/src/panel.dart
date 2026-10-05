import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:miaotou_capabilities/miaotou_capabilities.dart';

import 'panel_native.dart';

abstract interface class WindowsPanelPositionStore {
  Future<WindowsPanelPosition?> read();

  Future<void> write(WindowsPanelPosition position);
}

final class WindowsPanelPosition {
  const WindowsPanelPosition({required this.x, required this.y});

  final double x;
  final double y;
}

final class FileWindowsPanelPositionStore implements WindowsPanelPositionStore {
  FileWindowsPanelPositionStore({File? file}) : _file = file ?? _defaultFile();

  final File _file;

  static File _defaultFile() {
    final String? root =
        Platform.environment['LOCALAPPDATA'] ??
        Platform.environment['USERPROFILE'];
    if (root == null || root.isEmpty) {
      throw StateError('Windows has no local application-data directory');
    }
    return File(
      '$root${Platform.pathSeparator}妙投军师'
      '${Platform.pathSeparator}panel-placement.json',
    );
  }

  @override
  Future<WindowsPanelPosition?> read() async {
    if (!await _file.exists()) {
      return null;
    }
    final Object? decoded = jsonDecode(await _file.readAsString());
    if (decoded is! Map<Object?, Object?>) {
      throw const FormatException('panel placement must be a JSON object');
    }
    return WindowsPanelPosition(
      x: _finite(decoded, 'x'),
      y: _finite(decoded, 'y'),
    );
  }

  @override
  Future<void> write(WindowsPanelPosition position) async {
    await _file.parent.create(recursive: true);
    final File temporary = File('${_file.path}.tmp');
    await temporary.writeAsString(
      jsonEncode(<String, double>{'x': position.x, 'y': position.y}),
      flush: true,
    );
    if (await _file.exists()) {
      await _file.delete();
    }
    await temporary.rename(_file.path);
  }
}

double _finite(Map<Object?, Object?> map, String key) {
  final Object? value = map[key];
  if (value is! num || !value.toDouble().isFinite) {
    throw FormatException('panel placement $key must be finite');
  }
  return value.toDouble();
}

final class WindowsFloatingPanel implements FloatingPanel {
  WindowsFloatingPanel(
    this._native, {
    PanelPositionMemory? memory,
    this.hideSettle = const Duration(milliseconds: 120),
  }) : _memory = memory ?? PanelPositionMemory();

  final WindowsPanelNative _native;
  final PanelPositionMemory _memory;
  final Duration hideSettle;

  bool _upBeforeCapture = false;
  @override
  Future<void> show({required PanelPlacement placement}) async {
    ScreenRect? at;
    if (placement.anchor == PanelAnchor.free) {
      final PanelGeometry geometry = await _native.panelGeometry();
      at = _memory.resolve(
        placement: placement,
        screen: geometry.screen,
        size: ScreenRect.fromLTWH(
          0,
          0,
          placement.width ?? geometry.window.width,
          placement.height ?? geometry.window.height,
        ),
      );
    }
    await _native.showPanel(placement: placement, at: at);
  }

  @override
  Future<void> hide() => _native.hidePanel();

  @override
  Future<void> hideForCapture() async {
    _upBeforeCapture = await _native.hidePanel();
    if (_upBeforeCapture) {
      await Future<void>.delayed(hideSettle);
    }
  }

  @override
  Future<void> restoreAfterCapture() async {
    if (!_upBeforeCapture) {
      return;
    }
    _upBeforeCapture = false;
    await _native.restorePanel();
  }

  @override
  Future<void> setFocusable(bool value) => _native.setPanelFocusable(value);

  @override
  late final Stream<PanelEvent> events = _reduce();

  Stream<PanelEvent> _reduce() {
    final StreamController<PanelEvent> out =
        StreamController<PanelEvent>.broadcast();
    _native.events.listen((NativeWindowsPanelEvent event) async {
      switch (event) {
        case NativeWindowsPanelDragged(:final window, :final screen):
          final ScreenRect landed = EdgeSnap.snap(window, screen);
          _memory.remember(landed);
          if (landed != window) {
            await _native.showPanel(
              placement: const PanelPlacement(anchor: PanelAnchor.free),
              at: landed,
            );
          }
          out.add(PanelDragged(x: landed.left, y: landed.top));
      }
    }, onError: out.addError);
    return out.stream;
  }
}
