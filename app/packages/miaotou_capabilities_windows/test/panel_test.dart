import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:miaotou_capabilities/miaotou_capabilities.dart';
import 'package:miaotou_capabilities_windows/miaotou_capabilities_windows.dart';
import 'package:miaotou_capabilities_windows/testing.dart';

void main() {
  test(
    'an explicit free placement is restored inside the current screen',
    () async {
      final FakeWindowsPanelNative native = FakeWindowsPanelNative();
      final WindowsFloatingPanel panel = WindowsFloatingPanel(native);

      await panel.show(
        placement: const PanelPlacement(
          anchor: PanelAnchor.free,
          dx: 1350,
          dy: 100,
          width: 56,
          height: 56,
        ),
      );

      expect(
        native.shows.single.$2,
        const ScreenRect(left: 1384, top: 100, right: 1440, bottom: 156),
      );
    },
  );

  test('a completed drag snaps and reports the landed point', () async {
    final FakeWindowsPanelNative native = FakeWindowsPanelNative();
    final WindowsFloatingPanel panel = WindowsFloatingPanel(native);
    final Future<PanelEvent> event = panel.events.first;

    native.drag(
      window: const ScreenRect(left: 1000, top: 920, right: 1056, bottom: 976),
      screen: const ScreenRect(left: 0, top: 0, right: 1440, bottom: 900),
    );

    expect(
      await event,
      isA<PanelDragged>()
          .having((PanelDragged value) => value.x, 'x', 1384)
          .having((PanelDragged value) => value.y, 'y', 844),
    );
    expect(
      native.shows.single.$2,
      const ScreenRect(left: 1384, top: 844, right: 1440, bottom: 900),
    );
  });

  test('capture restores only a panel that was visible', () async {
    final FakeWindowsPanelNative native = FakeWindowsPanelNative();
    final WindowsFloatingPanel panel = WindowsFloatingPanel(
      native,
      hideSettle: Duration.zero,
    );

    await panel.hideForCapture();
    await panel.restoreAfterCapture();
    expect(native.restores, 0);

    native.visible = true;
    await panel.hideForCapture();
    await panel.restoreAfterCapture();
    expect(native.restores, 1);
  });

  test('focusability is an explicit runtime switch', () async {
    final FakeWindowsPanelNative native = FakeWindowsPanelNative();
    final WindowsFloatingPanel panel = WindowsFloatingPanel(native);

    await panel.setFocusable(true);
    expect(native.focusable, isTrue);
    await panel.setFocusable(false);
    expect(native.focusable, isFalse);
  });

  test('the durable placement file replaces an earlier position', () async {
    final Directory directory = await Directory.systemTemp.createTemp(
      'miaotou-panel-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final FileWindowsPanelPositionStore store = FileWindowsPanelPositionStore(
      file: File('${directory.path}/panel-placement.json'),
    );

    await store.write(const WindowsPanelPosition(x: 1, y: 2));
    await store.write(const WindowsPanelPosition(x: 10, y: 20));

    final WindowsPanelPosition? restored = await store.read();
    expect(restored?.x, 10);
    expect(restored?.y, 20);
  });

  test('the native source declares no-activate and always-on-top behavior', () {
    final String source = File('lib/src/panel_native.dart').readAsStringSync();
    expect(source, contains('_wsExNoActivate = 0x08000000'));
    expect(source, contains('setAlwaysOnTop(true)'));
    expect(source, contains('show(inactive: !_focusable)'));
    expect(source, contains('setAsFrameless()'));
    expect(source, contains('startDragging()'));
    expect(source, isNot(contains('onWindowMoved()')));
  });
}
