import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:miaotou_capabilities/miaotou_capabilities.dart';
import 'package:miaotou_capabilities_macos/miaotou_capabilities_macos.dart';

/// Turning recognised text into an attributed conversation.
///
/// The fixture is synthetic on purpose and every number in it is stated in
/// pixels, because the thresholds are fractions of the window and a fixture
/// written in fractions would hide which of them is being exercised. What it
/// reproduces is one chat window at 1000×800: a title in the header band, a
/// three-line message from the other side, a group chat's sender name above its
/// bubble, a reply of the user's own, one bubble too wide to attribute, plus the
/// three kinds of furniture that must never reach the judgement — a timestamp, a
/// button, and the input area with its blinking caret.
void main() {
  const int frameWidth = 1000;
  const int frameHeight = 800;
  final CaptureFrame frame = CaptureFrame(
    pixels: Uint8List(0),
    width: frameWidth,
    height: frameHeight,
    scaleX: 1,
    scaleY: 1,
    originX: 0,
    originY: 0,
  );

  OcrLine line(
    String text, {
    required double left,
    required double top,
    required double width,
    required double height,
    double confidence = 0.95,
  }) =>
      OcrLine(
        text: text,
        confidence: confidence,
        bounds: ScreenRect.fromLTWH(left, top, width, height),
      );

  /// One chat window, top to bottom, with each row saying why it is there.
  ///
  /// The furniture is deliberately **inside** the band the pipeline reads: a
  /// timestamp or a button placed below it would be excluded by the region test
  /// whether or not the noise rules work, and the noise rules would go untested.
  final List<OcrLine> chat = <OcrLine>[
    // Header band: the conversation's name, and one glyph of menu beside it.
    line('阿七的面试群', left: 400, top: 40, width: 160, height: 20),
    line('\u22ef', left: 620, top: 44, width: 24, height: 14),

    // The chat list, left of the pane. Not a message, and not read at all.
    line('\u5f20\u4e09', left: 60, top: 300, width: 120, height: 20),

    // Their message, wrapped over three lines.
    line('\u4f60\u4e0a\u6b21\u8bf4\u7684\u90a3\u5bb6', left: 340, top: 300, width: 300, height: 22),
    line('\u5496\u5561\u5e97\u6211\u627e\u5230\u4e86', left: 340, top: 328, width: 280, height: 22),
    line('\u5c31\u5728\u697c\u4e0b', left: 340, top: 356, width: 120, height: 22),

    // A group chat draws the sender's name in smaller type above the bubble.
    line('\u5c0f\u738b\uff1a', left: 340, top: 420, width: 60, height: 14),
    line('\u6211\u8fd9\u8fb9\u4e5f\u53ef\u4ee5', left: 340, top: 470, width: 300, height: 30),

    // The user's own reply, anchored to the right.
    line('\u90a3\u5468\u4e09\u4e0b\u5348\uff1f', left: 700, top: 560, width: 260, height: 24),

    // A bubble wide enough to span both anchors. Nobody can be named from this.
    line('\u6211\u4e0b\u5468\u4e94\u53ef\u80fd\u90fd\u8981\u51fa\u5dee', left: 340, top: 580, width: 500, height: 24),

    // Furniture, inside the band: a timestamp and a button.
    line('10:23', left: 500, top: 300, width: 60, height: 16),
    line('\u53d1\u9001', left: 900, top: 520, width: 40, height: 16),

    // The input area, below the band: the caret lives here and blinks forever.
    line('\u8f93\u5165\u6587\u5b57', left: 340, top: 700, width: 200, height: 20),
  ];

  PerceivedConversation read({List<OcrLine>? lines}) =>
      perceive(frame, lines ?? chat, maxMessages: 12);

  test('the conversation is named from the header band', () {
    expect(read().title, '阿七的面试群');
  });

  test('furniture never becomes a message', () {
    final List<String> texts =
        read().messages.map((PerceivedMessage m) => m.text).toList();
    for (final String furniture in <String>[
      '10:23', // a timestamp
      '发送', // a button
      '输入文字', // the input area's own hint
      '⋯', // a header glyph
      '张三', // the chat list
    ]) {
      expect(texts, isNot(contains(furniture)), reason: '$furniture is not speech');
    }
  });

  test('a run at least half as long as the name is part of the name', () {
    // The header holds the name and, beside it, whatever the window's buttons
    // were rendered as. Half the length is the line between "the same name, run
    // together" and "a glyph".
    final List<OcrLine> two = <OcrLine>[
      line('阿七的面试群', left: 400, top: 40, width: 160, height: 20),
      line('群聊记录', left: 580, top: 44, width: 80, height: 16),
    ];
    expect(read(lines: two).title, '阿七的面试群 群聊记录');
  });

  test('a wrapped message is one message, not three', () {
    final List<PerceivedMessage> messages = read().messages;
    expect(messages.first.text, '你上次说的那家\n咖啡店我找到了\n就在楼下');
    expect(messages.first.speaker, Speaker.other);
  });

  test('the folded bubble covers every line, not only the first', () {
    final NormalisedBlock bounds = read().messages.first.bounds;
    expect(bounds.height, greaterThan(0.028 * 3),
        reason: 'one line is 22px of 800; three of them cannot be 22px tall');
  });

  test('a sender name above a bubble becomes the sender, not a message', () {
    final PerceivedMessage grouped = read().messages[1];
    expect(grouped.text, '我这边也可以');
    expect(grouped.sender, '小王', reason: 'the colon is punctuation, not a name');
    expect(grouped.speaker, Speaker.other);
  });

  test('the right-hand side is the user and the ambiguous one is nobody', () {
    final List<PerceivedMessage> messages = read().messages;
    expect(messages[2].text, '那周三下午？');
    expect(messages[2].speaker, Speaker.me);
    expect(messages[3].text, '我下周五可能都要出差');
    expect(
      messages[3].speaker,
      Speaker.unknown,
      reason: 'a bubble spanning both anchors has no author to name, and a wrong '
          'one is worse than an unknown one',
    );
  });

  test('the newest messages are the ones kept when the cap bites', () {
    final PerceivedConversation capped = perceive(frame, chat, maxMessages: 2);
    expect(capped.messages.length, 2);
    expect(capped.messages.last.text, '我下周五可能都要出差');
  });

  test('a low-confidence line is not read as speech', () {
    final List<OcrLine> noisy = <OcrLine>[
      line('你上次说的那家', left: 340, top: 300, width: 300, height: 22, confidence: 0.10),
      line('那周三下午？', left: 700, top: 560, width: 260, height: 24),
    ];
    expect(read(lines: noisy).messages.single.text, '那周三下午？');
  });

  test('a frame with no area reads as nothing rather than dividing by zero', () {
    expect(
      normaliseBlocks(
        CaptureFrame(
          pixels: Uint8List(0),
          width: 0,
          height: 0,
          scaleX: 1,
          scaleY: 1,
          originX: 0,
          originY: 0,
        ),
        chat,
      ),
      isEmpty,
    );
  });

  test('the pipeline is fed bytes and returns text, never pixels', () {
    // The frame handed to the recogniser carries pixels; nothing downstream of
    // `normaliseBlocks` may still be holding them, so this asserts the pipeline
    // takes a frame and gives back words.
    final CaptureFrame withPixels = CaptureFrame(
      pixels: Uint8List(frameWidth * frameHeight * 4),
      width: frameWidth,
      height: frameHeight,
      scaleX: 1,
      scaleY: 1,
      originX: 0,
      originY: 0,
    );
    final PerceivedConversation result = perceive(withPixels, chat);
    expect(result.messages, isNotEmpty);
    expect(
      result.messages.every((PerceivedMessage m) => m.text.isNotEmpty),
      isTrue,
    );
  });
}
