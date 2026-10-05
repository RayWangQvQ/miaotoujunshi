import 'package:flutter/material.dart';
import 'package:miaotou_capabilities/miaotou_capabilities.dart';

import 'panel_main.dart';
import 'src/app.dart';
import 'src/capability_registry.dart';
import 'src/session.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final PanelWindowRuntime? panel = await attachPanelWindowForCurrentPlatform();
  if (panel != null) {
    runApp(
      PanelApp(
        channel: panel.channel,
        onExpandedChanged: panel.setExpanded,
        onDragStart: panel.startDragging,
        onInputFocusChanged: panel.setFocusable,
        initialExpanded: false,
      ),
    );
    return;
  }

  // The one line that knows what it is running on. Everything below `runApp`
  // receives the capability set rather than looking for one, which is what lets a
  // test drive the whole application with no device attached (ADR-0009).
  final CapabilitySet capabilities = capabilitiesForCurrentPlatform();

  // The session and the window are made here rather than inside a widget,
  // because ADR-0012 requires the session to survive the window: a `State` that
  // owned it would end it in `dispose`, and closing the main window would take
  // the capture loop and the credentials with it while the ball is still on
  // screen.
  //
  // Nothing in this file ends the session either. Quitting is a platform
  // decision — a tray item, a dock menu — and arrives through a port's own
  // implementation ticket.
  final Session session = Session(capabilities: capabilities);
  final MainWindowController window = MainWindowController();

  await startPanelForCurrentPlatform(capabilities, session.panel);

  runApp(MiaotouApp(session: session, window: window));
}
