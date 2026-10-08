import 'conversation_ref.dart';
import 'screen_rect.dart';
import 'speaker.dart';

/// One chat line the accessibility tree could read.
final class ChatLine {
  const ChatLine({
    required this.speaker,
    required this.text,
    this.bounds,
    this.occurredAt,
  });

  final Speaker speaker;
  final String text;

  /// Screen coordinates when the tree exposes them. Null when it does not —
  /// which is the normal case for a line the tree could read but not place.
  final ScreenRect? bounds;

  /// When the message itself was sent, when a chat's own timestamp named it.
  ///
  /// Distinct from a snapshot's `capturedAt`, which is the capture moment. A
  /// whole-frame capture reads a day divider (`10/04 11:39`) above a message and
  /// records that as the message's time; the tree path has no such divider and
  /// leaves this null. A time is a convenience, never something to invent.
  final DateTime? occurredAt;

  @override
  String toString() => 'ChatLine(${speaker.name}, $text)';
}

/// A bubble the tree could locate but not read.
///
/// Some chat applications draw their message text instead of laying it out as
/// nodes, so the tree yields a rectangle and nothing else. [speaker] is what the
/// tree could infer around the bubble, which is frequently [Speaker.unknown];
/// the caller reads the words by running OCR over [bounds].
final class UnreadBubble {
  const UnreadBubble({required this.bounds, required this.speaker});

  final ScreenRect bounds;
  final Speaker speaker;

  @override
  String toString() => 'UnreadBubble(${speaker.name}, $bounds)';
}

/// What the accessibility tree says about the conversation in front.
///
/// An empty [lines] together with a populated [unreadBubbles] means "in a chat
/// window, but the tree holds no text" — the cue for the OCR fallback, and the
/// only case where [unreadBubbles] is populated at all.
final class ChatUiSnapshot {
  const ChatUiSnapshot({
    required this.conversation,
    required this.lines,
    required this.capturedAt,
    this.unreadBubbles = const <UnreadBubble>[],
    this.note,
    this.reviewed = false,
  });

  final ConversationRef conversation;
  final List<ChatLine> lines;
  final List<UnreadBubble> unreadBubbles;

  /// When the tree was read. A snapshot is a measurement, not a live view.
  final DateTime capturedAt;

  /// A caveat about how this snapshot was produced, shown verbatim in the
  /// panel. Null when there is nothing to warn about.
  final String? note;

  /// Whether the user has read this batch and confirmed it.
  ///
  /// **A fact about the batch, not about a line.** A manual whole-frame capture
  /// cannot be scored per line, so every line of one carries `[OCR待核对]`, and
  /// the domain refuses a batch whose every line is doubtful. The way out is a
  /// person saying "that is the conversation", which is answered for the batch
  /// as a whole — a user who changed nothing has still answered it. It is
  /// deliberately not a field on [ChatLine]: a line's speaker and text are what
  /// the perception layer produced, and what the user did with them afterwards
  /// is a different claim (ADR-0022).
  ///
  /// Defaults to false because the ordinary snapshot is one nobody has looked
  /// at yet.
  final bool reviewed;

  /// A stable signature of the last few lines, so a caller can tell a real
  /// change from a re-read of the same screen. Six is the count the Android
  /// port settled on before the freeze.
  String signature() {
    const tail = 6;
    final start = lines.length <= tail ? 0 : lines.length - tail;
    return lines
        .sublist(start)
        .map((line) => '${line.speaker.name}:${line.text}')
        .join('|');
  }

  @override
  String toString() =>
      'ChatUiSnapshot($conversation, ${lines.length} lines, '
      '${unreadBubbles.length} unread${reviewed ? ', reviewed' : ''})';
}
