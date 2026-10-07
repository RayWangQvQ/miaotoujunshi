import 'package:flutter_test/flutter_test.dart';
import 'package:miaotou_app/src/design/copy.dart';
import 'package:miaotou_app/src/panel/protocol.dart';
import 'package:miaotou_app/src/panel/translation.dart';
import 'package:miaotou_capabilities/miaotou_capabilities.dart';
import 'package:miaotou_domain/miaotou_domain.dart';

/// The two vocabularies the window boundary forces to be spelled twice.
///
/// The engine's command list and note list are in `miaotou_domain`, which may
/// not know that a panel is a second window with a wire (ADR-0020), and the
/// panel's are in this application, which is the side that does. So [commandKindOf]
/// and [copyKeyOf] are `switch` expressions and the compiler is the gate for
/// "every one of them has an answer".
///
/// What the compiler cannot see is the pair of failures that are silent: two
/// codes answered with the *same* sentence, so the panel cannot tell them apart,
/// and a code whose sentence has a hole in it that nothing ever fills. Both are
/// checked here.
void main() {
  group('note codes', () {
    test('every one has a sentence', () {
      final List<String> empty = <String>[
        for (final NoteCode code in NoteCode.values)
          if (AppCopy.zh.text(copyKeyOf(code)).trim().isEmpty) code.name,
      ];

      expect(empty, isEmpty);
    });

    test('no two of them are answered with the same sentence', () {
      final Map<String, NoteCode> seen = <String, NoteCode>{};
      final List<String> collisions = <String>[];

      for (final NoteCode code in NoteCode.values) {
        final String text = AppCopy.zh.text(copyKeyOf(code));
        final NoteCode? other = seen[text];
        if (other != null) {
          collisions.add('${other.name} and ${code.name} both say $text');
        }
        seen[text] = code;
      }

      expect(
        collisions,
        isEmpty,
        reason: 'a note is a code because one name means one fact; two names '
            'sharing a sentence is a panel that cannot say which happened',
      );
    });

    test('the one code with a hole in its sentence is the one that fills it', () {
      final List<String> wrong = <String>[];

      for (final NoteCode code in NoteCode.values) {
        final String text = AppCopy.zh.text(copyKeyOf(code));
        final bool hasHole = text.contains(platformWordsPlaceholder);
        final bool expectsHole = notesWithPlatformWords.contains(code);
        if (hasHole != expectsHole) {
          wrong.add('${code.name}: expects a reason=$expectsHole, text=$text');
        }
      }

      expect(
        wrong,
        isEmpty,
        reason: 'a sentence with an unfilled {reason} is shown to the user as '
            'written, and a reason with nowhere to go is a cause that is lost',
      );
      expect(
        notesWithPlatformWords,
        <NoteCode>{NoteCode.captureRefused},
        reason: 'the platform writes one of these sentences to be shown '
            'unchanged — the refusal that names the cause of a frame it would '
            'not take — and every other note is a fact with words of our own',
      );
    });

    test('a reason is substituted rather than appended', () {
      final PanelNote note = noteOf(
        const CopyNote(NoteCode.captureRefused, reason: 'window is protected'),
        AppCopy.zh,
      );

      expect(note.text, contains('window is protected'));
      expect(note.text, isNot(contains(platformWordsPlaceholder)));
    });

    test('a literal note is passed through as somebody else wrote it', () {
      final PanelNote note = noteOf(const LiteralNote('关系背景过长'), AppCopy.zh);

      expect(note.text, '关系背景过长');
      expect(note.remedy, isNull);
    });
  });

  group('remedies', () {
    test('the two ways out cross as the two the panel draws', () {
      expect(
        panelRemedyOf(const AskPermission(PermissionKind.accessibility)),
        const OpenPermissionPage(PermissionKind.accessibility),
      );
      expect(panelRemedyOf(const AskReview()), const EnterReview());
    });

    test('a note carries its remedy through', () {
      final PanelNote note = noteOf(
        const CopyNote(
          NoteCode.captureServiceOff,
          remedy: AskPermission(PermissionKind.accessibility),
        ),
        AppCopy.zh,
      );

      expect(
        note.remedy,
        const OpenPermissionPage(PermissionKind.accessibility),
      );
    });
  });

  group('command kinds', () {
    test('the panel has no command the engine cannot name', () {
      expect(
        PanelCommandKind.values.map(commandKindOf).toSet(),
        hasLength(PanelCommandKind.values.length),
        reason: 'two panel commands folding onto one engine command would make '
            'them indistinguishable below the boundary',
      );
    });

    test('and the engine has none the panel cannot send', () {
      expect(
        ConversationCommandKind.values.length,
        PanelCommandKind.values.length,
        reason: 'the engine command added without a panel command is either '
            'unreachable or waiting on a protocol change',
      );
    });

    test('a command carries its payload across', () {
      final CommandReceived command = commandOf(
        const PanelCommand(
          PanelCommandKind.confirmTranscript,
          lines: <PanelLine>[
            PanelLine(speaker: Speaker.me, text: '在吗'),
            PanelLine(speaker: Speaker.other, text: '在的'),
          ],
        ),
      );

      expect(command.kind, ConversationCommandKind.confirmTranscript);
      expect(
        command.lines?.map((ChatLine line) => line.text),
        <String>['在吗', '在的'],
      );
      expect(command.lines?.first.speaker, Speaker.me);
    });

    test('no lines stays distinct from an empty batch', () {
      final CommandReceived command = commandOf(
        const PanelCommand(PanelCommandKind.reanalyse),
      );

      expect(
        command.lines,
        isNull,
        reason: 'the panel disables the confirm button on an empty batch, so '
            '"there are no lines" and "the batch is empty" are two different '
            'facts and the second one is refused rather than sent',
      );
    });
  });
}
