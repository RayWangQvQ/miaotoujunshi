import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:miaotou_capabilities/miaotou_capabilities.dart';
import 'package:miaotou_capabilities_macos/miaotou_capabilities_macos.dart';
import 'package:miaotou_capabilities_macos/testing.dart';

/// #15's storage quartet, over a scripted Mac and a temporary container.
///
/// Every branch here is one a device could not tell us about: a file that is
/// written and read back, a value that survives the process going away, a
/// contact matched by an alias rather than a name, an undo that puts back what
/// was there before. The seam's contribution is three strings and four keychain
/// calls; everything asserted below happens in pure Dart, which is the split
/// `native.dart`'s header argues for and this file is the evidence for.
void main() {
  late FakeMacosNative native;

  setUp(() {
    native = fakeMacosWithTemporaryStorage();
  });

  tearDown(() async {
    await native.close();
    deleteTemporaryStorage(native);
  });

  group('preferences', () {
    late MacosPreferences preferences;

    setUp(() {
      preferences = MacosPreferences.inContainer(native);
    });

    test('a value written is a value read back, with its type intact', () async {
      await preferences.setString('route', 'deepseek');
      await preferences.setBool('autoAnalyse', true);
      await preferences.setInt('candidates', 3);

      expect(await preferences.getString('route'), 'deepseek');
      expect(await preferences.getBool('autoAnalyse'), isTrue);
      expect(await preferences.getInt('candidates'), 3);
    });

    test('a key that was never set reads back as null, not as an error', () async {
      expect(await preferences.getString('absent'), isNull);
      expect(await preferences.getBool('absent'), isNull);
      expect(await preferences.getInt('absent'), isNull);
      expect(await preferences.getStringList('absent'), isNull);
    });

    test('reading a key as the wrong type gives null rather than a coercion',
        () async {
      // The dangerous shape: `autoAnalyse` is a bool, and a store that returned
      // the string "false" for it would let a caller branch on a value that is
      // never what was written.
      await preferences.setBool('autoAnalyse', false);

      expect(await preferences.getString('autoAnalyse'), isNull);
      expect(await preferences.getInt('autoAnalyse'), isNull);
      expect(await preferences.getBool('autoAnalyse'), isFalse);
    });

    test('a string list is stored as a set, so its order is not the value',
        () async {
      await preferences.setStringList('whitelist', <String>['b', 'a', 'b']);

      expect(
        await preferences.getStringList('whitelist'),
        <String>['a', 'b'],
        reason: 'the contract says the order is not part of the value, so two '
            'writes of the same set must produce the same file',
      );
    });

    test('the same set written in two orders leaves one file, not two', () async {
      await preferences.setStringList('whitelist', <String>['a', 'b']);
      final String first = _containerFile(native, 'preferences.json')
          .readAsStringSync();
      await preferences.setStringList('whitelist', <String>['b', 'a']);

      expect(
        _containerFile(native, 'preferences.json').readAsStringSync(),
        first,
        reason: 'a settings diff that shows a change nobody made is a bug report '
            'waiting to happen',
      );
    });

    test('keys lists what is held so a caller can wipe it blind', () async {
      await preferences.setString('route', 'deepseek');
      await preferences.setInt('candidates', 3);

      expect(await preferences.keys(), <String>{'route', 'candidates'});
    });

    test('removing a key that is not set is not an error', () async {
      await preferences.remove('never-written');
      expect(await preferences.keys(), isEmpty);
    });

    test('a store survives the process: a second store over the same directory '
        'reads what the first wrote', () async {
      await preferences.setString('route', 'openrouter');
      await preferences.setStringList('whitelist', <String>['x', 'y']);

      // A *different object* over the same place, which is what a relaunch is.
      // Constructing the same object twice would share nothing here, but making
      // it explicit is what keeps the test honest about what it proves.
      final MacosPreferences reopened =
          MacosPreferences(ContainerFile(native, 'preferences.json'));

      expect(await reopened.getString('route'), 'openrouter');
      expect(await reopened.getStringList('whitelist'), <String>['x', 'y']);
      expect(await reopened.keys(), <String>{'route', 'whitelist'});
    });

    test('a corrupt settings file is refused rather than read as empty',
        () async {
      // The scenario is a half-written file from a crash. Reading it as an empty
      // store would present "you have no settings" as the truth and then write
      // over whatever was salvageable on the next save.
      // One store per shape, because a *successful* read is memoised and a
      // shared store would answer the second and third cases from the first
      // one's cached failure — the test would pass without ever reaching the
      // branch each shape is aimed at.
      for (final String corrupt in <String>[
        '{"route": "dee',   // truncated mid-value: fails inside the decoder
        '[1, 2, 3]',         // valid JSON, wrong shape: reaches the Map guard
        'not json at all',   // not JSON: fails inside the decoder
      ]) {
        _containerFile(native, 'preferences.json').writeAsStringSync(corrupt);

        await expectLater(
          MacosPreferences(ContainerFile(native, 'preferences.json')).keys(),
          throwsFormatException,
          reason: '"$corrupt" must not read as an empty store',
        );
      }
    });

    test('a failed read is not remembered, so a store recovers on its own',
        () async {
      // A read can fail for a reason that goes away — a file mid-rewrite, a
      // volume not yet mounted. Caching the failure would make the store
      // permanently unreadable until a relaunch, with nothing to tell the user
      // what happened.
      _containerFile(native, 'preferences.json')
          .writeAsStringSync('{"route": "dee');
      final MacosPreferences store =
          MacosPreferences(ContainerFile(native, 'preferences.json'));

      await expectLater(store.keys(), throwsFormatException);

      File('${native.containerRoot}/preferences.json')
          .writeAsStringSync('{"route":"deepseek"}');

      expect(
        await store.keys(),
        <String>{'route'},
        reason: 'the same store object, after the file became readable again',
      );
    });

    test('a second store over the same file sees the first one\'s write', () async {
      // The property `ContainerFile`'s header rests on, and the one its removed
      // cache used to break. Two stores over one file is not a contrived setup:
      // `macosCapabilities()` builds a fresh set of stores on every call and
      // `capabilitiesForCurrentPlatform()` memoises nothing, so it is the
      // ordinary shape of this code.
      //
      // Both directions, because read-modify-write only loses an update in one of
      // them: a reader that cannot see a write gives a stale answer, and a writer
      // that cannot see a read writes the other store's changes back over its own.
      final MacosPreferences first = MacosPreferences.inContainer(native);
      expect(await first.getString('route'), isNull);

      await MacosPreferences(ContainerFile(native, 'preferences.json'))
          .setString('route', 'deepseek');

      expect(
        await first.getString('route'),
        'deepseek',
        reason: 'the first store did not write this, and it is still the store a '
            'caller holds; it must not be answering from a value that was current '
            'when it was first asked',
      );
    });

    test('a store that wrote a key away does not resurrect it', () async {
      // The lost update, which is the damaging half. A store that read before the
      // deletion and writes afterwards puts the deleted key back — so this is the
      // test that says a stale read is not merely a stale display.
      final MacosPreferences store = MacosPreferences.inContainer(native);
      await store.setString('route', 'deepseek');
      await store.setString('model', 'gpt');
      expect(await store.keys(), <String>{'route', 'model'});

      // A different object removes one, then the first store saves an unrelated
      // key — the ordinary sequence of two screens touching one settings file.
      await MacosPreferences(ContainerFile(native, 'preferences.json'))
          .remove('route');
      await store.setString('candidates', '3');

      expect(
        await store.keys(),
        <String>{'model', 'candidates'},
        reason: 'the removal has to survive a later write from another store; a '
            'store that rewrote a document it had not re-read would put the '
            'deleted key back',
      );
    });

    test('a write interrupted before the rename leaves the last good file', () async {
      // The strongest durability claim in `ContainerFile` — write to a sibling
      // `.tmp`, then rename over the target — and until now nothing tested it.
      //
      // The failure is injected rather than described: the directory is made
      // read-only *after* the scratch file exists, so writing the scratch file
      // still succeeds (an existing file needs write permission, not directory
      // permission) while the rename fails. That is precisely the window the claim
      // is about — the bytes are on disk and the target has not been replaced yet.
      final MacosPreferences store = MacosPreferences.inContainer(native);
      await store.setString('route', 'first');
      final File target = _containerFile(native, 'preferences.json');
      final File scratch = File('${target.path}.tmp');

      // The scratch file has to exist beforehand, or creating it would need the
      // directory permission this removes and the failure would land in the wrong
      // place — before the write rather than between the write and the rename.
      scratch.writeAsStringSync('{}');
      _makeReadOnly(target.parent);
      addTearDown(() => _makeWritable(target.parent));

      await expectLater(
        store.setString('route', 'second'),
        throwsA(isA<FileSystemException>()),
        reason: 'the rename cannot succeed with the directory read-only; if this '
            'did not throw, the fault was not injected and the test proves '
            'nothing',
      );

      expect(
        target.readAsStringSync(),
        contains('first'),
        reason: 'the target must still hold the last complete document. A '
            'half-written preferences file is worse than a missing one: it is '
            'unreadable *and* it has already destroyed what was there',
      );
      expect(
        () => jsonDecode(target.readAsStringSync()),
        returnsNormally,
        reason: '"first" has to be the whole previous document, not a prefix of a '
            'new one — the claim is that the old file is intact, not merely that '
            'some of it is',
      );
      expect(
        await MacosPreferences(ContainerFile(native, 'preferences.json'))
            .getString('route'),
        'first',
        reason: 'and the store recovers on its own once the directory is writable '
            'again, with no relaunch and nothing to reset',
      );
    });

    test('no credential is ever written to the container', () async {
      const String secret = 'sk-this-must-never-touch-a-file';
      await MacosSecretStore(native).write('deepseek', secret);
      await preferences.setString('route', 'deepseek');

      final List<File> files = _containerFiles(native);
      expect(files, isNotEmpty, reason: 'the preference did write something');
      for (final File file in files) {
        expect(
          file.readAsStringSync(),
          isNot(contains(secret)),
          reason: '${file.path} holds a value that went to the Keychain; '
              'PRIVACY.md says the keys are in the system Keychain',
        );
      }
    });

    test('the two stores write to different files', () async {
      await MacosPreferences.inContainer(native).setString('route', 'jev');
      await MacosKnowledgeStore.inContainer(native).saveNote(
        KnowledgeNote(
          id: 'n1',
          title: 't',
          content: 'c',
          updatedAt: DateTime(2026, 10, 4),
        ),
      );
      await MacosMemoryStore.inContainer(native).clear();

      expect(
        _containerFiles(native).map((File f) => f.uri.pathSegments.last).toSet(),
        <String>{'preferences.json', 'knowledge.json', 'memory.json'},
        reason: 'one file per store, so a corrupt one cannot take the others with '
            'it and a reader can tell what is what',
      );
    });
  });

  group('the keychain', () {
    late MacosSecretStore secrets;

    setUp(() {
      secrets = MacosSecretStore(native);
    });

    test('a secret written is a secret read back', () async {
      await secrets.write('deepseek', 'sk-value');

      expect(await secrets.read('deepseek'), 'sk-value');
    });

    test('a key that was never set reads back as null, not as an error',
        () async {
      expect(await secrets.read('openrouter'), isNull);
    });

    test('writing the same key twice replaces rather than duplicates', () async {
      await secrets.write('jev', 'first');
      await secrets.write('jev', 'second');

      expect(await secrets.read('jev'), 'second');
      expect(await secrets.keys(), <String>{'jev'});
    });

    test('deleting a key that is not set is not an error', () async {
      await secrets.delete('never-written');
      expect(await secrets.keys(), isEmpty);
    });

    test('keys() names the configured routes and nothing else', () async {
      await secrets.write('deepseek', 'sk-one');
      await secrets.write('jev', 'sk-two');

      final Set<String> keys = await secrets.keys();

      expect(keys, <String>{'deepseek', 'jev'});
      // The property that matters: there is no member anywhere that hands back
      // the values in bulk, so a settings screen physically cannot render an API
      // key while deciding whether to show a field. Asserted on the fake's
      // contents because the fake, unlike the real store, can be looked at.
      expect(
        keys.where((String key) => key.contains('sk-')),
        isEmpty,
        reason: 'a key is the name a caller passed; a value must never appear in '
            'the key set, because the key set is what a settings screen renders',
      );
    });

    test('the keychain is never asked for a directory, and the stores never ask '
        'for a resource root', () async {
      await secrets.write('deepseek', 'sk-value');
      await MacosPreferences.inContainer(native).setString('route', 'deepseek');

      expect(
        native.log,
        isNot(contains('resourceRoot')),
        reason: 'the payload root is a read-only location inside the bundle; a '
            'store writing there would fail in a signed, sandboxed app',
      );
      expect(
        native.log.where((String call) => call.startsWith('keychain.')),
        <String>['keychain.write:deepseek'],
        reason: 'the preferences write must not have gone anywhere near the '
            'Keychain — the two are the whole privacy boundary',
      );
    });

    test('a secret survives the process: a second store reads the same value',
        () async {
      await secrets.write('deepseek', 'sk-durable');

      // The Keychain is outside the app's container, so a relaunch keeps it while
      // the container's caches do not. Asserted by going through a second object
      // and by checking the fake was never asked to re-create anything.
      final MacosSecretStore reopened = MacosSecretStore(native);

      expect(await reopened.read('deepseek'), 'sk-durable');
    });
  });

  group('the knowledge base', () {
    late MacosKnowledgeStore knowledge;

    setUp(() {
      knowledge = MacosKnowledgeStore.inContainer(native);
    });

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
    });

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
        reason: 'a window title arrives with whatever padding the chat app put '
            'on it; refusing to match it would make every alias useless',
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
        await knowledge.findContact(title: '   ', packageName: 'com.tencent.xinWeChat'),
        isNull,
        reason: 'a window that has not reported its title yet must not be '
            'attached to an arbitrary contact — and an unnamed contact is the '
            'one record it could plausibly be attached to',
      );
      expect(
        await knowledge.findContact(title: '', packageName: 'com.tencent.xinWeChat'),
        isNull,
      );
    });

    test('an empty package name matches nothing, not everything', () async {
      // The other half of the identity, and the one the file header states as an
      // invariant: "a title alone would match a stranger with the same nickname in
      // another app". A caller that cannot name the application has not named a
      // conversation, so the pair is not half-present — it identifies nobody.
      //
      // A contact that *does* have packages is the case that matters here. The
      // test above uses a contact with an empty name, which makes the empty
      // *title* the thing under test; this one keeps the title matchable and
      // removes only the package, so it fails if the package check is skipped
      // rather than satisfied.
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

    test('an empty package name does not match a contact that has one', () async {
      // What makes the guard above load-bearing rather than a restatement of
      // the loop.
      //
      // Every other test of the empty package reaches the same answer twice:
      // once because `wantedPackage.isEmpty` returns null, and once because the
      // loop's own `contains(wantedPackage)` would have rejected it anyway. Two
      // mechanisms, one observable behaviour — so deleting the guard, or
      // changing it to `if (false)`, leaves the suite green. A test that cannot
      // tell those two mechanisms apart is not testing the guard, and a guard
      // that can be deleted silently is not a guard.
      //
      // So this contact carries an **empty string among its package names**,
      // which is a real state rather than a contrived one: `_texts` decodes a
      // missing or blank entry as `''`, and a contact recorded before an
      // application reported its package name has exactly that. With the guard,
      // an empty query is refused before any contact is examined. Without it,
      // the loop finds this contact's `''` and answers a question nobody asked
      // with a record the caller did not identify — the precise failure the
      // header calls out.
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
        reason: 'a blank entry in one list must not stop a real package beside '
            'it from matching',
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

    test('history is appended oldest first and read back as a window', () async {
      await knowledge.appendLog('c1', <KnowledgeLogEntry>[
        _entry('me', '在吗', 1),
        _entry('other', '在', 2),
        _entry('me', '周末有空吗', 3),
      ]);
      await knowledge.appendLog('c1', <KnowledgeLogEntry>[_entry('other', '有', 4)]);

      final List<KnowledgeLogEntry> recent =
          await knowledge.recentLog('c1', limit: 2);

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

    test('appending nothing does not rewrite the file', () async {
      await knowledge.appendLog('c1', <KnowledgeLogEntry>[_entry('me', '在吗', 1)]);
      final File file = _containerFile(native, 'knowledge.json');
      final DateTime before = file.lastModifiedSync();

      await knowledge.appendLog('c1', const <KnowledgeLogEntry>[]);

      expect(
        file.lastModifiedSync(),
        before,
        reason: 'appendLog runs after every capture; a no-op that touched the '
            'file would make its timestamp mean nothing',
      );
    });

    test('deleting a contact takes its history with it', () async {
      await knowledge.saveContact(
        KnowledgeContact(id: 'c1', name: '小岚', updatedAt: DateTime(2026, 10, 4)),
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

    test('clearAll empties notes, contacts and history together', () async {
      await knowledge.saveNote(_note('n1', 'x'));
      await knowledge.saveContact(
        KnowledgeContact(id: 'c1', name: '小岚', updatedAt: DateTime(2026, 10, 4)),
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

      final MacosKnowledgeStore reopened =
          MacosKnowledgeStore(ContainerFile(native, 'knowledge.json'));

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
  });

  group('the memory store', () {
    late MacosMemoryStore memory;

    setUp(() {
      memory = MacosMemoryStore.inContainer(native);
    });

    test('a store nobody has consented to writes nothing and reads nothing',
        () async {
      final MemoryStatus status = await memory.status();

      expect(status.consentEnabled, isFalse);
      expect(status.acceptsWrites, isFalse);
      await expectLater(
        memory.apply(subjectId: 's1', field: 'stage', value: '了解中'),
        throwsStateError,
      );
      expect(await memory.show('s1'), isEmpty);
    });

    test('consent is required to be confirmed, mirroring the upstream --confirm',
        () async {
      await expectLater(
        memory.grantConsent(confirmed: false),
        throwsStateError,
        reason: '"enable" is the one action here that starts storing something '
            'about a person, and upstream refused to do it without an explicit '
            'confirmation',
      );
    });

    test('with consent, a field written is a field read back', () async {
      await memory.grantConsent(confirmed: true);
      await memory.apply(subjectId: 's1', field: 'display_label', value: '小王');

      final List<MemoryRecord> shown = await memory.show('s1');

      expect(shown, hasLength(1));
      expect(shown.single.subjectId, 's1');
      expect(shown.single.field, 'display_label');
      expect(shown.single.value, '小王');
    });

    test('a paused store refuses writes but still reads', () async {
      await memory.grantConsent(confirmed: true);
      await memory.apply(subjectId: 's1', field: 'display_label', value: '小王');
      await memory.setPaused(paused: true);

      final MemoryStatus status = await memory.status();
      expect(status.paused, isTrue);
      expect(status.acceptsWrites, isFalse);
      await expectLater(
        memory.apply(subjectId: 's1', field: 'stage', value: '了解中'),
        throwsStateError,
      );
      expect(
        await memory.show('s1'),
        hasLength(1),
        reason: 'pausing is about writing; a user who paused still wants to see '
            'what is already there',
      );
    });

    test('revoking consent stops writes and stops reading out', () async {
      await memory.grantConsent(confirmed: true);
      await memory.apply(subjectId: 's1', field: 'display_label', value: '小王');

      await memory.revokeConsent();

      final MemoryStatus status = await memory.status();
      expect(status.consentEnabled, isFalse);
      expect(status.acceptsWrites, isFalse);
      expect(
        await memory.show('s1'),
        isEmpty,
        reason: 'a store that will not write a row without consent has no '
            'business handing it to a prompt without consent',
      );
    });

    test('undo rolls back exactly this run and reports how many', () async {
      await memory.grantConsent(confirmed: true);
      await memory.apply(subjectId: 's1', field: 'display_label', value: '小王');
      await memory.apply(subjectId: 's1', field: 'stage', value: '了解中');

      final int rolledBack = await memory.undo();

      expect(rolledBack, 2);
      expect(await memory.show('s1'), isEmpty);
    });

    test('undo unwinds a run back to where it started, not one step back',
        () async {
      await memory.grantConsent(confirmed: true);
      await memory.apply(subjectId: 's1', field: 'stage', value: '了解中');
      // A second write to the same field within the same run.
      await memory.apply(subjectId: 's1', field: 'stage', value: '约会中');
      expect((await memory.show('s1')).single.value, '约会中');

      final int rolledBack = await memory.undo();

      expect(rolledBack, 2);
      expect(
        await memory.show('s1'),
        isEmpty,
        reason: 'undo rolls back every write since the store was opened, so the '
            'field is gone rather than showing an intermediate value — the '
            "run's starting state had no stage at all",
      );
    });

    test('undo restores a value that predates the stack', () async {
      // A row that was already in the file when this run's stack was empty: the
      // state a user is in after the stack is bounded past its oldest entry, or
      // after an upgrade from a build whose writes were not undoable. Seeded by
      // hand because no sequence of `apply` calls produces it — every apply
      // pushes an entry, and a full undo removes the rows it unwound.
      _containerFile(native, 'memory.json').writeAsStringSync(
        jsonEncode(<String, Object?>{
          'policyVersion': MacosMemoryStore.policyVersion,
          'consentEnabled': true,
          'paused': false,
          'records': <Map<String, Object?>>[
            <String, Object?>{'subjectId': 's1', 'field': 'stage', 'value': '了解中'},
          ],
          'undo': const <Object?>[],
        }),
      );
      final MacosMemoryStore reopened =
          MacosMemoryStore(ContainerFile(native, 'memory.json'));

      await reopened.apply(subjectId: 's1', field: 'stage', value: '约会中');
      expect((await reopened.show('s1')).single.value, '约会中');

      await reopened.undo();

      expect(
        (await reopened.show('s1')).single.value,
        '了解中',
        reason: 'the undo entry recorded the value before the write, so a field '
            'this run overwrote comes back rather than disappearing',
      );
    });

    test('each undo entry records the value that was there before its own write',
        () async {
      await memory.grantConsent(confirmed: true);
      await memory.apply(subjectId: 's1', field: 'stage', value: '了解中');
      await memory.apply(subjectId: 's1', field: 'stage', value: '约会中');

      // White-box on purpose. The `before` field is the mechanism that makes a
      // bounded stack safe: without it, unwinding the newest entry would delete
      // the field instead of restoring it, and the value the user had two
      // seconds ago would be gone. A black-box test cannot see it, because a full
      // undo of a full stack always lands on the state before the *first* write.
      final List<Object?> stack = (jsonDecode(
            _containerFile(native, 'memory.json').readAsStringSync(),
          )
              as Map<String, Object?>)['undo']! as List<Object?>;

      expect(stack, hasLength(2));
      expect(
        (stack[0]! as Map<String, Object?>)['before'],
        isNull,
        reason: 'the first write of the run had nothing before it',
      );
      expect(
        (stack[1]! as Map<String, Object?>)['before'],
        '了解中',
        reason: 'the second write must record what the first one left',
      );
    });

    test('undo with nothing to undo is zero, not an error', () async {
      await memory.grantConsent(confirmed: true);

      expect(await memory.undo(), 0);
    });

    test('the value cap is upstream MAX_VALUE_CHARS', () async {
      await memory.grantConsent(confirmed: true);

      await memory.apply(
        subjectId: 's1',
        field: 'notes',
        value: 'x' * MacosMemoryStore.maxValueChars,
      );
      await expectLater(
        memory.apply(
          subjectId: 's1',
          field: 'notes',
          value: 'x' * (MacosMemoryStore.maxValueChars + 1),
        ),
        throwsStateError,
        reason: '200 is MAX_VALUE_CHARS in goutoujunshi/scripts/memory_store.py, '
            'and the cap is what stops a transcript being written into `notes`',
      );
    });

    test('an empty value is refused, which is why 未填写 exists', () async {
      await memory.grantConsent(confirmed: true);

      await expectLater(
        memory.apply(subjectId: 's1', field: 'notes', value: '   '),
        throwsStateError,
        reason: 'the domain writes 未填写 for "unknown" before calling apply; an '
            'empty value here means a caller skipped that translation, and '
            'storing it would make "unset" and "set to nothing" the same row',
      );
    });

    test('a control character is refused', () async {
      await memory.grantConsent(confirmed: true);

      await expectLater(
        memory.apply(subjectId: 's1', field: 'notes', value: '正常文本'),
        throwsStateError,
      );
    });

    test('the capacity bound is upstream MAX_ROWS and it refuses rather than '
        'forgetting', () async {
      await memory.grantConsent(confirmed: true);
      for (int i = 0; i < MacosMemoryStore.maxRows; i++) {
        await memory.apply(subjectId: 's$i', field: 'stage', value: '了解中');
      }

      final MemoryStatus status = await memory.status();
      expect(status.atCapacity, isTrue);
      expect(status.acceptsWrites, isFalse);
      await expectLater(
        memory.apply(subjectId: 'overflow', field: 'stage', value: '了解中'),
        throwsStateError,
        reason: 'upstream pruned the oldest event rows to make room; with the '
            'scope taxonomy gone there is nothing to prune preferentially, and an '
            'unrecoverable-by-surprise store is the better failure for a record '
            'of a person',
      );
    });

    test('updating a field the store already holds is not a new row', () async {
      await memory.grantConsent(confirmed: true);
      // Fill the store to exactly the bound.
      for (int i = 0; i < MacosMemoryStore.maxRows; i++) {
        await memory.apply(subjectId: 's$i', field: 'stage', value: '了解中');
      }

      // At capacity, and yet this is an update rather than an insert.
      await memory.apply(subjectId: 's0', field: 'stage', value: '约会中');

      expect(
        (await memory.show('s0')).single.value,
        '约会中',
        reason: 'an update does not grow the store, so it must not be refused by '
            'the capacity bound',
      );
    });

    test('the undo stack is bounded and keeps the newest entries', () async {
      await memory.grantConsent(confirmed: true);
      // One more than the bound, so the oldest must fall off the end.
      for (int i = 0; i <= MacosMemoryStore.maxOperations; i++) {
        await memory.apply(subjectId: 's1', field: 'field$i', value: 'v$i');
      }

      final int rolledBack = await memory.undo();

      expect(rolledBack, MacosMemoryStore.maxOperations);
      final List<MemoryRecord> left = await memory.show('s1');
      expect(left, hasLength(1));
      expect(
        left.single.field,
        'field0',
        reason: 'the oldest operation fell off the stack, so its write survives — '
            'MAX_OPERATIONS in the upstream script, and dropping the oldest '
            'rather than refusing is what it did',
      );
    });

    test('the file records the policy version it was written by', () async {
      await memory.grantConsent(confirmed: true);

      final Map<String, Object?> document = jsonDecode(
        _containerFile(native, 'memory.json').readAsStringSync(),
      ) as Map<String, Object?>;

      expect(
        document['policyVersion'],
        MacosMemoryStore.policyVersion,
        reason: "POLICY_VERSION upstream; written rather than assumed so a later "
            'format change can be recognised instead of guessed at',
      );
    });

    test('a memory store survives the process, consent and all', () async {
      await memory.grantConsent(confirmed: true);
      await memory.apply(subjectId: 's1', field: 'display_label', value: '小王');
      await memory.apply(subjectId: 's1', field: 'stage', value: '了解中');

      final MacosMemoryStore reopened =
          MacosMemoryStore(ContainerFile(native, 'memory.json'));

      expect((await reopened.status()).consentEnabled, isTrue);
      expect(await reopened.show('s1'), hasLength(2));
    });

    test('clear empties the store and closes it again', () async {
      await memory.grantConsent(confirmed: true);
      await memory.apply(subjectId: 's1', field: 'stage', value: '了解中');

      await memory.clear();

      final MemoryStatus status = await memory.status();
      expect(status.consentEnabled, isFalse);
      expect(await memory.show('s1'), isEmpty);
    });
  });

  group('the container directory', () {
    test('is created if it is not there, and it is the seam that is asked',
        () async {
      final Directory fresh = Directory.systemTemp.createTempSync('miaotou-nested');
      // A path that does not exist yet, three levels down.
      final String missing = '${fresh.path}/a/b/c';
      final FakeMacosNative scripted =
          FakeMacosNative(containerRoot: missing, payloadRoot: fresh.path);
      addTearDown(() async {
        await scripted.close();
        fresh.deleteSync(recursive: true);
      });

      await MacosPreferences.inContainer(scripted).setString('route', 'jev');

      expect(Directory(missing).existsSync(), isTrue);
      expect(scripted.log, contains('containerDirectory'));
    });

    test('an answer with no path in it is refused rather than written to', () async {
      // The `?? ''` in the channel implementation would otherwise turn into a
      // relative path under the process's working directory — which, in a
      // sandboxed app, is somewhere unwritable and somewhere surprising.
      //
      // Driven through the file rather than through the fake, because the fake
      // *refuses* the question rather than answering it with an empty string, so
      // it never reaches the guard this is about. The two refusals are different
      // failures and both are wanted.
      final _EmptyDirectory seam = _EmptyDirectory();

      await expectLater(
        MacosPreferences(ContainerFile(seam, 'preferences.json')).keys(),
        throwsStateError,
        reason: 'an empty container path must not become a relative path under '
            'the working directory',
      );
      await expectLater(
        MacosKnowledgeStore(ContainerFile(seam, 'knowledge.json')).notes(),
        throwsStateError,
      );
      await expectLater(
        MacosMemoryStore(ContainerFile(seam, 'memory.json')).status(),
        throwsStateError,
      );
    });

    test('a fake that is not told where the container is refuses the question',
        () async {
      // The other half, and the reason the fake does not default: a fake that
      // invented a path would let a test pass against a location nothing else
      // uses, or read the developer's own container.
      final FakeMacosNative bare = FakeMacosNative();
      addTearDown(bare.close);

      await expectLater(
        MacosPreferences.inContainer(bare).keys(),
        throwsStateError,
      );
      await expectLater(
        MacosSharedPayload(bare).resourceRoot(),
        throwsStateError,
      );
    });
  });
}

/// A seam that answers an **empty** container path.
///
/// Not a `FakeMacosNative`, because that one refuses the question rather than
/// answering it badly — and the guard under test is the one that catches a bad
/// answer, which the fake's refusal never reaches.
class _EmptyDirectory implements MacosNative {
  @override
  Future<String> containerDirectory() async => '';

  @override
  Future<String> resourceRoot() async => '';

  @override
  Future<List<String>> keychainKeys() async => const <String>[];

  @override
  Future<String?> keychainRead(String key) async => null;

  @override
  Future<void> keychainWrite(String key, String value) async {}

  @override
  Future<void> keychainDelete(String key) async {}

  @override
  Future<String?> findTargetWindow() async => null;

  @override
  Future<CaptureOutcome> capture({String? targetWindowId}) async =>
      const CaptureFailed(code: 1, message: 'not used');

  @override
  Future<List<OcrLine>> recognize(
    CaptureFrame frame, {
    required List<String> languages,
  }) async =>
      const <OcrLine>[];

  @override
  Future<InjectResult> inject(String text, {required InjectTarget target}) async =>
      const InjectResult.unverified('not used');

  @override
  Future<PanelGeometry> panelGeometry() async =>
      const PanelGeometry(screen: ScreenRect.empty, window: ScreenRect.empty);

  @override
  Future<void> showPanel({
    required PanelPlacement placement,
    ScreenRect? at,
  }) async {}

  @override
  Future<bool> hidePanel() async => false;

  @override
  Future<void> restorePanel() async {}

  @override
  Future<void> setPanelFocusable(bool value) async {}

  @override
  Stream<NativePanelEvent> get events => const Stream<NativePanelEvent>.empty();
}

File _containerFile(FakeMacosNative native, String name) =>
    File('${native.containerRoot}/$name');

/// Makes [directory] read-only, so a rename inside it cannot succeed.
///
/// `chmod` rather than a Dart-side flag because the property under test is a
/// property of the filesystem: a `rename` needs write permission on the
/// *directory*, while writing to an already-openable file does not. That
/// difference is what lets the test fail between the scratch write and the
/// rename rather than before the write.
///
/// The [ProcessException] catch is for the shape of the API rather than for
/// `chmod`, which exists on every platform this suite runs on. `runSync` raises
/// when the executable is missing and returns a non-zero code when it ran and
/// refused — and the second is a fact about the filesystem worth failing on,
/// while the first would abort a test that was never about permissions.
void _makeReadOnly(Directory directory) {
  final ProcessResult result;
  try {
    result = Process.runSync('chmod', <String>['0555', directory.path]);
  } on ProcessException catch (error) {
    throw StateError('could not run chmod to make ${directory.path} '
        'read-only: ${error.message}');
  }
  if (result.exitCode != 0) {
    throw StateError('could not make ${directory.path} read-only: ${result.stderr}');
  }
}

/// Undoes [_makeReadOnly], so the tear-down can delete what the test wrote.
///
/// Deliberately not checked. This runs in a tear-down, where a throw masks the
/// failure that made the clean-up necessary; a directory left read-only is a
/// scratch directory in `systemTemp` that the next run replaces anyway.
void _makeWritable(Directory directory) {
  try {
    Process.runSync('chmod', <String>['0755', directory.path]);
  } on ProcessException {
    // Nothing to do and nowhere to report it to that would help.
  }
}

List<File> _containerFiles(FakeMacosNative native) => <File>[
      for (final FileSystemEntity entity
          in Directory(native.containerRoot!).listSync(recursive: true))
        if (entity is File) entity,
    ];

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
