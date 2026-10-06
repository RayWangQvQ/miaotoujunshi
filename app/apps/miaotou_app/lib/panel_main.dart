import 'package:flutter/material.dart';
import 'package:miaotou_capabilities/miaotou_capabilities.dart';

import 'src/design/colors.dart';
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
/// reach a capability, a store or the model: the panel is handed a [PanelFrame],
/// a [PanelAppearance] and a callback, and there is no path for anything else to
/// cross.
///
/// The production Windows entry point supplies a multi-window channel; tests and
/// the standalone preview may use the in-memory implementation. Both carry only
/// [PanelFrame] and [PanelAppearance] values down and [PanelCommand] values up.
void main() {
  runApp(const PanelApp());
}

/// The panel window's application.
///
/// The frame it starts with is [ConversationRef.none] on purpose. The panel must
/// never print a package name (ADR-0002), so the first thing worth seeing on
/// screen is the 「未识别会话」 fallback rather than a plausible-looking name.
class PanelApp extends StatefulWidget {
  const PanelApp({
    super.key,
    this.channel,
    this.onExpandedChanged,
    this.onDragStart,
    this.onInputFocusChanged,
    this.onReviewChanged,
    this.initialExpanded = true,
    this.initialAppearance = const PanelAppearance(),
  });

  /// The seam. An in-memory one by default so the panel runs with nothing else
  /// present; a window channel replaces it without changing anything below.
  final PanelChannel? channel;
  final ValueChanged<bool>? onExpandedChanged;
  final VoidCallback? onDragStart;
  final Future<void> Function(bool focusable)? onInputFocusChanged;

  /// Asks the host to grow the window while the batch is being reviewed
  /// (ADR-0022 decision 15).
  ///
  /// Null on the ports whose panel is already tall enough, which is why it is
  /// optional rather than required: a port with nothing to do says so by not
  /// answering, and the review still works.
  final Future<void> Function(bool reviewing)? onReviewChanged;
  final bool initialExpanded;

  /// What the panel paints itself with until the main window's first push
  /// arrives.
  ///
  /// The panel engine has no store, so it cannot read the setting and this is
  /// the default. A user who has left the slider alone therefore sees no change
  /// at all when the push lands; a user on a custom value may see one frame of
  /// the default, which is why the main window pushes beside the frame push it
  /// already does immediately after `show`.
  final PanelAppearance initialAppearance;

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
  Widget build(BuildContext context) {
    final AppColors palette = AppColors.light();
    final ThemeData baseTheme = buildTheme(colors: palette);
    return CopyScope(
      copy: AppCopy.zh,
      child: StreamBuilder<PanelAppearance>(
        stream: _channel.appearance,
        builder:
            (BuildContext context, AsyncSnapshot<PanelAppearance> snapshot) =>
                MaterialApp(
                  title: AppCopy.zh.text(CopyKey.appTitle),
                  debugShowCheckedModeBanner: false,
                  theme: _theme(
                    baseTheme,
                    palette,
                    snapshot.data ?? widget.initialAppearance,
                  ),
                  home: Material(
                    type: MaterialType.transparency,
                    child: StreamBuilder<PanelFrame>(
                      stream: _channel.frames,
                      builder:
                          (
                            BuildContext context,
                            AsyncSnapshot<PanelFrame> snapshot,
                          ) => PanelPage(
                            frame: snapshot.data ?? _empty,
                            onCommand: _channel.send,
                            onExpandedChanged: widget.onExpandedChanged,
                            onDragStart: widget.onDragStart,
                            onInputFocusChanged: widget.onInputFocusChanged,
                            onReviewChanged: widget.onReviewChanged,
                            initialExpanded: widget.initialExpanded,
                          ),
                    ),
                  ),
                ),
      ),
    );
  }

  /// The panel engine's whole visual difference from the main window: one colour
  /// role, overridden with the fill alpha the main window pushed.
  ///
  /// **It is one token and it reaches three places.** Every `Card` in this engine
  /// reads `cardTheme.color`, and the panel has three of them — the collapsed
  /// ball, the frame and each candidate card — so the value covers all of them
  /// and the inner cards are white on white over the frame. Splitting the token
  /// is a visual redesign and was rejected for this change (ADR-0020). Two things
  /// deliberately do not follow it: the read-only banner's fill and the frame's
  /// hairline. The banner is the one thing on the panel a user must be able to
  /// see, and a border that faded with the fill would remove the only mark of
  /// where a nearly-transparent panel ends and the chat begins.
  static ThemeData _theme(
    ThemeData baseTheme,
    AppColors palette,
    PanelAppearance appearance,
  ) => baseTheme.copyWith(
    canvasColor: palette.surface.withValues(alpha: 0),
    scaffoldBackgroundColor: palette.surface.withValues(alpha: 0),
    cardTheme: baseTheme.cardTheme.copyWith(
      color: palette.surfaceRaised.withValues(alpha: appearance.fillAlpha),
    ),
  );
}
