import 'package:flutter_test/flutter_test.dart';
import 'package:miaotou_app/src/design/copy.dart';
import 'package:miaotou_app/src/panel/protocol.dart';
import 'package:miaotou_app/src/panel/review_block.dart';
import 'package:miaotou_capabilities/miaotou_capabilities.dart'
    show Speaker;

/// The block text the review edits, and the rules that bind it to the typed
/// lines the protocol carries (ADR-0025).
void main() {
  const AppCopy copy = AppCopy.zh;

  // `PanelLine` is a plain value with no equality, so a batch is read as the
  // `speaker:text` pairs the panel test already uses for the same reason.
  List<String> asStrings(List<PanelLine> lines) => lines
      .map((PanelLine line) => '${line.speaker.name}:${line.text}')
      .toList();

  group('serialising a batch', () {
    test('every line gets its prefix, including 未定', () {
      expect(
        ReviewBlock.fromLines(const <PanelLine>[
          PanelLine(speaker: Speaker.me, text: '在吗'),
          PanelLine(speaker: Speaker.other, text: '在的'),
          PanelLine(speaker: Speaker.unknown, text: '嗯'),
        ], copy),
        '我：在吗\n对方：在的\n未定：嗯',
      );
    });
  });

  group('parsing a block', () {
    test('a prefix names the speaker and the rest is the text', () {
      expect(
        asStrings(ReviewBlock.toLines('我：在吗\n对方：在的', copy)),
        <String>['me:在吗', 'other:在的'],
      );
    });

    test('a half-width colon and a space after it are the same prefix', () {
      expect(
        asStrings(ReviewBlock.toLines('我: 在吗\n对方:在的', copy)),
        <String>['me:在吗', 'other:在的'],
      );
    });

    test('a line with no prefix inherits the speaker above it', () {
      expect(
        asStrings(ReviewBlock.toLines('我：在吗\n在的', copy)),
        <String>['me:在吗', 'me:在的'],
        reason:
            'a multi-line paste after 我： is 我 all the way down, which is '
            'the failure ADR-0022 named',
      );
    });

    test('a first line with no prefix is 未定', () {
      expect(
        asStrings(ReviewBlock.toLines('在吗\n对方：在的', copy)),
        <String>['unknown:在吗', 'other:在的'],
      );
    });

    test('blank lines are dropped and surviving lines are trimmed', () {
      expect(
        asStrings(ReviewBlock.toLines(' 我：在吗 \n\n   \n 对方： 在的 ', copy)),
        <String>['me:在吗', 'other:在的'],
      );
    });

    test('a bare prefix is dropped but still sets the inheritance', () {
      expect(
        asStrings(ReviewBlock.toLines('对方：\n在的', copy)),
        <String>['other:在的'],
        reason: 'a line with only a prefix is not a message, but it does say '
            'what the next line is',
      );
    });

    test('a message that merely starts with a speaker word is not a prefix', () {
      expect(
        asStrings(ReviewBlock.toLines('我\n对方\n在吗', copy)),
        <String>['unknown:我', 'unknown:对方', 'unknown:在吗'],
        reason: 'a speaker word without a colon is text, not an attribution',
      );
    });
  });

  test('serialising then parsing round-trips a batch exactly', () {
    const List<PanelLine> batch = <PanelLine>[
      PanelLine(speaker: Speaker.me, text: '在吗'),
      PanelLine(speaker: Speaker.other, text: '在的'),
      PanelLine(speaker: Speaker.unknown, text: '嗯'),
    ];
    expect(
      asStrings(ReviewBlock.toLines(ReviewBlock.fromLines(batch, copy), copy)),
      <String>['me:在吗', 'other:在的', 'unknown:嗯'],
    );
  });
}
