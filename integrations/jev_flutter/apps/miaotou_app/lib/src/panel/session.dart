import 'dart:async';

import 'package:miaotou_capabilities/miaotou_capabilities.dart';

import 'protocol.dart';

/// Main-engine owner of the panel's shared snapshot and command streams.
final class PanelSession {
  PanelSession({
    PanelFrame initial = const PanelFrame(analysed: ConversationRef.none),
  }) : _current = initial;

  PanelFrame _current;
  final StreamController<PanelFrame> _frames =
      StreamController<PanelFrame>.broadcast();
  final StreamController<PanelCommand> _commands =
      StreamController<PanelCommand>.broadcast();

  PanelFrame get current => _current;
  Stream<PanelFrame> get frames => _frames.stream;
  Stream<PanelCommand> get commands => _commands.stream;

  void publish(PanelFrame frame) {
    _current = frame;
    _frames.add(frame);
  }

  void receive(PanelCommand command) => _commands.add(command);

  Future<void> dispose() async {
    await _frames.close();
    await _commands.close();
  }
}
