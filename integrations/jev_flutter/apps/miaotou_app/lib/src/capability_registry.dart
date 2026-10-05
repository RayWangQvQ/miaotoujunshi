import 'dart:io';

import 'package:miaotou_capabilities/miaotou_capabilities.dart';
import 'package:miaotou_capabilities_android/miaotou_capabilities_android.dart';
import 'package:miaotou_capabilities_macos/miaotou_capabilities_macos.dart';
import 'package:miaotou_capabilities_windows/miaotou_capabilities_windows.dart';

import 'panel/protocol.dart';
import 'panel/session.dart';
import 'panel/window_channel.dart';

/// The one place in the application that asks what it is running on.
///
/// ADR-0009 makes the contract the only boundary the three ports may differ
/// across, which means the *decision* about which port this is has to be made
/// exactly once and as early as possible. This is that place. Everything else
/// takes a [CapabilitySet] as a parameter, and nothing else in `lib/` imports a
/// platform package or `dart:io`.
///
/// There is no per-target selection in `pubspec.yaml` to do this for us: the
/// interface package is pure Dart by decision, so there is no federated plugin
/// and no `default_package` for the tool to read.
CapabilitySet capabilitiesForCurrentPlatform() {
  if (Platform.isAndroid) {
    return androidCapabilities();
  }

  if (Platform.isMacOS) {
    return macosCapabilities();
  }
  if (Platform.isWindows) {
    return windowsCapabilities();
  }
  throw UnsupportedError(
    'this application is built for Android, Windows and macOS; it is running on '
    '${Platform.operatingSystem}',
  );
}

final class PanelWindowRuntime {
  const PanelWindowRuntime({
    required this.channel,
    required this.setExpanded,
    required this.startDragging,
    required this.setFocusable,
  });

  final PanelChannel channel;
  final Future<void> Function(bool expanded) setExpanded;
  final Future<void> Function() startDragging;
  final Future<void> Function(bool focusable) setFocusable;
}

Future<PanelWindowRuntime?> attachPanelWindowForCurrentPlatform() async {
  if (Platform.isAndroid) {
    final AndroidPanelBootstrap bootstrap = AndroidPanelBootstrap();
    if (await bootstrap.role() == AndroidPanelEngineRole.main) {
      return null;
    }
    await bootstrap.markResumed();
    final AndroidPanelViewChannel channel = AndroidPanelViewChannel();
    await channel.initialize();
    return PanelWindowRuntime(
      channel: channel,
      setExpanded: channel.setExpanded,
      startDragging: channel.startDragging,
      setFocusable: channel.setFocusable,
    );
  }
  if (!Platform.isWindows) {
    return null;
  }
  final WindowsPanelWindowBinding? panel =
      await WindowsPanelWindowBinding.attachIfPanel();
  if (panel == null) {
    return null;
  }
  final WindowsPanelViewChannel channel = WindowsPanelViewChannel();
  await channel.initialize();
  return PanelWindowRuntime(
    channel: channel,
    setExpanded: panel.setExpanded,
    startDragging: panel.startDragging,
    setFocusable: panel.setFocusable,
  );
}

Future<void> startPanelForCurrentPlatform(
  CapabilitySet capabilities,
  PanelSession panel,
) async {
  if (Platform.isAndroid) {
    final AndroidPanelMainChannel channel = AndroidPanelMainChannel();
    await channel.initialize();
    await capabilities.floatingPanel.show(
      placement: const PanelPlacement(
        anchor: PanelAnchor.topLeft,
        dx: 12,
        dy: 56,
        width: 56,
        height: 56,
      ),
    );
    await channel.push(panel.current);
    panel.frames.listen(channel.push);
    channel.commands.listen((PanelCommand command) {
      panel.receive(command);
      if (command.kind == PanelCommandKind.close) {
        capabilities.floatingPanel.hide();
      }
    });
    return;
  }
  if (!Platform.isWindows) {
    return;
  }
  final WindowsPanelMainChannel channel = WindowsPanelMainChannel();
  final WindowsPanelPositionStore positionStore =
      FileWindowsPanelPositionStore();
  final WindowsPanelPosition? savedPosition = await positionStore.read();
  await channel.initialize();
  await capabilities.floatingPanel.show(
    placement: PanelPlacement(
      anchor: PanelAnchor.free,
      dx: savedPosition?.x ?? 0,
      dy: savedPosition?.y ?? 0,
      width: 56,
      height: 56,
    ),
  );
  capabilities.floatingPanel.events.listen((PanelEvent event) {
    if (event case PanelDragged(:final x, :final y)) {
      positionStore.write(WindowsPanelPosition(x: x, y: y));
    }
  });
  await channel.push(panel.current);
  panel.frames.listen(channel.push);
  channel.commands.listen((PanelCommand command) {
    panel.receive(command);
    if (command.kind == PanelCommandKind.close) {
      capabilities.floatingPanel.hide();
    }
  });
}
