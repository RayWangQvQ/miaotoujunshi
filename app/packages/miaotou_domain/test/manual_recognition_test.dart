import 'dart:typed_data';

import 'package:miaotou_capabilities/miaotou_capabilities.dart';
import 'package:miaotou_domain/miaotou_domain.dart';
import 'package:test/test.dart';

/// The whole-frame calibration, pinned (ADR-0019 decision 5, ADR-0011).
///
/// Two thresholds decide what the model is told about a photographed
/// conversation: the 1.2× line gap that turns lines into messages, and the
/// half-frame boundary that guesses who said each one. Both are guesses
/// calibrated on a device, and a fixture is what stops one from moving silently
/// — which is the whole reason this arithmetic lives in Dart rather than in the
/// retained Kotlin (ADR-0018's rejected alternative).
///
/// The rectangles are synthetic: no screenshot, no device, no recogniser.
void main() {
  group('line grouping', () {
    test('lines closer than the gap factor become one message', () {
      final RecognisedCapture capture = recognise(
        <OcrLine>[
          line('你吃了吗', left: 40, top: 100, right: 300, bottom: 140),
          // 20pt below the previous line, against a 40pt line height: one bubble.
          line('我还没吃', left: 40, top: 160, right: 300, bottom: 200),
        ],
      );

      expect(capture.lines, hasLength(1));
      expect(capture.lines.single.text, '你吃了吗 我还没吃');
    });

    test('a gap past the factor starts a new message', () {
      final RecognisedCapture capture = recognise(
        <OcrLine>[
          line('你吃了吗', left: 40, top: 100, right: 300, bottom: 140),
          // 60pt below a 40pt line: 60 > 40 * 1.2, so a new bubble.
          line('我还没吃', left: 40, top: 200, right: 300, bottom: 240),
        ],
      );

      expect(capture.lines, hasLength(2));
      expect(capture.lines.first.text, '你吃了吗');
      expect(capture.lines.last.text, '我还没吃');
    });

    test('a gap exactly at the factor still joins', () {
      // The comparison is strict, so 48pt against 40pt * 1.2 is not a break.
      final RecognisedCapture capture = recognise(
        <OcrLine>[
          line('上一句', left: 40, top: 100, right: 300, bottom: 140),
          line('下一句', left: 40, top: 188, right: 300, bottom: 228),
        ],
      );

      expect(capture.lines, hasLength(1));
    });

    test('blank lines and standalone timestamps are dropped', () {
      final RecognisedCapture capture = recognise(
        <OcrLine>[
          line('8:11', left: 440, top: 60, right: 520, bottom: 90),
          line('   ', left: 40, top: 100, right: 300, bottom: 140),
          line('在的', left: 40, top: 160, right: 300, bottom: 200),
          line('下午 3:20', left: 440, top: 220, right: 560, bottom: 250),
        ],
      );

      expect(capture.lines, hasLength(1));
      expect(capture.lines.single.text, '在的');
    });

    test('a timestamp inside a bubble is kept as its content', () {
      final RecognisedCapture capture = recognise(
        <OcrLine>[
          line('会议改到 8:11', left: 40, top: 100, right: 400, bottom: 140),
        ],
      );

      expect(capture.lines.single.text, '会议改到 8:11');
    });

    test('a dated timestamp is chrome, not speech', () {
      // The old pattern matched only a bare `HH:MM`, so a day divider rendered
      // as `10/04 11:39` survived as a message and was folded into a speaker.
      final RecognisedCapture capture = recognise(
        <OcrLine>[
          line('在的', left: 40, top: 100, right: 300, bottom: 140),
          line('10/04 11:39', left: 440, top: 160, right: 560, bottom: 190),
          line('2026-10-04 11:39', left: 440, top: 210, right: 620, bottom: 240),
          line('10月4日 11:39', left: 440, top: 260, right: 560, bottom: 290),
          line('刚刚你发的', left: 40, top: 320, right: 300, bottom: 360),
        ],
      );

      expect(capture.lines.map((ChatLine l) => l.text).toList(), <String>[
        '在的',
        '刚刚你发的',
      ]);
    });

    test('a dated divider records its time on the message below it', () {
      // The divider above a message is that message's time; the message before
      // it keeps null, and a divider with no year is dropped without a time.
      final RecognisedCapture capture = recognise(
        <OcrLine>[
          line('昨天说的', left: 40, top: 100, right: 300, bottom: 140),
          line('10/04 11:39', left: 440, top: 160, right: 560, bottom: 190),
          line('2026-10-05 08:30:05', left: 440, top: 210, right: 640, bottom: 240),
          line('今天这个', left: 40, top: 260, right: 300, bottom: 300),
        ],
      );

      expect(capture.lines, hasLength(2));
      expect(capture.lines[0].text, '昨天说的');
      expect(capture.lines[0].occurredAt, isNull,
          reason: 'a divider sits above the message it introduces, so the one '
              'before it has no time of its own');
      expect(capture.lines[1].text, '今天这个');
      expect(capture.lines[1].occurredAt, DateTime(2026, 10, 5, 8, 30, 5),
          reason: 'the year-bearing divider above it names the message time');
    });

    test('no lines at all produces no capture and no split', () {
      final RecognisedCapture capture = recognise(<OcrLine>[]);

      expect(capture.lines, isEmpty);
      expect(capture.sidesSplit, isFalse);
    });
  });

  group('side inference', () {
    test('both sides present: left is the other party, right is the user', () {
      final RecognisedCapture capture = recognise(
        <OcrLine>[
          line('在吗', left: 40, top: 100, right: 240, bottom: 140),
          line('在的', left: 760, top: 200, right: 960, bottom: 240),
        ],
      );

      expect(capture.sidesSplit, isTrue);
      expect(capture.lines.first.speaker, Speaker.other);
      expect(capture.lines.last.speaker, Speaker.me);
    });

    test('every message leaning left means the geometry proved nothing', () {
      // Feishu's layout, which is the counter-example ADR-0019 names: it
      // left-aligns everybody, so a threshold on the centre reads the whole
      // conversation as incoming.
      final RecognisedCapture capture = recognise(
        <OcrLine>[
          line('在吗', left: 40, top: 100, right: 240, bottom: 140),
          line('在的', left: 40, top: 200, right: 200, bottom: 240),
        ],
      );

      expect(capture.sidesSplit, isFalse);
      expect(
        capture.lines.map((ChatLine line) => line.speaker),
        everyElement(Speaker.other),
      );
    });

    test('every message leaning right is also reported as unsplit', () {
      // A one-sided frame is indistinguishable from a left-aligning application
      // by this test, and the conservative direction is the other party: the
      // model then drafts a reply to it rather than treating it as the user's own
      // words. Recorded in ADR-0019's consequences.
      final RecognisedCapture capture = recognise(
        <OcrLine>[
          line('在吗', left: 760, top: 100, right: 960, bottom: 140),
          line('在的', left: 800, top: 200, right: 960, bottom: 240),
        ],
      );

      expect(capture.sidesSplit, isFalse);
      expect(
        capture.lines.map((ChatLine line) => line.speaker),
        everyElement(Speaker.other),
      );
    });

    test('a group is placed by its whole box, not its first line', () {
      // A wrapped bubble whose first line hugs the left margin and whose last
      // line runs to the right of centre is still the user's.
      final RecognisedCapture capture = recognise(
        <OcrLine>[
          line('别人说的', left: 40, top: 100, right: 220, bottom: 140),
          line('我这条很长，长到中心过了中线', left: 600, top: 200, right: 960, bottom: 240),
          line('接着写第二行', left: 600, top: 220, right: 960, bottom: 260),
        ],
      );

      expect(capture.sidesSplit, isTrue);
      expect(capture.lines.first.speaker, Speaker.other);
      expect(capture.lines.last.speaker, Speaker.me);
      expect(capture.lines.last.text, '我这条很长，长到中心过了中线 接着写第二行');
    });
  });

  group('geometry carried through', () {
    test('a group rectangle is mapped back to screen coordinates', () {
      final CaptureFrame scaled = frame(
        width: 1000,
        height: 2000,
        scaleX: 2,
        scaleY: 2,
        originX: 30,
        originY: 50,
      );
      final RecognisedCapture capture = groupRecognisedLines(
        <OcrLine>[
          line('在吗', left: 80, top: 200, right: 400, bottom: 280),
        ],
        frame: scaled,
      );

      // Bitmap 80..400 at 2× from origin 30 is screen 70..230.
      final ScreenRect bounds = capture.lines.single.bounds!;
      expect(bounds.left, 70);
      expect(bounds.right, 230);
      expect(bounds.top, 150);
      expect(bounds.bottom, 190);
    });

    test('a zero-width frame cannot call anything the user\'s own', () {
      final RecognisedCapture capture = groupRecognisedLines(
        <OcrLine>[line('在吗', left: 900, top: 100, right: 990, bottom: 140)],
        frame: frame(width: 0),
      );

      expect(capture.sidesSplit, isFalse);
      expect(capture.lines.single.speaker, Speaker.other);
    });
  });
}

/// One message bubble's OCR output.
OcrLine line(
  String text, {
  required double left,
  required double top,
  required double right,
  required double bottom,
  double confidence = 1,
}) =>
    OcrLine(
      text: text,
      bounds: ScreenRect(left: left, top: top, right: right, bottom: bottom),
      confidence: confidence,
    );

/// A capture frame. The default is 1:1 and anchored at the origin, so a test
/// that does not care about the mapping can read bitmap coordinates as screen
/// ones.
CaptureFrame frame({
  double width = 1000,
  double height = 2000,
  double scaleX = 1,
  double scaleY = 1,
  double originX = 0,
  double originY = 0,
}) =>
    CaptureFrame(
      pixels: Uint8List.fromList(<int>[0x00, 0x00, 0x00, 0x00]),
      width: (width * scaleX).round(),
      height: (height * scaleY).round(),
      scaleX: scaleX,
      scaleY: scaleY,
      originX: originX,
      originY: originY,
    );

/// One frame of OCR output, read at 1:1 with no origin offset.
RecognisedCapture recognise(List<OcrLine> lines) =>
    groupRecognisedLines(lines, frame: frame());
