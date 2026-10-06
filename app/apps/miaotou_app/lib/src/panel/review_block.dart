import 'package:miaotou_capabilities/miaotou_capabilities.dart'
    show Speaker;

import '../design/copy.dart';
import 'protocol.dart';

/// The block text the review edits, and the rules that bind it to the typed
/// [PanelLine] list the protocol carries (ADR-0025).
///
/// The speaker lives in a prefix at the start of each line — `我：`, `对方：` or
/// `未定：` — and the whole batch is one editable string. Serialising and
/// parsing are exact inverses only if every line is written with a prefix, so
/// serialisation always writes one, including `未定：`: a line written bare
/// would parse as *inherit the line above* and come back a different speaker.
///
/// Parsing is deliberately forgiving about what a person types, and strict only
/// about the one thing that keeps a paste safe: a line with no prefix inherits
/// the speaker of the line above it, and a first line with no prefix is
/// `unknown`. That rule is why a multi-line message pasted straight after
/// `我：` stays `我` all the way down, which is the failure ADR-0022 named.
///
/// The speaker words are copy, not literals: the wire never spells these tokens
/// (ADR-0015) and the review is the surface that does, so it asks [AppCopy] for
/// them the same way every other string on the panel does.
final class ReviewBlock {
  const ReviewBlock._();

  /// The three speaker words, in enum order, matched at the start of a line.
  static Map<Speaker, String> _words(AppCopy copy) => <Speaker, String>{
    Speaker.me: copy.text(CopyKey.panelSpeakerMe),
    Speaker.other: copy.text(CopyKey.panelSpeakerOther),
    Speaker.unknown: copy.text(CopyKey.panelSpeakerUnknown),
  };

  /// Renders the batch as the one block the user edits.
  ///
  /// Every line gets its prefix, joined by a newline, and the block ends in a
  /// newline so that typing a new line has somewhere to go. A single trailing
  /// newline round-trips cleanly: parsing drops it as a blank line.
  static String fromLines(List<PanelLine> lines, AppCopy copy) => lines
      .map(
        (PanelLine line) => '${_words(copy)[line.speaker]}：${line.text}',
      )
      .join('\n');

  /// Turns the block the user edited back into typed lines.
  ///
  /// Blank lines are dropped and every surviving line is trimmed, which is the
  /// same reading `confirmTranscript` already applies to its input. A line whose
  /// prefix does not match any speaker inherits the one above it; a first line
  /// with no match is `unknown`.
  static List<PanelLine> toLines(String block, AppCopy copy) {
    final List<PanelLine> lines = <PanelLine>[];
    Speaker previous = Speaker.unknown;
    for (final String raw in block.split('\n')) {
      final String line = raw.trim();
      if (line.isEmpty) {
        continue;
      }
      final Speaker? matched = speakerOf(line, copy);
      final Speaker speaker = matched ?? previous;
      final String text = matched == null ? line : bodyOf(line, matched, copy);
      if (text.isEmpty) {
        // A bare prefix — `对方：` and nothing after it — is a line the user has
        // not filled in yet; it is not a message, so it is dropped rather than
        // carried as an empty body. It still sets the inheritance for the next
        // line, though, which is why it is not `continue`d before this point.
        previous = speaker;
        continue;
      }
      lines.add(PanelLine(speaker: speaker, text: text));
      previous = speaker;
    }
    return lines;
  }

  /// The speaker a line's prefix names, or null when the line has no recognised
  /// prefix and is therefore the previous speaker's.
  ///
  /// Tolerant in the way a person types: a half-width or full-width colon, and
  /// any amount of space after it, are all the same prefix. The match is
  /// anchored at the start of the line and nowhere else.
  static Speaker? speakerOf(String line, AppCopy copy) {
    final Map<Speaker, String> words = _words(copy);
    for (final MapEntry<Speaker, String> entry in words.entries) {
      final String word = entry.value;
      if (!line.startsWith(word)) {
        continue;
      }
      final String rest = line.substring(word.length);
      // `对方` is a prefix of `对方：`, so the colon check is what tells a
      // speaker word from a message that merely starts with one.
      if (RegExp(r'^[:：]\s*').hasMatch(rest)) {
        return entry.key;
      }
    }
    return null;
  }

  /// The text after [speaker]'s prefix, trimmed.
  static String bodyOf(String line, Speaker speaker, AppCopy copy) =>
      line.substring(_words(copy)[speaker]!.length + 1).trim();

  /// The word that names [speaker] in the block.
  static String wordOf(Speaker speaker, AppCopy copy) =>
      _words(copy)[speaker]!;
}
