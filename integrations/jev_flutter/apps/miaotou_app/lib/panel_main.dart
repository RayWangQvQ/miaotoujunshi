import 'package:flutter/material.dart';
import 'package:miaotou_capabilities/miaotou_capabilities.dart';

import 'src/design/copy.dart';
import 'src/design/theme.dart';
import 'src/panel/panel_page.dart';
import 'src/panel/protocol.dart';

/// The floating panel's own Flutter entry point.
///
/// **A second engine, not a route.** ADR-0012 gives the panel its own window so
/// it can float above the chat and stay up when the main window is closed. On
/// desktop that means a separate `FlutterEngine` and a separate isolate, and the
/// native side starts this entry point inside an `NSPanel` (see
/// `FloatingPanelHost.swift` in the macOS capability package). Nothing here may
/// reach a capability, a store or the model: the panel is handed a [PanelFrame]
/// and a callback, and there is no path for anything else to cross.
///
/// Until the frame channel is carried over a window channel the panel runs on an
/// in-memory one and shows the empty frame — the same frame the gallery shows, so
/// what is on screen is the real widget rather than a mock-up of it. Carrying the
/// two ends is the window mechanism's work, and the seam is [PanelChannel]: the
/// only thing that changes when it arrives is which channel the two widgets share.
void main() {
  runApp(const PanelApp());
}

/// The panel window's application.
///
/// The frame it starts with is [ConversationRef.none] on purpose. The panel must
/// never print a package name (ADR-0002), so the first thing worth seeing on
/// screen is the 「未识别会话」 fallback rather than a plausible-looking name.
class PanelApp extends StatefulWidget {
  const PanelApp({super.key, this.channel});

  /// The seam. An in-memory one by default so the panel runs with nothing else
  /// present; a window channel replaces it without changing anything below.
  final PanelChannel? channel;

  @override
  State<PanelApp> createState() => _PanelAppState();
}

class _PanelAppState extends State<PanelApp> {
  static const PanelFrame _empty = PanelFrame(analysed: ConversationRef.none);

  late final PanelChannel _channel;

  /// The channel this widget made, and therefore the one it has to close. Null
  /// when a channel was handed in, because closing somebody else's channel is not
  /// this widget's business.
  InMemoryPanelChannel? _owned;

  @override
  void initState() {
    super.initState();
    final PanelChannel? provided = widget.channel;
    if (provided == null) {
      final InMemoryPanelChannel created = InMemoryPanelChannel()..push(_empty);
      _owned = created;
      _channel = created;
      return;
    }
    _channel = provided;
  }

  @override
  void dispose() {
    _owned?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CopyScope(
        copy: AppCopy.zh,
        child: MaterialApp(
          title: AppCopy.zh.text(CopyKey.appTitle),
          debugShowCheckedModeBanner: false,
          theme: buildTheme(),
          home: StreamBuilder<PanelFrame>(
            stream: _channel.frames,
            builder: (BuildContext context, AsyncSnapshot<PanelFrame> snapshot) =>
                PanelPage(
                  frame: snapshot.data ?? _empty,
                  onCommand: _channel.send,
                ),
          ),
        ),
      );
}
