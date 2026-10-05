import 'dart:async';

import 'package:miaotou_capabilities/miaotou_capabilities.dart';

import 'panel_native.dart';

/// Windows' answer for the floating window.
///
/// **No store.** Where the panel was left used to live in
/// `%LOCALAPPDATA%\妙投军师\panel-placement.json`, written by this file; it is one
/// key in the application's `Preferences` now, and the application writes it
/// from the [PanelDragged] event below. Keeping the position beside the window
/// rather than beside the setting was the reason the same value had three
/// shapes on three ports (ADR-0020 decision 4).
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
