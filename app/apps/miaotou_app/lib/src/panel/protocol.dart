import 'dart:async';

import 'package:miaotou_capabilities/miaotou_capabilities.dart';
import 'package:miaotou_domain/miaotou_domain.dart';

/// Everything that may cross between the main window and the floating panel.
///
/// Two directions, and that is the whole contract (#12, AC2): a frame goes down,
/// a command comes up. Nothing else crosses, and nothing reaches across: the
/// panel cannot ask a capability, read a store or call a model, because there is
/// no path for it to do so — it is handed a [PanelFrame] and a callback.
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

  /// Commands going up.
  void send(PanelCommand command);
}

/// A channel with both ends in one process. For tests, and for the gallery.
final class InMemoryPanelChannel implements PanelChannel {
  final StreamController<PanelFrame> _frames =
      StreamController<PanelFrame>.broadcast();

  /// Everything the panel asked for, in order. Readable by a test.
  final List<PanelCommand> sent = <PanelCommand>[];

  @override
  Stream<PanelFrame> get frames => _frames.stream;

  @override
  void send(PanelCommand command) => sent.add(command);

  /// A frame going down, from the main window's side.
  void push(PanelFrame frame) => _frames.add(frame);

  void dispose() => _frames.close();
}
