import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:miaotou_capabilities/miaotou_capabilities.dart';
import 'package:miaotou_capabilities_android/miaotou_capabilities_android.dart';
import 'package:miaotou_capabilities_macos/miaotou_capabilities_macos.dart';
import 'package:miaotou_capabilities_windows/miaotou_capabilities_windows.dart';

import 'design/copy.dart';
import 'panel/protocol.dart';
import 'panel/session.dart';
import 'panel/window_channel.dart';
import 'runtime/panel_settings.dart';

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

/// Which side of the panel this process is, or null when it is the main window.
///
/// The panel engine runs the same `main` the main window does, on every port:
/// Android and macOS ask the host which engine this is, Windows reads the window
/// arguments `desktop_multi_window` created it with. Whichever way the answer
/// arrives, the two engines get the same widget with a different channel and
/// nothing else — which is what keeps the panel a view rather than a second
/// application (ADR-0012).
Future<PanelWindowRuntime?> attachPanelWindowForCurrentPlatform() async {
  if (Platform.isAndroid) {
    final PanelEngineBootstrap bootstrap = PanelEngineBootstrap(
      channelName: PanelEngineBootstrap.androidChannelName,
    );
    if (await bootstrap.role() == PanelEngineRole.main) {
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
  if (Platform.isMacOS) {
    final PanelEngineBootstrap bootstrap = PanelEngineBootstrap(
      channelName: PanelEngineBootstrap.macosChannelName,
    );
    if (await bootstrap.role() == PanelEngineRole.main) {
      return null;
    }
    final MacosPanelViewChannel channel = MacosPanelViewChannel();
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

/// Starts the panel window and connects the two engines.
///
/// **The panel's settings are read here and nowhere else.** The appearance goes
/// down the panel protocol as a second down-stream beside the frame, and the
/// placement goes down the event stream — it is read from
/// [CapabilitySet.preferences] rather than from a per-port store, and written
/// back from the drag the panel reports. Nothing on the panel's side reads a
/// preference, because that would be a second reader of one setting
/// (ADR-0002 decision 2, ADR-0020).
Future<void> startPanelForCurrentPlatform(
  CapabilitySet capabilities,
  PanelSession panel, {
  AppCopy copy = AppCopy.zh,
}) async {
  final PanelSettings settings = await PanelSettings.load(
    capabilities.preferences,
  );

  if (Platform.isAndroid) {
    final AndroidPanelMainChannel channel = AndroidPanelMainChannel();
    await channel.initialize();
    await _showPanel(
      capabilities: capabilities,
      panel: panel,
      copy: copy,
      placement: _placement(
        settings,
        const PanelPlacement(anchor: PanelAnchor.topLeft, dx: 12, dy: 56),
      ),
    );
    return _connect(
      panel: panel,
      pushFrame: channel.push,
      pushAppearance: channel.pushAppearance,
      commands: channel.commands,
      floating: capabilities.floatingPanel,
      appearance: settings.appearance,
    );
  }

  if (Platform.isMacOS) {
    final MacosPanelMainChannel channel = MacosPanelMainChannel();
    await channel.initialize();
    await _showPanel(
      capabilities: capabilities,
      panel: panel,
      copy: copy,
      placement: _placement(
        settings,
        const PanelPlacement(anchor: PanelAnchor.topLeft, dx: 12, dy: 56),
      ),
    );
    return _connect(
      panel: panel,
      pushFrame: channel.push,
      pushAppearance: channel.pushAppearance,
      commands: channel.commands,
      floating: capabilities.floatingPanel,
      appearance: settings.appearance,
    );
  }

  if (!Platform.isWindows) {
    return;
  }
  final WindowsPanelMainChannel channel = WindowsPanelMainChannel();
  await channel.initialize();
  await _showPanel(
    capabilities: capabilities,
    panel: panel,
    copy: copy,
    placement: _placement(settings, const PanelPlacement(anchor: PanelAnchor.free)),
  );
  return _connect(
    panel: panel,
    pushFrame: channel.push,
    pushAppearance: channel.pushAppearance,
    commands: channel.commands,
    floating: capabilities.floatingPanel,
    appearance: settings.appearance,
  );
}

/// Shows the panel window, and does not let a refused system permission take the
/// application down with it.
///
/// `FloatingPanel.show()` is where Android asks for the overlay permission
/// implicitly: when the grant is missing the plugin launches
/// `ACTION_MANAGE_OVERLAY_PERMISSION` itself, waits for the result and retries on
/// it. ADR-0021 decision 10 keeps that jump — the first run should not cost two
/// trips through settings for a user who never asked to configure anything — and
/// this is the other half of the decision. What the plugin does *not* do is
/// survive the answer: it raises `overlay_permission_unavailable`,
/// `overlay_permission_pending`, `overlay_permission_denied` or
/// `android_panel_show_failed`, and until ADR-0021 nothing in Dart caught any of
/// them. A declined permission was therefore an exception out of `main()`: the
/// user was dropped back into an application with no panel, no explanation, and
/// nothing to do next.
///
/// The sentence goes down the panel protocol like every other refusal, as a
/// [PanelNote] naming [PermissionKind.overlay], so a panel that does come up
/// draws the button instead of a description of the page.
///
/// **The panel is not what the user sees when this fails**, and that is not an
/// oversight: on Android its window is created by the same native call that just
/// refused, so there is nothing to render the note into. The surface that
/// actually gets the user out is the permission section at the top of settings,
/// which reads the same fact from `Permissions` and offers the same jump
/// (ADR-0021 decisions 7 and 9). What this function buys is the process
/// surviving, which is what makes that section reachable at all.
///
/// It is also why there is no retry here. Retrying `show()` without a restart
/// would close the loop — grant the permission from the section, come back, and
/// watch the panel appear — and it is not wired today. The note records the gap
/// rather than the code pretending it was closed.
Future<void> _showPanel({
  required CapabilitySet capabilities,
  required PanelSession panel,
  required AppCopy copy,
  required PanelPlacement placement,
}) async {
  try {
    await capabilities.floatingPanel.show(placement: placement);
  } on PlatformException catch (failure) {
    final PanelFrame current = panel.current;
    panel.publish(
      PanelFrame(
        analysed: current.analysed,
        live: current.live,
        advice: current.advice,
        note: panelShowFailureNote(failure, copy),
        transcript: current.transcript,
        appNames: current.appNames,
        reviewing: current.reviewing,
      ),
    );
    return;
  }
  _rememberPlacement(capabilities);
}

/// The sentence for one of the refusal codes `FloatingPanel.show()` raises.
///
/// Reading the code rather than the message, because the message is written for
/// a developer — `overlay_permission_pending` says "a display-over-other-apps
/// permission request is already open", which names the mechanism and not the
/// thing the user has to do.
///
/// Only `denied` carries a remedy, and that is the shape of the state rather
/// than a shortcut: `denied` means the user was taken to the page and declined,
/// so the way back is the same page. `pending` means a request is already open
/// and the answer is to wait for the dialog already on screen; `unavailable`
/// means the plugin has no activity to ask from at all, which no grant from the
/// user can fix. Anything else — `android_panel_show_failed` and the generic
/// `android_panel_<method>_failed` — is a defect and says so in one sentence.
///
/// Public because it is a pure function over four strings and a copy, and a
/// mapping nobody can pin is a mapping that drifts back to unhandled.
PanelNote panelShowFailureNote(PlatformException failure, AppCopy copy) =>
    switch (failure.code) {
      'overlay_permission_denied' => PanelNote(
        copy.text(CopyKey.runtimePanelPermissionDenied),
        remedy: const OpenPermissionPage(PermissionKind.overlay),
      ),
      'overlay_permission_pending' => PanelNote(
        copy.text(CopyKey.runtimePanelPermissionPending),
      ),
      _ => PanelNote(copy.text(CopyKey.runtimePanelShowFailed)),
    };

/// The collapsed ball is the panel's initial size on every port.
///
/// It expands itself the first time the user taps it; what a port has to be told
/// at `show` is only where the ball goes, and a saved placement says nothing
/// about size because the size is not a setting.
const double _collapsedSide = 56;

/// A stored placement, or the port's own first-run corner.
///
/// The corner is a parameter because the two shapes are genuinely different: the
/// phone ports start inset from a corner and the two desktop ports start free,
/// which is the anchor that means "the next show resolves where I was left".
PanelPlacement _placement(PanelSettings settings, PanelPlacement firstRun) {
  final PanelPlacement? saved = settings.placement;
  return PanelPlacement(
    anchor: saved?.anchor ?? firstRun.anchor,
    dx: saved?.dx ?? firstRun.dx,
    dy: saved?.dy ?? firstRun.dy,
    width: _collapsedSide,
    height: _collapsedSide,
  );
}

/// Writes the placement the user dragged the panel to.
///
/// The event is the *reported* landing rather than the window being asked,
/// because the window is the only thing that knows where it actually ended up,
/// and this store is the only writer of one key in the main window's
/// preferences. All three ports used to keep this themselves — a JSON file on
/// Windows, a native preference file on Android, process memory on macOS — and
/// ADR-0020 retires all three.
void _rememberPlacement(CapabilitySet capabilities) {
  capabilities.floatingPanel.events.listen((PanelEvent event) {
    if (event case PanelDragged(:final double x, :final double y)) {
      unawaited(
        PanelSettings.savePlacement(
          capabilities.preferences,
          PanelPlacement(anchor: PanelAnchor.free, dx: x, dy: y),
        ),
      );
    }
  });
}

/// Both down-streams out, commands in.
Future<void> _connect({
  required PanelSession panel,
  required Future<void> Function(PanelFrame frame) pushFrame,
  required Future<void> Function(PanelAppearance appearance) pushAppearance,
  required Stream<PanelCommand> commands,
  required FloatingPanel floating,
  required PanelAppearance appearance,
}) async {
  // Into the session first so it is the one holder of the value, then out to a
  // window that may not be listening yet — the channel holds it either way.
  panel.publishAppearance(appearance);
  await pushAppearance(panel.appearance);
  await pushFrame(panel.current);
  panel.frames.listen((PanelFrame frame) => unawaited(pushFrame(frame)));
  panel.appearances.listen(
    (PanelAppearance value) => unawaited(pushAppearance(value)),
  );
  commands.listen((PanelCommand command) {
    panel.receive(command);
    if (command.kind == PanelCommandKind.close) {
      unawaited(floating.hide());
    }
  });
}
