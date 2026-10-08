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
/// A date is part of the same divider: a chat stamps `10/04 11:39` or
/// `2026-10-04 11:39` between days, and that line is no more speech than a bare
/// `11:39`. The date separator accepts `-`, `/`, `.` and `年/月/日`, and the
/// date may precede the time with or without a year.
///
/// The two meridiem words are escapes rather than themselves because this file
/// began in the application package, where a Han character in a string literal
/// outside the copy file is an audit failure — the pattern is not copy, and the
/// audit is right not to care. The escapes came along when the file moved into
/// the domain, and are kept: no audit here would object either way, but the
/// pattern is not read by a person, so spelling the words out would only put
/// copy in a place that has no business holding any.
final RegExp _timestampShape = RegExp(
  '^\\s*'
  '(?:'
  '(?:(\\d{4})[-/.年](\\d{1,2})[-/.月](\\d{1,2})[日]?\\s*)?'
  '(?:\\d{1,2}[-/.月]\\d{1,2}[日]?\\s*)?'
  '(?:\u4e0a\u5348|\u4e0b\u5348|AM|PM|am|pm)?'
  '\\s*(\\d{1,2})[:：](\\d{2})(?::(\\d{2}))?'
  '\\s*(?:\u4e0a\u5348|\u4e0b\u5348|AM|PM|am|pm)?'
  ')'
  '\\s*\$',
);

/// Whether [text] is a timestamp divider of any shape, year or not.
///
/// The drop gate: a `10/04 11:39` or a bare `11:39` is chrome to remove before
/// grouping, whether or not it carries a year worth recording.
bool isTimestampShape(String text) => _timestampShape.hasMatch(text);

/// The [DateTime] a timestamp line names, or null when it has no year to pin to.
///
/// A divider without a year (`10/04 11:39`, `11:39`) is still dropped by
/// [isTimestampShape] — this only answers whether there is a time worth
/// recording, and those shapes have no year to record. The parse is strict: an
/// impossible day or hour yields null, and the line is kept as ordinary text
/// rather than silently mis-dated.
DateTime? timestampOf(String text) {
  final RegExpMatch? match = _timestampShape.firstMatch(text);
  if (match == null) {
    return null;
  }
  final int? y = int.tryParse(match.group(1) ?? '');
  final int? month = int.tryParse(match.group(2) ?? '');
  final int? day = int.tryParse(match.group(3) ?? '');
  final int? h = int.tryParse(match.group(4) ?? '');
  final int? mi = int.tryParse(match.group(5) ?? '');
  final int s = int.tryParse(match.group(6) ?? '0') ?? 0;
  if (y == null || month == null || day == null || h == null || mi == null) {
    return null;
  }
  if (h > 23 || mi > 59 || s > 59) {
    return null;
  }
  final DateTime parsed = DateTime(y, month, day, h, mi, s);
  if (parsed.year != y || parsed.month != month || parsed.day != day) {
    return null;
  }
  return parsed;
}


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
  final List<OcrLine> usable = <OcrLine>[];
  final List<_Stamp> stamps = <_Stamp>[];
  for (final OcrLine line in raw) {
    final String text = line.text.trim();
    if (text.isEmpty) {
      continue;
    }
    if (isTimestampShape(text)) {
      final DateTime? time = timestampOf(text);
      if (time != null) {
        stamps.add(_Stamp(time, line.bounds.top));
      }
      continue;
    }
    usable.add(line);
  }
  usable.sort((OcrLine a, OcrLine b) => a.bounds.top.compareTo(b.bounds.top));

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
          occurredAt: _stampAbove(group.bounds.top, stamps),
          bounds: frame.mapToScreen(group.bounds),
        ),
    ],
  );
}

/// The time of the timestamp divider nearest above a group's top, else null.
///
/// A chat stamps a divider before the message it introduces, so a group owns the
/// most recent stamp at or above its top. A stamp above no message (a divider at
/// the bottom of the frame) is simply unread — there is no message it names.
DateTime? _stampAbove(double top, List<_Stamp> stamps) {
  DateTime? nearest;
  double nearestTop = double.negativeInfinity;
  for (final _Stamp stamp in stamps) {
    if (stamp.top <= top && stamp.top > nearestTop) {
      nearestTop = stamp.top;
      nearest = stamp.time;
    }
  }
  return nearest;
}

/// A timestamp divider's value and its vertical position.
final class _Stamp {
  const _Stamp(this.time, this.top);

  final DateTime time;
  final double top;
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
