import 'package:flutter/foundation.dart';

import 'package:miaotou_capabilities/miaotou_capabilities.dart';

import 'panel/session.dart';
import 'shell/destination.dart';

/// What the process is doing, as opposed to what the window is showing.
///
/// ADR-0012 gives the main window two jobs that pull in opposite directions: it
/// is the sole holder of the ten capabilities, and it must survive being closed.
/// It can only do both if the two halves are separate objects, so this type is
/// the half that is *not* a widget. Nothing in the tree owns it, nothing in the
/// tree disposes it, and closing the window cannot reach it — which is exactly
/// what `test/main_window_test.dart` asserts.
///
/// The [onEnd] hook exists because "tear down the capabilities" is a sentence
/// only the platform layer can finish: a port's capture loop, its credentials
/// and its panel are its own to close. The session promises to call it once, and
/// promises never to call it on the way to hiding a window.
final class Session {
  Session({required this.capabilities, this.onEnd, PanelSession? panel})
    : panel = panel ?? PanelSession();

  /// The ten capabilities this port answers for. Read by the diagnostics page,
  /// and by nothing that could mistake a hidden window for a dead one.
  final CapabilitySet capabilities;
  final PanelSession panel;

  /// Called exactly once, by [end], and by nothing else.
  final Future<void> Function()? onEnd;

  bool _running = true;
  int _endCount = 0;

  /// Whether the session is still up. A hidden window leaves this true.
  bool get running => _running;

  /// How many times [end] has actually ended something. Zero means no teardown
  /// has happened, which is the number the close-window test reads.
  int get endCount => _endCount;

  /// Ends the session: the one path that tears the capabilities down.
  ///
  /// Idempotent, because "quit" can arrive twice — from a menu and from a
  /// system shutdown in the same moment — and a second teardown is a crash in a
  /// port that has already closed its panel.
  Future<void> end() async {
    if (!_running) {
      return;
    }
    _running = false;
    _endCount++;
    final Future<void> Function()? stop = onEnd;
    if (stop != null) {
      await stop();
    }
    await panel.dispose();
  }
}

/// The main window's own state: whether it is on screen, and which page is up.
///
/// A [ChangeNotifier] rather than a `State`, because the thing that drives it
/// is not the user tapping a widget — it is the platform reporting that the
/// window was closed, which arrives from outside the tree on every desktop port
/// and cannot wait for a build. Keeping it here also means a test can close the
/// window without a window.
///
/// [requestClose] is the whole of ADR-0012's "closing the window is not the same
/// as quitting": it hides, and nothing else. There is deliberately no path from
/// here to [Session.end] — quitting is a separate decision, taken elsewhere, and
/// the absence of that path is the acceptance criterion.
class MainWindowController extends ChangeNotifier {
  bool _visible = true;
  ShellDestination _destination = ShellDestination.detail;

  /// Whether the main window is on screen. False means hidden, not closed: the
  /// session is still running and the ball is still on top of the chat.
  bool get visible => _visible;

  ShellDestination get destination => _destination;

  /// The user closed the window. Hide it and keep going.
  ///
  /// Who calls this is the platform: on each desktop port a window plugin has to
  /// turn the operating system's close event into this call, because a Flutter
  /// application ends when its last window does unless somebody says otherwise.
  /// That plugin is a port's own implementation ticket (#15/#19/#23). What #11
  /// owns is the other half — that once the call arrives, hiding cannot take the
  /// session with it.
  void requestClose() {
    if (!_visible) {
      return;
    }
    _visible = false;
    notifyListeners();
  }

  /// Something asked for the window again: a tray item, a dock icon, a second
  /// launch.
  void requestShow() {
    if (_visible) {
      return;
    }
    _visible = true;
    notifyListeners();
  }

  /// Moves to another page. A route inside this window, never a new window.
  void navigate(ShellDestination destination) {
    if (_destination == destination) {
      return;
    }
    _destination = destination;
    notifyListeners();
  }
}
