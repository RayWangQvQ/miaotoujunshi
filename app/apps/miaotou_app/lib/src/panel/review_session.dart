import 'package:flutter/services.dart' show TextEditingValue, TextSelection;
import 'package:miaotou_capabilities/miaotou_capabilities.dart' show Speaker;

import '../design/copy.dart';
import 'protocol.dart';
import 'review_block.dart';

/// The review's rules, in one module: what the block starts as, what the caret's
/// own operations do to it, and when a frame carries a batch the field does not.
///
/// ## Why this is a module and not four private methods
///
/// While the review is up the block is the source of truth (ADR-0025), so the
/// surface has to answer two questions on every frame:
///
/// - *Is the batch in the field still the batch on the panel?* A republish that
///   repeats it must not replace what the user has typed with what the
///   recogniser read.
/// - *Has the user come back to the review?* Coming back is a new block, not the
///   edit from last time resurrected under the caret.
///
/// Both are one comparison against one remembered fact, and both used to be a
/// twelve-line comparator plus a flag inside the panel widget — reachable only
/// by pumping the whole form through `test/panel_test.dart`.
///
/// ## What it holds, and what it does not
///
/// **No content.** The rows the block was built from are remembered as a
/// signature, never as lines: the batch itself is on the frame, and a second
/// copy here would be the drift every other field in the panel is scanned for.
/// [PanelLine] is not on that scan's list because the surface *is* rows; what
/// this module adds is one string per batch.
///
/// **No Flutter focus.** Which line the caret is on arrives with the
/// [TextEditingValue]. Whether the field has been focused at all is the
/// widget's, because that is a fact about a `FocusNode` and not about the batch
/// (ADR-0025 decision 9).
final class ReviewSession {
  ReviewSession(this._copy);

  /// The words for the prefixes and the speaker buttons. Injected once, because
  /// the block is made of copy and every method would otherwise carry it.
  final AppCopy _copy;

  /// The batch the field currently holds, as a signature — or null, which is
  /// this module's whole memory of the review not being up.
  String? _builtFrom;

  /// The block the field should show, or null when it already shows the right
  /// one.
  ///
  /// Called on every frame **in both states**, because the answer for "the
  /// review is not up" is *forget*: the batch the field was built from belongs
  /// to one visit, and that is what makes coming back a fresh block rather than
  /// a resurrected edit. Handing over `reviewing: false` and ignoring the null
  /// is the whole of what the caller owes this module.
  String? blockFor({
    required bool reviewing,
    required List<PanelLine> batch,
  }) {
    if (!reviewing) {
      _builtFrom = null;
      return null;
    }
    final String signature = _signatureOf(batch);
    if (_builtFrom == signature) {
      return null;
    }
    _builtFrom = signature;
    return ReviewBlock.fromLines(batch, _copy);
  }

  /// The batch as the engine receives it, read back out of the edited block.
  ///
  /// The one door: the confirm command and the confirm button's own enablement
  /// read the same parse, so they cannot disagree about whether anything is left
  /// (ADR-0025 decision 15).
  List<PanelLine> lines(String block) => ReviewBlock.toLines(block, _copy);

  /// Deletes the physical line the caret is on, newline and all.
  ///
  /// "Physical" is deliberate: a chat message that wrapped is several physical
  /// lines, and the user asked to delete the line they can see, not the message
  /// the model will later read. A non-last line goes with its trailing newline,
  /// a last line with its preceding newline, so the two neighbours meet rather
  /// than leaving a blank line behind. The caret falls back to the start of the
  /// deleted span, so tapping 删行 again removes the next line.
  TextEditingValue deleteLine(TextEditingValue value) {
    final String text = value.text;
    final int caret = value.selection.start < 0 ? 0 : value.selection.start;
    final int lineStart = _lineStartOf(text, caret);
    final int lineEnd = text.indexOf('\n', caret); // -1 on the last line

    final int delStart;
    final int delEnd;
    if (lineEnd != -1) {
      delStart = lineStart;
      delEnd = lineEnd + 1;
    } else if (lineStart > 0) {
      delStart = lineStart - 1;
      delEnd = text.length;
    } else {
      delStart = 0;
      delEnd = text.length;
    }
    return TextEditingValue(
      text: text.replaceRange(delStart, delEnd, ''),
      selection: TextSelection.collapsed(offset: delStart),
    );
  }

  /// Rewrites the prefix of the caret's line — or of every line the selection
  /// covers — to [speaker].
  TextEditingValue setSpeaker(TextEditingValue value, Speaker speaker) {
    final String text = value.text;
    final int start = value.selection.start < 0 ? 0 : value.selection.start;
    final int end = value.selection.end < 0 ? start : value.selection.end;
    // The first line the selection touches, and the line its extent is on. A
    // collapsed caret sets start == end and so a single line.
    final int lineStart = _lineStartOf(text, start);
    int lineEnd = text.indexOf('\n', end);
    if (lineEnd == -1) {
      lineEnd = text.length;
    }

    final String prefix = '${ReviewBlock.wordOf(speaker, _copy)}：';
    final String rewritten = _rewriteSpan(text, lineStart, lineEnd, prefix);
    return TextEditingValue(
      text: rewritten,
      selection: TextSelection.collapsed(
        offset: _caretAfter(rewritten, prefix, end),
      ),
    );
  }

  /// Replaces the speaker prefix of every line in `[lineStart, lineEnd)`.
  String _rewriteSpan(String text, int lineStart, int lineEnd, String prefix) {
    final String span = text.substring(lineStart, lineEnd);
    final List<String> rewritten = <String>[];
    for (final String raw in span.split('\n')) {
      final String line = raw.trim();
      final Speaker? matched = ReviewBlock.speakerOf(line, _copy);
      if (matched == null) {
        rewritten.add('$prefix$line');
      } else {
        rewritten.add('$prefix${ReviewBlock.bodyOf(line, matched, _copy)}');
      }
    }
    return text.replaceRange(lineStart, lineEnd, rewritten.join('\n'));
  }

  /// Where the caret should land after a rewrite: at the end of the original
  /// selection's extent, but never before the new prefix of that line, and never
  /// past the block a shorter prefix left behind.
  int _caretAfter(String replacement, String prefix, int end) {
    final int endLineStart = _lineStartOf(replacement, end);
    final int prefixEnd = endLineStart + prefix.length;
    final int wanted = end < prefixEnd ? prefixEnd : end;
    return wanted < replacement.length ? wanted : replacement.length;
  }

  /// The first index of the line containing [offset]: just past the nearest
  /// newline before it, or 0 on the first line.
  ///
  /// `lastIndexOf` cannot say "there is nothing before the start" the way
  /// `indexOf` can — a negative `start` is a `RangeError`, not an empty search —
  /// and 0 is not the edge case it looks like. Assigning `text` onto a
  /// controller leaves its selection invalid, an invalid selection is read as 0
  /// by the callers above, and a user tapping the very start of the block asks
  /// for offset 0 as well. Spelled out at each site, all three found a newline
  /// at -1 and threw.
  ///
  /// An offset past the end is answered as the end, which is where [setSpeaker]
  /// can leave it: rewriting a prefix onto a shorter one makes the block shorter
  /// than the selection that asked for it.
  int _lineStartOf(String text, int offset) {
    if (offset <= 0) {
      return 0;
    }
    final int at = offset < text.length ? offset : text.length;
    return text.lastIndexOf('\n', at - 1) + 1;
  }

  /// The whole batch as one string, so that "is this the same batch" is one
  /// comparison.
  ///
  /// **Every row counts, not the last few.** The two signatures this repository
  /// already has — `ChatUiSnapshot.signature` and `conversationSignature` — keep
  /// the tail six lines, because the question they answer is "has the
  /// conversation moved on", and a re-read that grew by a line has. The question
  /// here is whether the panel handed down *this* batch, and a batch whose
  /// fourth line changed is a different batch even though its tail is
  /// identical: the edit made against the old one must not be kept against it.
  ///
  /// A length in front of each text keeps the join unambiguous. A plain
  /// `speaker:text` join would let a two-line batch collide with a one-line
  /// batch whose message happens to contain the separator, and a collision here
  /// is a kept edit against a batch it does not belong to.
  static String _signatureOf(List<PanelLine> lines) => lines
      .map(
        (PanelLine line) =>
            '${line.speaker.name}:${line.text.length}:${line.text}',
      )
      .join('\u0000');
}
