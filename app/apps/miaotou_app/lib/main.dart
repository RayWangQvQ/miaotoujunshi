import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:miaotou_capabilities/miaotou_capabilities.dart';

import 'panel_main.dart';
import 'src/app.dart';
import 'src/capability_registry.dart';
import 'src/design/copy.dart';
import 'src/runtime/conversation_runtime.dart';
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
        onReviewChanged: panel.setReviewing,
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
  late final ConversationRuntime runtime;
  final Session session = Session(
    capabilities: capabilities,
    onEnd: () => runtime.dispose(),
  );
  final MainWindowController window = MainWindowController();
  runtime = ConversationRuntime(
    capabilities: capabilities,
    panel: session.panel,
    copy: AppCopy.zh,
    clipboardWrite: (String text) =>
        Clipboard.setData(ClipboardData(text: text)),
    onAdvice: session.publishAdvice,
  );

  await startPanelForCurrentPlatform(capabilities, session.panel);
  await runtime.start();

  runApp(MiaotouApp(session: session, window: window));
}

/// The panel engine's entry point **on macOS**.
///
/// `FloatingPanelHost.entrypoint` names it, because the macOS host starts the
/// second engine itself and has to name a function. Android and Windows start
/// their panel engine on the default `main`; all three roads arrive at the same
/// detection in [attachPanelWindowForCurrentPlatform], so this is an alias and
/// nothing else — a second implementation here would be a second answer to
/// "which side am I".
///
/// **The annotation is load-bearing.** The name is looked up at runtime in a
/// release build, so an unannotated top-level function is tree-shaken away and
/// the panel engine then starts with no Dart at all.
@pragma('vm:entry-point')
void panelMain() {
  main();
}
