import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:miaotou_capabilities/miaotou_capabilities.dart';
import 'package:miaotou_capabilities_android/miaotou_capabilities_android.dart';

void main() {
  test('show carries the complete placement to the native window', () async {
    final _FakeAndroidPanelNative native = _FakeAndroidPanelNative();
    addTearDown(native.close);
    final AndroidFloatingPanel panel = AndroidFloatingPanel(native: native);
    const PanelPlacement placement = PanelPlacement(
      anchor: PanelAnchor.bottomRight,
      dx: 12,
      dy: 24,
      width: 300,
      height: 380,
    );

    await panel.show(placement: placement);

    expect(native.shown, same(placement));
  });

  test('capture restores only a panel that it actually hid', () async {
    final _FakeAndroidPanelNative native = _FakeAndroidPanelNative();
    addTearDown(native.close);
    final AndroidFloatingPanel panel = AndroidFloatingPanel(
      native: native,
      hideSettle: Duration.zero,
    );

    native.visible = false;
    await panel.hideForCapture();
    await panel.restoreAfterCapture();
    expect(native.restores, 0);

    native.visible = true;
    await panel.hideForCapture();
    await panel.restoreAfterCapture();
    expect(native.restores, 1);
  });

  test('focus and native events cross the capability seam', () async {
    final _FakeAndroidPanelNative native = _FakeAndroidPanelNative();
    addTearDown(native.close);
    final AndroidFloatingPanel panel = AndroidFloatingPanel(native: native);
    final Future<PanelEvent> event = panel.events.first;

    await panel.setFocusable(true);
    native.events.add(const AndroidPanelDragged(x: 16, y: 32));

    expect(native.focusable, isTrue);
    expect(await event, isA<PanelDragged>());
  });
}

final class _FakeAndroidPanelNative implements AndroidPanelNative {
  final StreamController<AndroidPanelEvent> events =
      StreamController<AndroidPanelEvent>.broadcast();

  PanelPlacement? shown;
  bool visible = false;
  bool focusable = false;
  int restores = 0;

  Future<void> close() => events.close();

  @override
  Stream<AndroidPanelEvent> get panelEvents => events.stream;

  @override
  Future<void> showPanel(PanelPlacement placement) async {
    shown = placement;
    visible = true;
  }

  @override
  Future<bool> hidePanel() async {
    final bool wasVisible = visible;
    visible = false;
    return wasVisible;
  }

  @override
  Future<void> restorePanel() async {
    restores++;
    visible = true;
  }

  @override
  Future<void> setPanelFocusable(bool value) async {
    focusable = value;
  }
}
