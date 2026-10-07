import 'dart:convert';

import 'package:miaotou_capabilities_shared/miaotou_capabilities_shared.dart';
import 'package:test/test.dart';

import 'fake_documents.dart';

/// The three ports' preferences store, in one suite.
///
/// This is the only place these behaviours are asserted. Android answered this
/// capability out of `SharedPreferences` until the shared module landed, so the
/// three implementations had drifted: only one of them sorted a list on the way
/// out, and the three disagreed about what a record whose tag contradicted its
/// value meant. Both of those are pinned below, at the point where the divergence
/// was.
void main() {
  late FakeDocuments documents;
  late PreferenceLedger preferences;

  setUp(() {
    documents = FakeDocuments();
    preferences = PreferenceLedger(documents);
  });

  test('a value written is a value read back, with its type intact', () async {
    await preferences.setString('route', 'deepseek');
    await preferences.setBool('autoAnalyse', true);
    await preferences.setInt('candidates', 3);
    await preferences.setStringList('whitelist', <String>['x', 'y']);

    expect(await preferences.getString('route'), 'deepseek');
    expect(await preferences.getBool('autoAnalyse'), isTrue);
    expect(await preferences.getInt('candidates'), 3);
    expect(await preferences.getStringList('whitelist'), <String>['x', 'y']);
  });

  test('a key that was never set reads back as null, not as an error',
      () async {
    expect(await preferences.getString('absent'), isNull);
    expect(await preferences.getBool('absent'), isNull);
    expect(await preferences.getInt('absent'), isNull);
    expect(await preferences.getStringList('absent'), isNull);
  });

  test('reading a key as the wrong type gives null rather than a coercion',
      () async {
    // The dangerous shape: `autoAnalyse` is a bool, and a store that returned the
    // string "false" for it would let a caller branch on a value that is never
    // what was written.
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
      reason: 'the contract calls this a set, so two writes of the same set must '
          'produce the same document',
    );
  });

  test('the same set written in two orders leaves one document, not two',
      () async {
    await preferences.setStringList('whitelist', <String>['a', 'b']);
    final String? first = documents.raw('preferences.json');
    await preferences.setStringList('whitelist', <String>['b', 'a']);

    expect(
      documents.raw('preferences.json'),
      first,
      reason: 'a settings diff that shows a change nobody made is a bug report '
          'waiting to happen',
    );
  });

  test('reading does not sort, so a hand-edited order survives', () async {
    // Android sorted on the way out, which meant the same file read back in a
    // different order there than on the two desktop ports. The write already
    // canonicalises, so a second normalisation has nothing to fix — and a rule
    // that only some reads obey is a rule nobody can rely on.
    documents.put(
      'preferences.json',
      jsonEncode(<String, Object?>{
        'whitelist': <String, Object?>{
          'type': 'stringList',
          'value': <String>['b', 'a'],
        },
      }),
    );

    expect(
      await preferences.getStringList('whitelist'),
      <String>['b', 'a'],
      reason: 'what is in the document is what is handed back; the only thing '
          'this store is allowed to canonicalise is what it writes',
    );
  });

  test('a record whose tag contradicts its value is reported, not coerced',
      () async {
    // The two desktop ports disagreed here: one cast and threw a bare
    // `TypeError`, the other answered null, and neither named the key. There is
    // no answer to "string, holding 7" that is not a guess, so this is the one
    // damaged shape the store refuses — and it says which key.
    documents.put(
      'preferences.json',
      jsonEncode(<String, Object?>{
        'route': <String, Object?>{'type': 'string', 'value': 7},
      }),
    );

    await expectLater(
      preferences.getString('route'),
      throwsA(
        isA<StateError>().having(
          (StateError error) => error.message,
          'message',
          contains('route'),
        ),
      ),
    );
  });

  test('a string list holding a non-string is reported too', () async {
    documents.put(
      'preferences.json',
      jsonEncode(<String, Object?>{
        'whitelist': <String, Object?>{
          'type': 'stringList',
          'value': <Object?>['a', 7],
        },
      }),
    );

    await expectLater(
      preferences.getStringList('whitelist'),
      throwsA(isA<StateError>()),
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

  test('a store survives the process: a second store over the same document '
      'reads what the first wrote', () async {
    await preferences.setString('route', 'openrouter');
    await preferences.setStringList('whitelist', <String>['x', 'y']);

    // A *different object*, which is what a relaunch is.
    final PreferenceLedger reopened = PreferenceLedger(documents);

    expect(await reopened.getString('route'), 'openrouter');
    expect(await reopened.getStringList('whitelist'), <String>['x', 'y']);
    expect(await reopened.keys(), <String>{'route', 'whitelist'});
  });

  test('a corrupt settings document is refused rather than read as empty',
      () async {
    // One store for all three shapes: the memoised read that used to force one
    // store per shape is gone from `JsonDocument`, so a single object reaches
    // every branch.
    for (final String corrupt in <String>[
      '{"route": "dee', // truncated mid-value: fails inside the decoder
      '[1, 2, 3]', // valid JSON, wrong shape: reaches the Map guard
      'not json at all', // not JSON: fails inside the decoder
    ]) {
      documents.put('preferences.json', corrupt);

      await expectLater(
        preferences.keys(),
        throwsFormatException,
        reason: '"$corrupt" must not read as an empty store',
      );
    }
  });

  test('a store that wrote a key away does not resurrect it', () async {
    // The lost update, which is the damaging half. A store that read before the
    // deletion and writes afterwards puts the deleted key back — so this is the
    // test that says a stale read is not merely a stale display.
    await preferences.setString('route', 'deepseek');
    await preferences.setString('model', 'gpt');
    expect(await preferences.keys(), <String>{'route', 'model'});

    // A different object removes one, then the first store saves an unrelated
    // key — the ordinary sequence of two screens touching one settings document.
    await PreferenceLedger(documents).remove('route');
    await preferences.setString('candidates', '3');

    expect(
      await preferences.keys(),
      <String>{'model', 'candidates'},
      reason: 'the removal has to survive a later write from another store; a '
          'store that rewrote a document it had not re-read would put the deleted '
          'key back',
    );
  });

  test('the document is named preferences.json', () {
    // The name is part of the port's contract with the user, not an internal
    // detail: it is the file a support request asks them to look at.
    expect(PreferenceLedger.fileName, 'preferences.json');
  });
}
