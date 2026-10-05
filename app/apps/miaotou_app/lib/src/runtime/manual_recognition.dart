/// Grouping and side inference for a manual whole-frame capture.
///
/// The accessibility tree answers "who said this" with a container's edge; a
/// screenshot answers it with nothing, because [OcrLine] is a string and a
/// rectangle and an author is not a property of text. So a whole-frame capture
/// has to build its own pseudo-bubbles and guess the side from where each one
/// sits. ADR-0019 is where that guess is decided; this file is the whole of its
/// arithmetic, kept pure so a synthetic fixture can pin it without a device.
///
/// Nothing here calls a capability, reads a clock or knows about a widget. The
/// caller supplies a [CaptureFrame]; every constant it depends on is a named
/// constant at the top, because that is what calibration moves.
library;

import 'dart:math' as math;

import 'package:miaotou_capabilities/miaotou_capabilities.dart';

/// A new pseudo-bubble starts when the vertical gap exceeds this multiple of the
/// previous line's height. Measured on real captures in the retired port before
/// the freeze; keep the value and the comparison shape together.
const double ocrLineGapFactor = 1.2;

/// The horizontal centre, as a fraction of the frame's width, above which a
/// group is read as the user's own.
///
/// Half the frame, which is the same rule the adapters use on a bubble's centre
/// (`ChatAppAdapter.kt`: `cx > width / 2`). It is a guess and it is meant to be
/// one: applications that align every message the same way defeat it, and
/// [RecognisedCapture.sidesSplit] is how the caller finds out that they did.
const double sideBoundary = 0.5;

/// A timestamp on a line of its own carries no conversational content.
///
/// Anchored on purpose, and matched by the same expression in the retained
/// Kotlin (`RetainedCaptureService.PURE_TIME`): the two whole-frame paths must
/// agree about which lines are content, or the same screen yields two different
/// transcripts depending on who asked for the capture. The meridiem may sit on
/// either side, because applications disagree about that.
///
/// The two meridiem words are written as escapes rather than as themselves only
/// because `lib/` outside `design/copy.dart` may not hold a Han character in a
/// string literal — the pattern is not copy, and the audit that enforces that
/// rule is right not to care.
final RegExp _pureTime = RegExp(
  '^\\s*(\u4e0a\u5348|\u4e0b\u5348|AM|PM|am|pm)?'
  '\\s*\\d{1,2}[:：]\\d{2}'
  '\\s*(\u4e0a\u5348|\u4e0b\u5348|AM|PM|am|pm)?\\s*\$',
);

/// One frame's worth of recognised conversation.
final class RecognisedCapture {
  const RecognisedCapture({required this.lines, required this.sidesSplit});

  /// The pseudo-bubbles, in the order the recogniser put them on screen.
  final List<ChatLine> lines;

  /// Whether the geometry found both sides.
  ///
  /// False means every group leaned the same way, so the framing gives no
  /// evidence about who is who — an application that left-aligns everybody, or a
  /// frame with one side talking. When it is false [lines] are all attributed to
  /// the other party, which is what the retired port did unconditionally, and the
  /// caller is expected to say so on the panel.
  final bool sidesSplit;

  @override
  String toString() =>
      'RecognisedCapture(${lines.length} lines, split: $sidesSplit)';
}

/// Turns one frame's OCR output into pseudo-bubbles with a guessed side.
///
/// [frame] supplies both the width the side is measured against and the mapping
/// that puts each group's rectangle back into screen coordinates, so the
/// rectangle a caller sees is in the same space as a tree line's `bounds`.
RecognisedCapture groupRecognisedLines(
  List<OcrLine> raw, {
  required CaptureFrame frame,
}) {
  final List<OcrLine> usable = raw
      .where((OcrLine line) => line.text.trim().isNotEmpty)
      .where((OcrLine line) => !_pureTime.hasMatch(line.text.trim()))
      .toList()
    ..sort((OcrLine a, OcrLine b) => a.bounds.top.compareTo(b.bounds.top));

  final List<_Group> groups = <_Group>[];
  OcrLine? previous;
  for (final OcrLine line in usable) {
    final bool starts = previous == null ||
        line.bounds.top - previous.bounds.bottom >
            math.max(previous.bounds.height, 1.0) * ocrLineGapFactor;
    if (starts) {
      groups.add(_Group());
    }
    groups.last.add(line);
    previous = line;
  }

  final bool anyMe = groups.any((_Group group) => group.isMine(frame.width));
  final bool anyOther = groups.any((_Group group) => !group.isMine(frame.width));
  final bool sidesSplit = anyMe && anyOther;

  return RecognisedCapture(
    sidesSplit: sidesSplit,
    lines: <ChatLine>[
      for (final _Group group in groups)
        ChatLine(
          speaker: sidesSplit && group.isMine(frame.width)
              ? Speaker.me
              : Speaker.other,
          text: group.text,
          bounds: frame.mapToScreen(group.bounds),
        ),
    ],
  );
}

/// The lines of one pseudo-bubble, accumulated as the scan walks down the frame.
final class _Group {
  final List<OcrLine> _lines = <OcrLine>[];

  void add(OcrLine line) => _lines.add(line);

  /// The group's words, joined the way a wrapped bubble reads as one message.
  String get text =>
      _lines.map((OcrLine line) => line.text.trim()).join(' ').trim();

  /// The rectangle the whole bubble occupies, in the frame's bitmap coordinates.
  ScreenRect get bounds {
    double left = _lines.first.bounds.left;
    double top = _lines.first.bounds.top;
    double right = _lines.first.bounds.right;
    double bottom = _lines.first.bounds.bottom;
    for (final OcrLine line in _lines) {
      left = math.min(left, line.bounds.left);
      top = math.min(top, line.bounds.top);
      right = math.max(right, line.bounds.right);
      bottom = math.max(bottom, line.bounds.bottom);
    }
    return ScreenRect(left: left, top: top, right: right, bottom: bottom);
  }

  bool isMine(int frameWidth) {
    if (frameWidth <= 0) {
      return false;
    }
    final ScreenRect box = bounds;
    return (box.left + box.right) / 2 / frameWidth > sideBoundary;
  }
}
