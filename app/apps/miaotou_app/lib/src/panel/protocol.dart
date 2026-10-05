import 'dart:async';

import 'package:miaotou_capabilities/miaotou_capabilities.dart';
import 'package:miaotou_domain/miaotou_domain.dart';

/// Everything that may cross between the main window and the floating panel.
///
/// **Two streams down and one up, and that is the whole contract** (#12, AC2): a
/// frame goes down, an appearance goes down beside it, a command comes up.
/// Nothing else crosses, and nothing reaches across: the panel cannot ask a
/// capability, read a store or call a model, because there is no path for it to
/// do so — it is handed a [PanelFrame], a [PanelAppearance] and a callback.
///
/// The appearance is a down-stream rather than a field on the frame because it is
/// not a fact about an analysis: a frame only arrives when there is one, so a
/// panel with nothing analysed yet would have nothing to paint its own surface
/// from. It is not a `FloatingPanel` member either — that interface is window
/// semantics, and this value never reaches a window (ADR-0020).
///
/// The typed contract lives here; the Windows JSON encoding lives beside the
/// multi-window transport in `window_channel.dart`. That keeps serialization
/// out of the domain while making every value crossing the engine boundary
/// explicit and testable.
///
/// ## Why the frame carries references and not labels
///
/// ADR-0002 decision 2: the view receives two facts — whose analysis this is,
/// and who the user is looking at now — and derives read-only itself. A frame
/// carrying pre-resolved labels would move that decision to the sender, and a
/// frame carrying only labels could not derive anything at all. So the refs go
/// down, and [PanelFrame.appNames] is how the package name becomes a name
/// *before* the label is built: the panel never sees one to print.
final class PanelFrame {
  const PanelFrame({
    required this.analysed,
    this.live,
    this.advice,
    this.note,
    this.transcript = const <PanelLine>[],
    this.appNames = const <String, String>{},
  });

  /// Whose analysis is on the panel. [ConversationRef.none] before the first
  /// one.
  final ConversationRef analysed;

  /// What the user is looking at right now, or null when nothing is known.
  final ConversationRef? live;

  /// The verdict and the drafts, or null when there has been no analysis.
  final Advice? advice;

  /// A caveat about how the analysed snapshot was produced, shown verbatim —
  /// an OCR capture cannot tell who said what, and that belongs on the panel.
  final String? note;

  /// What the last whole-frame capture read off the screen, in the order it
  /// appeared, and empty for every other source.
  ///
  /// A capture is the one path where the panel is the only witness: the user
  /// pressed a button, the screen it photographed is still behind the panel, and
  /// the words came out of pixels rather than out of a view the user can scroll
  /// to. Without this the panel can say that a capture happened and nothing at
  /// all about what it read — which is indistinguishable from a capture that
  /// read nothing, and was read that way (ADR-0018).
  final List<PanelLine> transcript;

  /// Package name to display name, resolved by the side that owns the platform.
  ///
  /// A package left out of this map has no known name, which is a real answer
  /// and drives the 「未识别会话」 fallbacks. It is never a reason to print the
  /// package.
  final Map<String, String> appNames;

  /// The resolver [derivePanel] wants, over this frame's map.
  String? appNameFor(ConversationRef reference) =>
      appNames[reference.packageName];
}

/// One line of that transcript.
///
/// The panel needs the speaker and the words and nothing else, so the rectangle
/// a captured line also carries stays on this side of the window boundary. It is
/// what the panel would need to point *at* the screen, and the panel has no way
/// to point at anything.
final class PanelLine {
  const PanelLine({required this.speaker, required this.text});

  final Speaker speaker;
  final String text;

  @override
  String toString() => 'PanelLine(${speaker.name}, $text)';
}

/// How the panel paints its own fill.
///
/// **The fill's alpha, not the window's.** The value lands on the one colour role
/// the panel engine overrides — `cardTheme.color` — so a window alpha is a
/// different effect: that one dims the text along with the background, and it
/// would collide with the `0f`/`1f` the Android port uses to take the panel out
/// of its own screenshot. Gate experiment A measured the difference (ADR-0020).
///
/// The panel is *fed* this and never derives it: the main window owns the
/// setting, reads it and pushes it, exactly as it pushes frames. The panel's own
/// state stays transient (ADR-0012).
final class PanelAppearance {
  const PanelAppearance({this.opacity = defaultOpacity});

  /// The panel is never fully transparent: at the bottom of the range the ball
  /// would disappear along with the fill it is drawn with, and the user would
  /// lose both the panel and the handle that drags it.
  static const int minOpacity = 40;

  /// Fully opaque. The top of the range, because a fill cannot be more solid.
  static const int maxOpacity = 100;

  /// What a user who has never touched the slider gets, and what the panel
  /// paints with before the main window's first push arrives.
  static const int defaultOpacity = 80;

  /// The fill's alpha as a whole percentage in
  /// [minOpacity]..[maxOpacity].
  final int opacity;

  /// What the panel's shared fill token is drawn at.
  double get fillAlpha => opacity / 100;

  /// A percentage from a source that may be outside the range: a stored value,
  /// or a slider that has not been clamped. Out-of-range is clamped rather than
  /// refused, because "as solid as the panel gets" is a real answer and a value
  /// from a previous release is not a fault.
  static PanelAppearance percent(int value) =>
      PanelAppearance(opacity: value.clamp(minOpacity, maxOpacity));

  @override
  bool operator ==(Object other) =>
      other is PanelAppearance && other.opacity == opacity;

  @override
  int get hashCode => opacity.hashCode;

  @override
  String toString() => 'PanelAppearance($opacity%)';
}

/// One thing the panel is asking for.
enum PanelCommandKind {
  fill,
  copy,
  details,
  reanalyse,
  analyseCurrent,

  /// Photograph whatever is in front and read the whole frame, then treat the
  /// result as the current conversation (ADR-0018).
  ///
  /// The one command that exists for applications the adapter registry does not
  /// know: without an adapter there is no tree to read, so the panel is the only
  /// way in and this is the door. It is never automatic — the registry stays the
  /// only thing that captures without the user asking.
  recogniseOnce,

  /// Closing the window is the window's business rather than the protocol's,
  /// and the OS gives the old ports no chrome to do it with — they draw their
  /// own close button. It is here so the panel has exactly one way to ask.
  close,
}

/// A command going up.
final class PanelCommand {
  const PanelCommand(this.kind, {this.candidateIndex, this.text});

  final PanelCommandKind kind;

  /// Which draft, for [PanelCommandKind.fill] and [PanelCommandKind.copy].
  final int? candidateIndex;

  /// The user-edited draft for fill/copy commands.
  final String? text;

  @override
  String toString() =>
      'PanelCommand(${kind.name}${candidateIndex == null ? '' : ', $candidateIndex'}'
      '${text == null ? '' : ', edited'})';
}

/// The one seam between the two windows.
///
/// An interface rather than a plugin call, so the panel can be driven in a
/// widget test with nothing attached — which is what #12, AC6 asks for. The
/// implementation that carries these over `desktop_multi_window` is #21's.
abstract class PanelChannel {
  /// Frames going down.
  Stream<PanelFrame> get frames;

  /// Appearances going down, beside the frames.
  ///
  /// A separate stream rather than a field on [PanelFrame] so that a panel with
  /// no analysis yet still knows how to paint itself, and so that a value the
  /// user is dragging lands the moment it changes rather than at the cadence
  /// analyses happen to arrive at (ADR-0020).
  Stream<PanelAppearance> get appearance;

  /// Commands going up.
  void send(PanelCommand command);
}

/// A channel with both ends in one process. For tests, and for the gallery.
final class InMemoryPanelChannel implements PanelChannel {
  final StreamController<PanelFrame> _frames =
      StreamController<PanelFrame>.broadcast();
  final StreamController<PanelAppearance> _appearance =
      StreamController<PanelAppearance>.broadcast();

  /// Everything the panel asked for, in order. Readable by a test.
  final List<PanelCommand> sent = <PanelCommand>[];

  @override
  Stream<PanelFrame> get frames => _frames.stream;

  @override
  Stream<PanelAppearance> get appearance => _appearance.stream;

  @override
  void send(PanelCommand command) => sent.add(command);

  /// A frame going down, from the main window's side.
  void push(PanelFrame frame) => _frames.add(frame);

  /// An appearance going down, from the main window's side.
  void pushAppearance(PanelAppearance value) => _appearance.add(value);

  void dispose() {
    _frames.close();
    _appearance.close();
  }
}
