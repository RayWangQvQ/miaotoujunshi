import 'dart:async';

import 'package:miaotou_capabilities/miaotou_capabilities.dart';

import 'protocol.dart';

/// Main-engine owner of the panel's shared snapshot and command streams.
///
/// The appearance is here for the same reason the frames are: the *main window*
/// owns it and the panel is fed it. Nothing below this type stores it, and
/// nothing on the panel's side may derive it (ADR-0012, ADR-0020).
final class PanelSession {
  PanelSession({
    PanelFrame initial = const PanelFrame(analysed: ConversationRef.none),
  }) : _current = initial;

  PanelFrame _current;
  PanelAppearance _appearance = const PanelAppearance();
  final StreamController<PanelFrame> _frames =
      StreamController<PanelFrame>.broadcast();
  final StreamController<PanelCommand> _commands =
      StreamController<PanelCommand>.broadcast();
  final StreamController<PanelAppearance> _appearances =
      StreamController<PanelAppearance>.broadcast();

  PanelFrame get current => _current;
  Stream<PanelFrame> get frames => _frames.stream;
  Stream<PanelCommand> get commands => _commands.stream;

  /// What the panel is painted with right now.
  PanelAppearance get appearance => _appearance;

  /// Appearance changes going down. Replayed to a channel that subscribes late
  /// by the caller, which is why the current value is kept here as well.
  Stream<PanelAppearance> get appearances => _appearances.stream;

  void publish(PanelFrame frame) {
    _current = frame;
    _frames.add(frame);
  }

  void publishAppearance(PanelAppearance value) {
    if (value == _appearance) {
      return;
    }
    _appearance = value;
    _appearances.add(value);
  }

  void receive(PanelCommand command) => _commands.add(command);

  Future<void> dispose() async {
    await _frames.close();
    await _commands.close();
    await _appearances.close();
  }
}
