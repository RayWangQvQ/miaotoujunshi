import 'dart:convert';

import 'package:miaotou_capabilities/miaotou_capabilities.dart';
import 'package:miaotou_capabilities_shared/miaotou_capabilities_shared.dart';
import 'package:test/test.dart';

import 'fake_documents.dart';

/// The knowledge base, in one suite for all three ports.
///
/// The union baseline (ADR-0007 decision 4) is what put this capability on the
/// two desktop ports as well as Android's, and it is also what makes one suite
/// the right shape: the matching rule below is the mechanism that lets a contact
/// recognised in one application be recognised in another, and three copies of it
/// could disagree about which titles are the same person.
void main() {
  late FakeDocuments documents;
  late KnowledgeLedger knowledge;

  setUp(() {
    documents = FakeDocuments();
    knowledge = KnowledgeLedger(documents);
  });

  group('notes', () {
    test('a note written is a note read back, with every field', () async {
      await knowledge.saveNote(
        KnowledgeNote(
          id: 'n1',
          title: '她的忌口',
          content: '不吃香菜',
          updatedAt: DateTime(2026, 10, 4, 9, 30),
          tags: <String>['饮食', '重要'],
          alwaysOn: true,
          enabled: false,
        ),
      );

      final KnowledgeNote note = (await knowledge.notes()).single;
      expect(note.id, 'n1');
      expect(note.title, '她的忌口');
      expect(note.content, '不吃香菜');
      expect(note.updatedAt, DateTime(2026, 10, 4, 9, 30));
      expect(note.tags, <String>['饮食', '重要']);
      expect(note.alwaysOn, isTrue);
      expect(note.enabled, isFalse);
    });

    test('saving the same id twice updates rather than duplicates', () async {
      await knowledge.saveNote(_note('n1', 'first'));
      await knowledge.saveNote(_note('n1', 'second'));

      final List<KnowledgeNote> notes = await knowledge.notes();
      expect(notes, hasLength(1));
      expect(notes.single.content, 'second');
    });

    test('deleting a note that is not there is not an error', () async {
      await knowledge.deleteNote('never-written');

      expect(await knowledge.notes(), isEmpty);
      expect(
        documents.writeCount('knowledge.json'),
        0,
        reason: 'a delete of something that was never there must not rewrite the '
            'document',
      );
    });

    test('an optional field that was never set reads back as empty', () async {
      // `''` is the contract's own spelling of "not set", so a missing title is
      // not damaged data — unlike a row with no id, which is refused below.
      await knowledge.saveNote(
        KnowledgeNote(
          id: 'n1',
          title: '',
          content: '',
          updatedAt: DateTime(2026, 10, 4),
        ),
      );

      final KnowledgeNote note = (await knowledge.notes()).single;
      expect(note.title, '');
      expect(note.content, '');
      expect(note.tags, isEmpty);
    });
  });

  group('finding a conversation', () {
    test('a contact is found by an alias, not only by its name', () async {
      // The property that makes the store portable and the union baseline
      // reachable: the same person is a different window title in each app.
      await knowledge.saveContact(
        KnowledgeContact(
          id: 'c1',
          name: '小岚',
          updatedAt: DateTime(2026, 10, 4),
          aliases: <String>['Lan', '小岚（微信）'],
          packageNames: <String>['com.tencent.xinWeChat'],
          stage: '了解中',
        ),
      );

      final KnowledgeContact? byAlias = await knowledge.findContact(
        title: 'Lan',
        packageName: 'com.tencent.xinWeChat',
      );
      final KnowledgeContact? byName = await knowledge.findContact(
        title: '小岚',
        packageName: 'com.tencent.xinWeChat',
      );

      expect(byAlias?.id, 'c1');
      expect(byName?.id, 'c1');
    });

    test('a title is matched case-insensitively and trimmed', () async {
      await knowledge.saveContact(
        KnowledgeContact(
          id: 'c1',
          name: 'Alex',
          updatedAt: DateTime(2026, 10, 4),
          packageNames: <String>['com.example.chat'],
        ),
      );

      expect(
        (await knowledge.findContact(
          title: '  alex  ',
          packageName: 'com.example.chat',
        ))
            ?.id,
        'c1',
        reason: 'a window title arrives with whatever padding the chat app put on '
            'it; refusing to match it would make every alias useless',
      );
    });

    test('the right title in the wrong package is not a match', () async {
      // Both halves of the identity are load-bearing. A title alone would attach
      // a conversation to a stranger with the same nickname in another app.
      await knowledge.saveContact(
        KnowledgeContact(
          id: 'c1',
          name: 'Alex',
          updatedAt: DateTime(2026, 10, 4),
          packageNames: <String>['com.example.chat'],
        ),
      );

      expect(
        await knowledge.findContact(
          title: 'Alex',
          packageName: 'com.other.app',
        ),
        isNull,
      );
    });

    test('an empty title matches nothing rather than everything', () async {
      // A contact whose *own* name is empty, so that removing the empty-title
      // guard would let the two empty strings meet. A contact named 小岚 does not
      // distinguish the guard from the loop's own comparison, and a test that
      // cannot tell them apart is not testing the guard.
      await knowledge.saveContact(
        KnowledgeContact(
          id: 'c1',
          name: '',
          updatedAt: DateTime(2026, 10, 4),
          packageNames: <String>['com.tencent.xinWeChat'],
        ),
      );

      expect(
        await knowledge.findContact(
          title: '   ',
          packageName: 'com.tencent.xinWeChat',
        ),
        isNull,
        reason: 'a window that has not reported its title yet must not be '
            'attached to an arbitrary contact — and an unnamed contact is the one '
            'record it could plausibly be attached to',
      );
      expect(
        await knowledge.findContact(
          title: '',
          packageName: 'com.tencent.xinWeChat',
        ),
        isNull,
      );
    });

    test('an empty package name matches nothing, not everything', () async {
      // The other half of the identity: a caller that cannot name the
      // application has not named a conversation, so the pair is not
      // half-present — it identifies nobody.
      await knowledge.saveContact(
        KnowledgeContact(
          id: 'c1',
          name: 'Alex',
          updatedAt: DateTime(2026, 10, 4),
          packageNames: <String>['com.tencent.xinWeChat'],
        ),
      );

      expect(
        await knowledge.findContact(title: 'Alex', packageName: ''),
        isNull,
        reason: 'a title with no application is not a conversation, and matching '
            'it would attach a window to whichever record shares the name first',
      );
      expect(
        await knowledge.findContact(title: 'Alex', packageName: '   '),
        isNull,
        reason: 'whitespace is not a package name either — it normalises to the '
            'same empty string, so it must reach the same answer',
      );
    });

    test('an empty package name does not match a contact that has one',
        () async {
      // What makes the guard above load-bearing rather than a restatement of the
      // loop.
      //
      // Every other test of the empty package reaches the same answer twice: once
      // because `wantedPackage.isEmpty` returns null, and once because the loop's
      // own `contains(wantedPackage)` would have rejected it anyway. Two
      // mechanisms, one observable behaviour — so deleting the guard, or changing
      // it to `if (false)`, leaves the suite green.
      //
      // So this contact carries an **empty string among its package names**, which
      // is a real state rather than a contrived one: `_texts` decodes a missing or
      // blank entry as `''`, and a contact recorded before an application reported
      // its package name has exactly that.
      await knowledge.saveContact(
        KnowledgeContact(
          id: 'c1',
          name: 'Alex',
          updatedAt: DateTime(2026, 10, 4),
          packageNames: <String>['', 'com.tencent.xinWeChat'],
        ),
      );

      expect(
        await knowledge.findContact(title: 'Alex', packageName: ''),
        isNull,
        reason: 'the guard exists for the contact whose own package list is '
            'blank. Any other contact is rejected by the loop, so this is the '
            'only shape that tells the guard from the loop it sits in front of',
      );
      // The same contact still matches on the package it really has, so the
      // assertion above is about the *empty* query and not about this contact
      // being unfindable.
      expect(
        (await knowledge.findContact(
          title: 'Alex',
          packageName: 'com.tencent.xinWeChat',
        ))
            ?.id,
        'c1',
        reason: 'a blank entry in one list must not stop a real package beside it '
            'from matching',
      );
    });

    test('a contact is found in a second application once it has been seen there',
        () async {
      await knowledge.saveContact(
        KnowledgeContact(
          id: 'c1',
          name: '小岚',
          updatedAt: DateTime(2026, 10, 4),
          aliases: <String>['小岚（浏览器）'],
          packageNames: <String>['com.tencent.xinWeChat', 'com.google.Chrome'],
        ),
      );

      expect(
        (await knowledge.findContact(
          title: '小岚（浏览器）',
          packageName: 'com.google.Chrome',
        ))
            ?.id,
        'c1',
      );
    });
  });

  group('history', () {
    test('history is appended oldest first and read back as a window', () async {
      await knowledge.appendLog('c1', <KnowledgeLogEntry>[
        _entry('me', '在吗', 1),
        _entry('other', '在', 2),
        _entry('me', '周末有空吗', 3),
      ]);
      await knowledge.appendLog(
        'c1',
        <KnowledgeLogEntry>[_entry('other', '有', 4)],
      );

      final List<KnowledgeLogEntry> recent = await knowledge.recentLog(
        'c1',
        limit: 2,
      );

      expect(
        recent.map((KnowledgeLogEntry e) => e.text),
        <String>['周末有空吗', '有'],
        reason: 'the most recent N, still oldest first — a reversed window would '
            'render the conversation backwards',
      );
    });

    test('a limit of zero or less returns nothing rather than everything',
        () async {
      await knowledge.appendLog('c1', <KnowledgeLogEntry>[_entry('me', '在吗', 1)]);

      expect(await knowledge.recentLog('c1', limit: 0), isEmpty);
      expect(await knowledge.recentLog('c1', limit: -5), isEmpty);
    });

    test('a larger limit than the history is not an error', () async {
      await knowledge.appendLog('c1', <KnowledgeLogEntry>[_entry('me', '在吗', 1)]);

      expect(await knowledge.recentLog('c1', limit: 100), hasLength(1));
    });

    test('appending nothing does not rewrite the document', () async {
      await knowledge.appendLog('c1', <KnowledgeLogEntry>[_entry('me', '在吗', 1)]);
      final int before = documents.writeCount('knowledge.json');

      await knowledge.appendLog('c1', const <KnowledgeLogEntry>[]);

      expect(
        documents.writeCount('knowledge.json'),
        before,
        reason: 'appendLog runs after every capture; a no-op that touched the '
            'document would make its modification time mean nothing',
      );
    });

    test('deleting a contact takes its history with it', () async {
      await knowledge.saveContact(
        KnowledgeContact(
          id: 'c1',
          name: '小岚',
          updatedAt: DateTime(2026, 10, 4),
        ),
      );
      await knowledge.appendLog('c1', <KnowledgeLogEntry>[_entry('me', '在吗', 1)]);

      await knowledge.deleteContact('c1');

      expect(await knowledge.contacts(), isEmpty);
      expect(
        await knowledge.recentLog('c1', limit: 10),
        isEmpty,
        reason: 'the one action a user takes to remove someone has to remove what '
            'was said to them too',
      );
    });

    test('deleting a contact that had no history leaves no empty logs key',
        () async {
      // The early return, and the shape it protects: a delete that took no
      // history must not materialise an `logs` object into a document that never
      // had one, because a rewrite on every empty swipe would make the document's
      // timestamp mean nothing.
      await knowledge.saveContact(
        KnowledgeContact(
          id: 'c1',
          name: '小岚',
          updatedAt: DateTime(2026, 10, 4),
        ),
      );
      await knowledge.deleteContact('c1');

      final Map<String, Object?> written =
          jsonDecode(documents.raw('knowledge.json')!) as Map<String, Object?>;

      expect(written.containsKey('logs'), isFalse);
      expect(written['contacts'], isEmpty);
    });

    test('deleting a contact that is not there does not rewrite', () async {
      final int before = documents.writeCount('knowledge.json');

      await knowledge.deleteContact('never-written');

      expect(documents.writeCount('knowledge.json'), before);
    });
  });

  test('clearAll empties notes, contacts and history together', () async {
    await knowledge.saveNote(_note('n1', 'x'));
    await knowledge.saveContact(
      KnowledgeContact(
        id: 'c1',
        name: '小岚',
        updatedAt: DateTime(2026, 10, 4),
      ),
    );
    await knowledge.appendLog('c1', <KnowledgeLogEntry>[_entry('me', '在吗', 1)]);

    await knowledge.clearAll();

    expect(await knowledge.notes(), isEmpty);
    expect(await knowledge.contacts(), isEmpty);
    expect(await knowledge.recentLog('c1', limit: 10), isEmpty);
  });

  test('a knowledge base survives the process', () async {
    await knowledge.saveNote(_note('n1', '不吃香菜'));
    await knowledge.saveContact(
      KnowledgeContact(
        id: 'c1',
        name: '小岚',
        updatedAt: DateTime(2026, 10, 4),
        aliases: <String>['Lan'],
        packageNames: <String>['com.tencent.xinWeChat'],
      ),
    );
    await knowledge.appendLog('c1', <KnowledgeLogEntry>[_entry('me', '在吗', 1)]);

    final KnowledgeLedger reopened = KnowledgeLedger(documents);

    expect((await reopened.notes()).single.content, '不吃香菜');
    expect(
      (await reopened.findContact(
        title: 'Lan',
        packageName: 'com.tencent.xinWeChat',
      ))
          ?.id,
      'c1',
    );
    expect(await reopened.recentLog('c1', limit: 5), hasLength(1));
  });

  test('a key this build does not know rides along untouched', () async {
    // Forward compatibility, and it is not free: the store rewrites the whole
    // document on every save, so "read the rest and write it back" is the only
    // thing standing between a newer build's key and silent deletion.
    documents.put(
      'knowledge.json',
      jsonEncode(<String, Object?>{'futureKey': <String, Object?>{'a': 1}}),
    );

    await knowledge.saveNote(_note('n1', 'x'));

    final Map<String, Object?> written =
        jsonDecode(documents.raw('knowledge.json')!) as Map<String, Object?>;

    expect(written['futureKey'], <String, Object?>{'a': 1});
  });

  group('a damaged document', () {
    test('a note with no id refuses the document rather than being dropped',
        () async {
      // The three ports had two answers here and neither was stated: macOS
      // dropped the row and claimed the file "loses the damaged rows rather than
      // inventing an identity" — but `saveNote` rebuilds the section from the
      // rows it decoded, so the dropped row disappeared on the next save without
      // a word.
      documents.put(
        'knowledge.json',
        jsonEncode(<String, Object?>{
          'notes': <Object?>[
            <String, Object?>{'title': 'no id here'},
          ],
        }),
      );

      await expectLater(knowledge.notes(), throwsStateError);
    });

    test('a contact with no id refuses the document too', () async {
      documents.put(
        'knowledge.json',
        jsonEncode(<String, Object?>{
          'contacts': <Object?>[
            <String, Object?>{'name': 'Alex'},
          ],
        }),
      );

      await expectLater(knowledge.contacts(), throwsStateError);
    });

    test('a log line has no id, and must not be judged as if it had', () async {
      // The split between the keyed sections and the log. A log entry is
      // identified by its position and its timestamp — `KnowledgeLogEntry` has no
      // identifier field at all — so running the id filter over it would drop
      // every line of every conversation.
      documents.put(
        'knowledge.json',
        jsonEncode(<String, Object?>{
          'logs': <String, Object?>{
            'c1': <Object?>[
              <String, Object?>{
                'speaker': 'other',
                'text': '在',
                'timestamp': '2026-10-04T12:02:00.000Z',
                'packageName': 'com.tencent.xinWeChat',
              },
            ],
          },
        }),
      );

      final List<KnowledgeLogEntry> recent = await knowledge.recentLog(
        'c1',
        limit: 10,
      );

      expect(recent, hasLength(1));
      expect(recent.single.text, '在');
      expect(recent.single.speaker, Speaker.other);
    });

    test('a section that is not a list is refused', () async {
      documents.put(
        'knowledge.json',
        jsonEncode(<String, Object?>{'notes': <String, Object?>{'a': 1}}),
      );

      await expectLater(knowledge.notes(), throwsStateError);
    });

    test('an entry that is not an object is refused', () async {
      documents.put(
        'knowledge.json',
        jsonEncode(<String, Object?>{
          'notes': <Object?>['just a string'],
        }),
      );

      await expectLater(knowledge.notes(), throwsStateError);
    });

    test('a speaker this build does not recognise reads back as other',
        () async {
      // Not a refusal, and deliberately so: one unrecognised line from an older
      // build must not make a whole conversation unreadable.
      documents.put(
        'knowledge.json',
        jsonEncode(<String, Object?>{
          'logs': <String, Object?>{
            'c1': <Object?>[
              <String, Object?>{
                'speaker': 'a-speaker-from-the-future',
                'text': '在',
                'timestamp': '2026-10-04T12:02:00.000Z',
                'packageName': 'com.tencent.xinWeChat',
              },
            ],
          },
        }),
      );

      final List<KnowledgeLogEntry> recent = await knowledge.recentLog(
        'c1',
        limit: 10,
      );

      expect(recent.single.speaker, Speaker.other);
    });
  });

  test('the document is named knowledge.json', () {
    expect(KnowledgeLedger.fileName, 'knowledge.json');
  });
}

KnowledgeNote _note(String id, String content) => KnowledgeNote(
  id: id,
  title: '标题',
  content: content,
  updatedAt: DateTime(2026, 10, 4, 12),
);

KnowledgeLogEntry _entry(String speaker, String text, int minute) =>
    KnowledgeLogEntry(
      speaker: speaker == 'me' ? Speaker.me : Speaker.other,
      text: text,
      timestamp: DateTime(2026, 10, 4, 12, minute),
      packageName: 'com.tencent.xinWeChat',
    );
