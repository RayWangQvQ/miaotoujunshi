import 'package:flutter/services.dart' show TextEditingValue, TextSelection;
import 'package:flutter_test/flutter_test.dart';
import 'package:miaotou_app/src/design/copy.dart';
import 'package:miaotou_app/src/panel/protocol.dart';
import 'package:miaotou_app/src/panel/review_session.dart';
import 'package:miaotou_capabilities/miaotou_capabilities.dart' show Speaker;

/// The review's rules, away from the panel that shows them (ADR-0025).
///
/// Every one of these used to need the whole form pumped: the caret's own
/// operations were private members of a 975-line widget, and the rule the form
/// cannot see — that a republish repeating the batch must not wipe an edit in
/// progress — had no test at all.
void main() {
  const AppCopy copy = AppCopy.zh;

  const List<PanelLine> batch = <PanelLine>[
    PanelLine(speaker: Speaker.me, text: '在吗'),
    PanelLine(speaker: Speaker.other, text: '在的'),
  ];

  /// What the module asks the field to show: a block to build, or null to leave
  /// what is in the field alone.
  String? ask(
    ReviewSession session,
    List<PanelLine> lines, {
    bool reviewing = true,
  }) => session.blockFor(reviewing: reviewing, batch: lines);

  TextEditingValue caretAt(String text, int caret) => TextEditingValue(
    text: text,
    selection: TextSelection.collapsed(offset: caret),
  );

  TextEditingValue selectionOver(String text, int base, int extent) =>
      TextEditingValue(
        text: text,
        selection: TextSelection(baseOffset: base, extentOffset: extent),
      );

  group('the block a frame asks for', () {
    test('entering the review builds it out of the batch', () {
      expect(ask(ReviewSession(copy), batch), '我：在吗\n对方：在的');
    });

    test('a republish of the same batch leaves the field alone', () {
      final ReviewSession session = ReviewSession(copy);
      ask(session, batch);

      expect(
        ask(session, batch),
        isNull,
        reason:
            'building the block again would replace what the user has typed '
            'with what the recogniser read',
      );
    });

    test('a batch whose fourth line changed is a new batch', () {
      // The tail is identical and the batch is not. The two signatures this
      // repository already has keep the last six lines, because the question
      // they answer is "has the conversation moved on" — this one is "is this
      // the batch in the field", and an edit against the old batch does not
      // belong to a new one.
      final List<PanelLine> long = <PanelLine>[
        for (int i = 0; i < 8; i++)
          PanelLine(speaker: Speaker.me, text: '第$i句'),
      ];
      final ReviewSession session = ReviewSession(copy);
      ask(session, long);

      expect(
        ask(session, <PanelLine>[
          const PanelLine(speaker: Speaker.me, text: '改过的第一句'),
          ...long.skip(1),
        ]),
        isNotNull,
      );
    });

    test('a two-line batch does not collide with a one-line batch', () {
      // A plain `speaker:text` join would give both of these the same string,
      // and a collision here is a kept edit against the wrong batch.
      final ReviewSession session = ReviewSession(copy);
      ask(session, const <PanelLine>[
        PanelLine(speaker: Speaker.me, text: 'a|other:b'),
      ]);

      expect(
        ask(session, const <PanelLine>[
          PanelLine(speaker: Speaker.me, text: 'a'),
          PanelLine(speaker: Speaker.other, text: 'b'),
        ]),
        isNotNull,
      );
    });

    test('leaving the review forgets the batch', () {
      // Which is the same rule as the one above, from the other side: a review
      // the user comes back to is a fresh block, not last visit's edit
      // resurrected under the caret.
      final ReviewSession session = ReviewSession(copy);
      ask(session, batch);
      expect(ask(session, batch, reviewing: false), isNull);

      expect(ask(session, batch), '我：在吗\n对方：在的');
    });

    test('an empty batch is a block like any other', () {
      // `signatureOf` returns the empty string here rather than null, so the
      // forgotten-batch state cannot be confused with the empty one.
      final ReviewSession session = ReviewSession(copy);
      expect(ask(session, const <PanelLine>[]), '');

      expect(ask(session, const <PanelLine>[]), isNull);
    });
  });

  group('删行', () {
    const String block = '我：在吗\n对方：在的\n对方：刚看到';

    test('a middle line goes with its trailing newline', () {
      final TextEditingValue out = ReviewSession(
        copy,
      ).deleteLine(caretAt(block, '我：在吗\n'.length + 1));

      expect(out.text, '我：在吗\n对方：刚看到');
      expect(
        out.selection,
        const TextSelection.collapsed(offset: '我：在吗\n'.length),
        reason: 'the caret falls back to the start of the deleted span, so a '
            'second tap removes the next line',
      );
    });

    test('the first line goes with its trailing newline', () {
      final TextEditingValue out = ReviewSession(copy).deleteLine(
        caretAt(block, 2),
      );

      expect(out.text, '对方：在的\n对方：刚看到');
      expect(out.selection, const TextSelection.collapsed(offset: 0));
    });

    test('the last line goes with its preceding newline', () {
      final TextEditingValue out = ReviewSession(
        copy,
      ).deleteLine(caretAt(block, block.length - 1));

      expect(out.text, '我：在吗\n对方：在的');
      expect(
        out.selection,
        const TextSelection.collapsed(offset: '我：在吗\n对方：在的'.length),
        reason: 'the two neighbours meet rather than leaving a blank line',
      );
    });

    test('the only line is the whole block', () {
      final TextEditingValue out = ReviewSession(
        copy,
      ).deleteLine(caretAt('我：在吗', 3));

      expect(out.text, '');
      expect(out.selection, const TextSelection.collapsed(offset: 0));
    });

    test('a block with no caret in it deletes from the top', () {
      // A controller that has never been focused reports offset -1. The widget
      // keeps 删行 disabled until it has been, but the module still owes this
      // value an answer rather than an exception.
      final TextEditingValue out = ReviewSession(
        copy,
      ).deleteLine(const TextEditingValue(text: block));

      expect(out.text, '对方：在的\n对方：刚看到');
    });
  });

  group('我 / 对方 rewrite the caret\'s line', () {
    const String block = '我：在吗\n对方：在的';

    test('a collapsed caret rewrites the line it sits on', () {
      final TextEditingValue out = ReviewSession(copy).setSpeaker(
        caretAt(block, '我：在吗\n'.length + 1),
        Speaker.me,
      );

      expect(out.text, '我：在吗\n我：在的');
    });

    test('the caret lands inside the new body, never before its prefix', () {
      final TextEditingValue out = ReviewSession(copy).setSpeaker(
        caretAt(block, '我：在吗\n'.length + 1),
        Speaker.me,
      );

      expect(
        out.selection,
        const TextSelection.collapsed(offset: '我：在吗\n我：'.length),
        reason: 'the caret was in the body and the body has not moved; landing '
            'it before the prefix would have the next keystroke overwrite the '
            'speaker the user just chose',
      );
    });

    test('a selection rewrites every line it touches', () {
      final TextEditingValue out = ReviewSession(copy).setSpeaker(
        selectionOver(block, 0, block.length),
        Speaker.other,
      );

      expect(out.text, '对方：在吗\n对方：在的');
    });

    test('a line typed without a prefix gets one', () {
      // The block is the source of truth, so a line the user typed arrives
      // bare; the shortcut has to make it a message rather than prepend to
      // nothing.
      final TextEditingValue out = ReviewSession(
        copy,
      ).setSpeaker(caretAt('在吗\n在的', 0), Speaker.me);

      expect(out.text, '我：在吗\n在的');
    });

    test('未定 is reachable through the same door', () {
      final TextEditingValue out = ReviewSession(
        copy,
      ).setSpeaker(caretAt(block, 0), Speaker.unknown);

      expect(out.text, '未定：在吗\n对方：在的');
    });
  });

  group('reading the batch back out', () {
    test('a block built from a batch parses back to that batch', () {
      final ReviewSession session = ReviewSession(copy);
      final String block = ask(session, batch)!;

      expect(
        session
            .lines(block)
            .map((PanelLine line) => '${line.speaker.name}:${line.text}'),
        <String>['me:在吗', 'other:在的'],
      );
    });

    test('a block with nothing left in it has no lines', () {
      expect(ReviewSession(copy).lines('   \n\n  '), isEmpty);
    });
  });
}
