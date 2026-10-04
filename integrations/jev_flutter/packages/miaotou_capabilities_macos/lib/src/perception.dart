/// The layout this port was calibrated against, and the pipeline that turns
/// recognised text into an attributed conversation.
///
/// ## What this is a port of
///
/// The Python port read the chat window by running Vision over a screenshot and
/// then deciding, from geometry alone, who said each line. That decision is
/// calibrated against one application's window: where the chat pane starts, how
/// high the title band sits, how small a sender name is set relative to a bubble.
/// The numbers below are those measurements, and the pipeline is the same one —
/// group blocks into visual lines, fold continuation lines, drop the sender-name
/// lines a group chat draws above each bubble, and classify what is left by which
/// side of the pane it is anchored to.
///
/// **Geometry, never a name.** Nothing here looks at *what* the text says to work
/// out who wrote it. A wrong author is worse than an unknown one, so the only
/// question asked is where the box is, and a box that spans the pane is
/// [Speaker.unknown] rather than a guess.
///
/// ## The two conversions, stated once
///
/// Vision reports a box in normalised coordinates **with the origin at the
/// bottom-left**; this file thinks in that space throughout, because every
/// threshold in it was written there. The contract's [ScreenRect] is top-origin
/// and in pixels, so [normaliseBlocks] is the single place the two meet. A second
/// conversion anywhere else would be a second set of thresholds to keep straight.
///

/// ## Why `sort` is never left to itself
///
/// Dart's `List.sort` is not stable, and this pipeline groups by "is this within
/// tolerance of the previous line" — which is exactly the kind of comparison where
/// two equal keys must keep their arrival order or the grouping changes. Every
/// comparator here therefore ends in [NormalisedBlock.order], the position the
/// block arrived in.
library;

import 'package:miaotou_capabilities/miaotou_capabilities.dart';

/// Where the chat pane begins, as a fraction of the window's width. The chat list
/// occupies everything left of it, and reading it costs about half the OCR time
/// for text that is never a message.
const double chatPaneXMin = 0.32;

/// Above this fraction of the window's height is the title band.
const double titleBarYMax = 0.90;

/// Below this fraction is the input box, which holds a blinking caret and must
/// never be read as a message.
const double inputAreaYMin = 0.24;

/// Below this, a block is treated as noise.
const double minConfidence = 0.30;

/// A sender name is set in smaller type than a bubble. Measured, not guessed.
const double userNameHeightMax = 0.026;

/// …and a bubble is never set that small.
const double messageHeightMin = 0.028;

/// Two blocks count as one visual line when their tops are this close.
const double sameLineTolerance = 0.012;

/// A line folds onto the previous one when the gap is smaller than this.
const double foldGap = 0.045;

/// …and only when their left edges are this close, so a reply that starts a new
/// column is a new message even when it follows immediately.
const double foldAlignment = 0.02;

/// The title band's rows are this close together vertically.
const double titleBandTolerance = 0.03;

/// A title shorter than this is a glyph the OCR made up rather than a name.
const int titleMinLength = 4;

/// One recognised line, in the window's own normalised space.
///
/// Bottom-left origin, matching Vision, so the thresholds above can be compared
/// against these numbers without a conversion in the reader's head.
final class NormalisedBlock {
  NormalisedBlock({
    required this.text,
    required this.confidence,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.order,
  });

  final String text;
  final double confidence;

  /// Fraction of the frame's width, from its left edge.
  final double x;

  /// Fraction of the frame's height, from its **bottom** edge.
  final double y;
  final double width;
  final double height;

  /// Arrival order. The tiebreaker every comparator in this file ends with.
  final int order;

  double get right => x + width;

  /// The same box with a top-origin y, which is how the folding pass reads it.
  double get top => 1 - y - height;

  NormalisedBlock copyWith({double? y, double? x, double? width, double? height, double? confidence}) =>
      NormalisedBlock(
        text: text,
        confidence: confidence ?? this.confidence,
        x: x ?? this.x,
        y: y ?? this.y,
        width: width ?? this.width,
        height: height ?? this.height,
        order: order,
      );

  @override
  String toString() => 'NormalisedBlock("$text" @ $x,$y ${width}x$height)';
}

/// Converts the contract's top-origin pixel rectangles into bottom-origin
/// normalised ones.
///
/// This is the only place the two coordinate systems meet. It also drops blocks
/// with no area: a zero-height box cannot be classified, and letting one through
/// would put a line at a position nothing else agrees with.
List<NormalisedBlock> normaliseBlocks(CaptureFrame frame, List<OcrLine> lines) {
  if (frame.width <= 0 || frame.height <= 0) {
    return const <NormalisedBlock>[];
  }
  final List<NormalisedBlock> blocks = <NormalisedBlock>[];
  for (int i = 0; i < lines.length; i++) {
    final OcrLine line = lines[i];
    final ScreenRect b = line.bounds;
    if (b.isEmpty) {
      continue;
    }
    final double left = b.left / frame.width;
    final double width = b.width / frame.width;
    final double height = b.height / frame.height;
    final double top = b.top / frame.height;
    blocks.add(
      NormalisedBlock(
        text: line.text.trim(),
        confidence: line.confidence,
        x: left,
        y: 1 - top - height,
        width: width,
        height: height,
        order: i,
      ),
    );
  }
  return blocks;
}

/// A timestamp line, which is chrome rather than speech.
final RegExp _timestamp = RegExp(r'^\d{1,2}:\d{2}(:\d{2})?$');

/// The fixed furniture of the window: buttons, hints, the folded-chat banner.
///
/// `\w` is ASCII-only in a Dart regular expression where Python's is Unicode-aware,
/// which is why the CJK range is written out — the intent was always "letters or
/// Chinese", and copying the Python class across verbatim would have silently
/// narrowed it.
final List<RegExp> _uiNoise = <RegExp>[
  RegExp('折叠聊天'),
  RegExp(r'共\s*\d+'),
  RegExp('搜索'),
  RegExp('发送'),
  RegExp('拖入文件'),
  RegExp('按住说话'),
  RegExp('语音输入文字'),
  RegExp('按住鼠标'),
  RegExp('按住 说话'),
  RegExp('输入文字'),
  RegExp(r'^[\w\-一-龥]{2,20}[:：].*\.\.\..*[）)]$'),
];

/// Whether a block is furniture rather than something somebody said.
bool isNoise(NormalisedBlock block) {
  if (block.confidence < minConfidence || block.text.isEmpty) {
    return true;
  }
  if (_timestamp.hasMatch(block.text)) {
    return true;
  }
  return _uiNoise.any((RegExp pattern) => pattern.hasMatch(block.text));
}

/// Reads the conversation's name out of the header band.
///
/// Two rows live up there: the title, and — when a chat is collapsed — a banner.
/// The topmost readable band is taken and the banner is dropped, and within the
/// band the longest run of text wins, because the header also holds the
/// chat-info, call and menu glyphs, which OCR turns into short junk.
String extractChatTitle(List<NormalisedBlock> blocks) {
  final List<NormalisedBlock> candidates = blocks
      .where((NormalisedBlock b) =>
          b.x >= chatPaneXMin &&
          b.y > titleBarYMax &&
          b.confidence >= minConfidence &&
          b.text.length >= 2 &&
          !isNoise(b))
      .toList();
  if (candidates.isEmpty) {
    return '';
  }
  candidates.sort((NormalisedBlock a, NormalisedBlock b) {
    final int byY = b.y.compareTo(a.y);
    if (byY != 0) {
      return byY;
    }
    final int byLength = b.text.length.compareTo(a.text.length);
    return byLength != 0 ? byLength : a.order.compareTo(b.order);
  });

  final double topY = candidates.first.y;
  final List<NormalisedBlock> band = candidates
      .where((NormalisedBlock b) => topY - b.y < titleBandTolerance)
      .toList();

  NormalisedBlock? longest;
  for (final NormalisedBlock b in band) {
    if (longest == null || b.text.length > longest.text.length) {
      longest = b;
    }
  }
  if (longest == null || longest.text.length < titleMinLength) {
    return '';
  }
  final int floor = (longest.text.length * 0.5).floor();
  final List<NormalisedBlock> keep = band
      .where((NormalisedBlock b) => b.text.length >= floor)
      .toList()
    ..sort((NormalisedBlock a, NormalisedBlock b) {
      final int byX = a.x.compareTo(b.x);
      return byX != 0 ? byX : a.order.compareTo(b.order);
    });
  return keep.map((NormalisedBlock b) => b.text).join(' ').trim();
}

/// Which side of the pane a box is anchored to.
///
/// Conservative on purpose: a centre measurement alone cannot identify a wide
/// bubble, so text spanning both anchors stays [Speaker.unknown]. An ambiguous
/// line is kept for context and never treated as an incoming reply, because the
/// cost of guessing wrong is a draft aimed at the wrong person.
Speaker speakerFor(NormalisedBlock box) {
  if (box.x >= 0.66 || (box.x >= 0.50 && box.right >= 0.80)) {
    return Speaker.me;
  }
  if (box.x <= 0.50 && box.right < 0.80) {
    return Speaker.other;
  }
  return Speaker.unknown;
}

/// One attributed line of the conversation.
final class PerceivedMessage {
  const PerceivedMessage({
    required this.text,
    required this.speaker,
    required this.confidence,
    required this.bounds,
    this.sender,
  });

  final String text;
  final Speaker speaker;
  final double confidence;

  /// The whole bubble, in normalised coordinates — every folded line, not just
  /// the first, because a box drawn around half a message points at nothing.
  final NormalisedBlock bounds;

  /// The name a group chat draws above the bubble, when there was one.
  final String? sender;

  @override
  String toString() => 'PerceivedMessage(${speaker.name}, ${text.length} chars)';
}

/// The whole read: the conversation's name and its messages, oldest first.
final class PerceivedConversation {
  const PerceivedConversation({required this.title, required this.messages});

  final String title;
  final List<PerceivedMessage> messages;

  @override
  String toString() => 'PerceivedConversation("$title", ${messages.length} messages)';
}

/// One read of the window: recognise, then attribute.
PerceivedConversation perceive(
  CaptureFrame frame,
  List<OcrLine> lines, {
  int maxMessages = 12,
}) {
  final List<NormalisedBlock> blocks = normaliseBlocks(frame, lines);
  return PerceivedConversation(
    title: extractChatTitle(blocks),
    messages: extractMessages(blocks, maxMessages: maxMessages),
  );
}

/// Everything the window says, oldest first, capped at the newest [maxMessages].
List<PerceivedMessage> extractMessages(
  List<NormalisedBlock> blocks, {
  int maxMessages = 12,
}) {
  final List<NormalisedBlock> chat = blocks
      .where((NormalisedBlock b) =>
          b.x >= chatPaneXMin &&
          b.y > inputAreaYMin &&
          b.y < titleBarYMax &&
          !isNoise(b))
      .map((NormalisedBlock b) => b.copyWith(y: b.top))
      .toList();
  if (chat.isEmpty) {
    return const <PerceivedMessage>[];
  }

  chat.sort((NormalisedBlock a, NormalisedBlock b) {
    final int byY = a.y.compareTo(b.y);
    return byY != 0 ? byY : a.order.compareTo(b.order);
  });

  // Blocks on one visual line are one line of text, joined left to right.
  final List<List<NormalisedBlock>> grouped = <List<NormalisedBlock>>[];
  for (final NormalisedBlock b in chat) {
    if (grouped.isNotEmpty &&
        (b.y - grouped.last.first.y).abs() < sameLineTolerance) {
      grouped.last.add(b);
    } else {
      grouped.add(<NormalisedBlock>[b]);
    }
  }

  final List<NormalisedBlock> lines = <NormalisedBlock>[];
  for (final List<NormalisedBlock> group in grouped) {
    group.sort((NormalisedBlock a, NormalisedBlock b) {
      final int byX = a.x.compareTo(b.x);
      return byX != 0 ? byX : a.order.compareTo(b.order);
    });
    final double left = group.first.x;
    double right = group.first.right;
    double height = group.first.height;
    double confidence = group.first.confidence;
    for (final NormalisedBlock b in group) {
      if (b.right > right) {
        right = b.right;
      }
      if (b.height > height) {
        height = b.height;
      }
      if (b.confidence < confidence) {
        confidence = b.confidence;
      }
    }
    lines.add(
      NormalisedBlock(
        text: group.map((NormalisedBlock b) => b.text).join(' '),
        confidence: confidence,
        x: left,
        y: group.first.y,
        width: right - left,
        height: height,
        order: group.first.order,
      ),
    );
  }

  final List<_Folded> folded = <_Folded>[];
  for (final NormalisedBlock b in lines) {
    final Speaker side = speakerFor(b);
    final _Folded? last = folded.isEmpty ? null : folded.last;
    final double gap = last == null ? 1.0 : b.y - last.lastY;
    final bool aligned = last != null && (b.x - last.x).abs() < foldAlignment;
    final bool compatible = last != null &&
        (side == last.speaker || side == Speaker.unknown || last.speaker == Speaker.unknown);

    if (last != null && aligned && compatible && gap >= 0 && gap < foldGap) {
      last.add(b, side);
    } else {
      folded.add(_Folded(b, side));
    }
  }

  // A group chat draws the sender's name as a short line above the bubble. It is
  // recognised by two independent signals — set in smaller type, and with
  // message-sized type under it — because a wrong name is worse than no name. A
  // small line with nothing message-sized under it is dropped outright: it is the
  // same glyph above an image-only message, and it is never something to judge.
  final List<PerceivedMessage> named = <PerceivedMessage>[];
  for (int i = 0; i < folded.length; i++) {
    final _Folded m = folded[i];
    final _Folded? next = i + 1 < folded.length ? folded[i + 1] : null;
    if (m.speaker == Speaker.other &&
        next != null &&
        next.speaker == m.speaker &&
        m.isSingleLine &&
        m.text.length <= 16 &&
        m.height < userNameHeightMax &&
        next.height >= messageHeightMin &&
        (next.y - m.y) > 0.035) {
      next.sender = m.text.trim().replaceFirst(RegExp(r'[:：]\s*$'), '');
      continue;
    }
    if (m.speaker == Speaker.other && m.isSingleLine && m.text.length <= 16 && m.height < userNameHeightMax) {
      continue;
    }
    named.add(m.toMessage());
  }

  if (named.length <= maxMessages) {
    return named;
  }
  return named.sublist(named.length - maxMessages);
}

/// A message while it is still being folded. Top-origin y, like the pass above.
final class _Folded {
  _Folded(NormalisedBlock first, this.speaker)
      : text = first.text,
        parts = <String>[first.text],
        confidence = first.confidence,
        x = first.x,
        y = first.y,
        width = first.width,
        height = first.height,
        lastY = first.y,
        order = first.order;

  final List<String> parts;
  String text;
  double confidence;
  double x;
  double y;
  double width;
  double height;

  /// The top of the most recent folded line. The fold test measures against this
  /// rather than against [y], because measuring against the first line makes every
  /// line from the third on look two line-pitches away and splits a long message
  /// into chunks the judgement only ever sees the tail of.
  double lastY;
  Speaker speaker;
  String? sender;
  final int order;

  bool get isSingleLine => !text.contains('\n');

  void add(NormalisedBlock block, Speaker side) {
    parts.add(block.text);
    text = parts.join('\n');
    if (block.confidence < confidence) {
      confidence = block.confidence;
    }
    final double bottom = y + height > block.y + block.height ? y + height : block.y + block.height;
    final double right = x + width > block.right ? x + width : block.right;
    if (block.x < x) {
      x = block.x;
    }
    width = right - x;
    height = bottom - y;
    // Re-classified from the grown box rather than inheriting: OCR can shift a
    // short continuation's left edge, and a fold that started from a
    // mis-classified first line would otherwise keep the wrong author.
    speaker = speakerFor(NormalisedBlock(
      text: text,
      confidence: confidence,
      x: x,
      y: y,
      width: width,
      height: height,
      order: order,
    ));
    lastY = block.y;
  }

  PerceivedMessage toMessage() => PerceivedMessage(
        text: text,
        speaker: speaker,
        confidence: confidence,
        sender: sender,
        bounds: NormalisedBlock(
          text: text,
          confidence: confidence,
          x: x,
          y: y,
          width: width,
          height: height,
          order: order,
        ),
      );
}
