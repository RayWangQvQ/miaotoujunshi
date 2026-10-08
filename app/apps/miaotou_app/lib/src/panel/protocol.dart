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
/// down, with the app's display name already on each one: the platform resolves
/// a package to a name, the reference carries it, and the panel neither sees a
/// package nor holds a resolver (ADR-0028).
final class PanelFrame {
  const PanelFrame({
    required this.analysed,
    this.live,
    this.advice,
    this.note,
    this.transcript = const <PanelLine>[],
    this.reviewing = false,
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
  ///
  /// It carries a possible way out as well as words, because some of the notes
  /// the panel shows are refusals the user can act on (ADR-0021 decision 8,
  /// ADR-0022 decision 13).
  final PanelNote? note;

  /// The lines behind the batch on the panel, in the order they appeared.
  ///
  /// A capture is the one path where the panel is the only witness: the user
  /// pressed a button, the screen it photographed is still behind the panel, and
  /// the words came out of pixels rather than out of a view the user can scroll
  /// to. Without this the panel can say that a capture happened and nothing at
  /// all about what it read — which is indistinguishable from a capture that
  /// read nothing, and was read that way (ADR-0018).
  ///
  /// Since ADR-0022 decision 17 the lines are published for **every** source
  /// rather than only for a capture, because the review surface serves any batch
  /// and the standing 「核对」 button has nothing to be about otherwise. What
  /// the field means is therefore "the batch the panel is showing", not "the
  /// last thing that was photographed".
  final List<PanelLine> transcript;

  /// True while the panel is asking the user to read the batch and confirm it
  /// (ADR-0022).
  ///
  /// The main engine owns this rather than the panel deriving it, for the same
  /// reason it owns [note]: that side holds the gate, and it is the side that
  /// knows whether a confirmation is still outstanding. It is on the frame
  /// rather than left to the panel because "there is a transcript" is not the
  /// same question — a confirmed batch is still shown.
  final bool reviewing;
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

/// Something the user can do about a note.
///
/// A note is nearly always only words. Some are not: the platform refusing
/// because a system permission is off names a cause the user still has to act
/// on, and a sentence that says "go and switch it on" without being able to take
/// them there is what cost ADR-0018's first device run a code-reading session. So
/// did the refusal that asked the user to confirm the speakers and the text of a
/// batch whose only surface was read-only text (ADR-0022).
///
/// The way out travels as a value rather than as a flag, so the panel neither
/// knows nor names the thing it is asking for — it reports what the note needs
/// and the main engine, which owns the capabilities and the gate, decides what
/// that means on this port.
sealed class PanelRemedy {
  const PanelRemedy();
}

/// The system page for one permission is the way out.
final class OpenPermissionPage extends PanelRemedy {
  const OpenPermissionPage(this.kind);

  final PermissionKind kind;

  @override
  bool operator ==(Object other) =>
      other is OpenPermissionPage && other.kind == kind;

  @override
  int get hashCode => Object.hash(OpenPermissionPage, kind);

  @override
  String toString() => 'OpenPermissionPage(${kind.name})';
}

/// Reviewing the batch is the way out.
///
/// The refusal this answers is 「all of this is unconfirmed, confirm it first」,
/// and the batch it is about is the one the panel is showing (ADR-0022).
final class EnterReview extends PanelRemedy {
  const EnterReview();

  @override
  bool operator ==(Object other) => other is EnterReview;

  @override
  int get hashCode => Object.hash(EnterReview, 0);

  @override
  String toString() => 'EnterReview()';
}

/// Something the panel has to say, and what the user can do about it.
final class PanelNote {
  const PanelNote(this.text, {this.remedy});

  final String text;

  /// What the user can do about this, or null when the note is only something to
  /// read.
  final PanelRemedy? remedy;

  @override
  String toString() =>
      'PanelNote($text${remedy == null ? '' : ', remedy: $remedy'})';
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

  /// Takes the user to the system page for the permission a note named
  /// (ADR-0021).
  ///
  /// The panel does not open it and does not know which page it is: the note
  /// carries a [PermissionKind] and the main engine holds the capability. That
  /// is the same split every other command here follows.
  openPermissionSettings,

  /// Shows the batch on the panel as something the user can edit and confirm
  /// (ADR-0022).
  ///
  /// One command for both doors into the review state — the standing 「核对」
  /// button and the landing point of a refusal whose remedy is [EnterReview] —
  /// because they ask for the same thing and the engine already knows which
  /// batch is on the panel.
  openReview,

  /// The user confirmed the batch, and [PanelCommand.lines] is how they left it.
  ///
  /// This is the only command that changes the transcript rather than reporting
  /// something about it: what comes back is the user's reading of the screen,
  /// and the next analysis is gated on it.
  confirmTranscript,

  /// The user dropped the batch instead of confirming it (ADR-0022).
  ///
  /// The batch is thrown away rather than kept for later, because a panel that
  /// shows words it refuses to use is worse than an empty one.
  cancelReview,
}

/// A command going up.
final class PanelCommand {
  const PanelCommand(
    this.kind, {
    this.candidateIndex,
    this.text,
    this.permission,
    this.lines,
    this.title,
    this.appName,
  });

  final PanelCommandKind kind;

  /// Which draft, for [PanelCommandKind.fill] and [PanelCommandKind.copy].
  final int? candidateIndex;

  /// The user-edited draft for fill/copy commands.
  final String? text;

  /// Which system page, for [PanelCommandKind.openPermissionSettings].
  final PermissionKind? permission;

  /// The batch as the user left it, for [PanelCommandKind.confirmTranscript].
  ///
  /// A list of lines rather than one string, because the review edits the
  /// speaker of a line as well as its words, and the unit the user works in is
  /// the batch: they delete a line, fold one into the one above it, and confirm
  /// the rest. A single string could carry the text and nothing about who said
  /// it.
  ///
  /// Null for every other command, which is what keeps "no lines" distinct from
  /// "an empty batch" — the latter is refused by the panel, which disables the
  /// button rather than sending it.
  final List<PanelLine>? lines;

  /// The thread title the user entered, for [PanelCommandKind.confirmTranscript].
  final String? title;

  /// The application name the user entered, for [PanelCommandKind.confirmTranscript].
  final String? appName;

  @override
  String toString() =>
      'PanelCommand(${kind.name}${candidateIndex == null ? '' : ', $candidateIndex'}'
      '${text == null ? '' : ', edited'}'
      '${permission == null ? '' : ', ${permission!.name}'}'
      '${lines == null ? '' : ', ${lines!.length} lines'}'
      '${title == null ? '' : ', title'}'
      '${appName == null ? '' : ', appName'})';
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

/// The panel engine's end of the protocol, as the runtime needs it.
///
/// [PanelChannel] is the seam a panel *widget* is driven through; this is the
/// seam a panel *engine* is started through, and the difference is the four
/// members below. `attachPanelWindow` used to spell those four out once per port
/// because the ports' view channels shared no supertype; with one, which port's
/// channel this is becomes a single fact (`capability_registry.dart`'s
/// `PanelWiring`) and each port can be driven on its own in a test.
///
/// **Two of the three ports implement it.** Android and macOS ask their host which
/// engine this is and start the panel engine in this process, so their view
/// channel carries the window semantics too. Windows' view channel is a plain
/// [PanelChannel]: the frames arrive and the commands leave over it, but
/// `setExpanded` / `startDragging` / `setFocusable` come from
/// `WindowsPanelWindowBinding`, because on that port the panel engine already *is*
/// a window and has a native handle to drive rather than a host to ask.
///
/// Those three are window semantics (ADR-0012 decision 2): the panel says what it
/// wants, and how a frameless window is dragged or focused stays with the port.
abstract class PanelViewChannel implements PanelChannel {
  /// Registers this engine's handlers, and tells the far side it is up.
  ///
  /// `panelReady` is part of it rather than a separate call because the value
  /// that arrives before this point is lost: the main window pushed the first
  /// frame while the panel engine was still starting.
  Future<void> initialize();

  /// Grows the window into the panel or shrinks it back into the ball.
  Future<void> setExpanded(bool expanded);

  /// Hands the current drag to the platform's own window mover.
  Future<void> startDragging();

  /// Allows or refuses the panel taking keyboard focus.
  Future<void> setFocusable(bool focusable);
}

/// The main window's end of the panel protocol.
///
/// The mirrors of the four facts [PanelViewChannel] carries, going the other
/// way: this engine pushes both down-streams out and reads commands off one
/// stream in. A port implements it so that *which* channel carries them is one
/// fact per port rather than three copies of the same six calls
/// (`capability_registry.dart`'s `PanelWiring`).
///
/// Android's implementation does not buffer and the two desktop ports' do,
/// because the host that relays the protocol is Kotlin on one port and the panel
/// engine itself on the others. That difference stays inside the class and not in
/// this interface, which is why the interface has no `flush`.
abstract class PanelMainChannel {
  /// Registers this engine's handler for commands.
  Future<void> initialize();

  /// Commands coming up.
  Stream<PanelCommand> get commands;

  /// A frame going down.
  Future<void> push(PanelFrame frame);

  /// An appearance going down, beside the frames.
  Future<void> pushAppearance(PanelAppearance appearance);
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
