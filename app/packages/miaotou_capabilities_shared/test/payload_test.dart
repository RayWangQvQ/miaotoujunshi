import 'dart:convert';
import 'dart:typed_data';

import 'package:miaotou_capabilities_shared/miaotou_capabilities_shared.dart';
import 'package:test/test.dart';

import 'fake_payload_tree.dart';

/// The shared payload, in one suite for all three ports.
///
/// AC3 of #15 says the packaged application reads the payload **as real files,
/// with no copy inlined into the port**. The packaging half of that is each
/// platform's build and is asserted where it happens; this is the half that is the
/// same everywhere — what a key is, what a missing one means, and what a listing
/// is allowed to contain.
void main() {
  late FakePayloadTree tree;
  late PayloadReader payload;

  setUp(() {
    tree = FakePayloadTree()
      ..put(
        'miaotoujunshi/references/data/payload-map.json',
        '{"strategy_guide": "g.md"}',
      )
      ..put(
        'miaotoujunshi/references/data/strategy-criteria.json',
        '{"strategies": ["A"]}',
      )
      ..put('miaotoujunshi/references/data/nested/deep.json', '{"deep": true}');
    payload = PayloadReader(tree);
  });

  test('a key is read as the bytes of the file at that path', () async {
    final Uint8List bytes = await payload.read(
      'miaotoujunshi/references/data/payload-map.json',
    );

    expect(
      utf8.decode(bytes),
      '{"strategy_guide": "g.md"}',
      reason: 'the key is repository-root-relative and resolves against the '
          'packaged tree, which is what keeps the built artifact mirroring the '
          'repository (ADR-0008 decision 3)',
    );
  });

  test('a key with Chinese characters in it resolves, because the payload has them',
      () async {
    tree.put('miaotoujunshi/references/knowledge/口吻与取舍.md', '口吻规则');

    expect(
      utf8.decode(
        await payload.read('miaotoujunshi/references/knowledge/口吻与取舍.md'),
      ),
      '口吻规则',
    );
  });

  test('a missing key is a hard error, not an empty buffer', () async {
    await expectLater(
      payload.read('miaotoujunshi/references/data/does-not-exist.json'),
      throwsA(
        isA<StateError>().having(
          (StateError error) => error.message,
          'message',
          allOf(
            contains('packaging fault'),
            contains('miaotoujunshi/references/data/does-not-exist.json'),
          ),
        ),
      ),
      reason: 'a caller that gets bytes back must be able to trust they came from '
          'the payload; an empty buffer is indistinguishable from an empty '
          'document, and the caller is a prompt. The message is asserted as well '
          'as the type because the type is the shared module\'s general refusal — '
          'what carries the diagnosis here is the sentence, and a guard on the '
          'type alone would not notice losing it',
    );
  });

  test('a missing directory is a hard error, not an empty list', () async {
    await expectLater(
      payload.list('miaotoujunshi/references/data/does-not-exist'),
      throwsA(
        isA<StateError>().having(
          (StateError error) => error.message,
          'message',
          contains('packaging fault'),
        ),
      ),
    );
  });

  test('listing a directory needs no member list', () async {
    expect(await payload.list('miaotoujunshi/references/data'), <String>[
      'payload-map.json',
      'strategy-criteria.json',
    ]);
  });

  test('listing is not recursive, because the contract asks about one directory',
      () async {
    expect(
      await payload.list('miaotoujunshi/references/data'),
      isNot(contains('nested/deep.json')),
      reason: 'a walk would answer a different question than the one asked; the '
          'caller that wants the nested names asks for that directory by name',
    );
  });

  test('the listing is sorted', () async {
    // `listSync` order is the filesystem's, which differs between the three
    // platforms and between two runs on one of them. A caller that renders the
    // names, or compares two listings, needs one answer.
    tree
      ..put('miaotoujunshi/references/data/zebra.json', '{}')
      ..put('miaotoujunshi/references/data/alpha.json', '{}');

    expect(await payload.list('miaotoujunshi/references/data'), <String>[
      'alpha.json',
      'payload-map.json',
      'strategy-criteria.json',
      'zebra.json',
    ]);
  });

  test('a file added to the payload is visible with no code change', () async {
    tree.put('miaotoujunshi/references/data/added-later.json', '{}');

    expect(
      await payload.list('miaotoujunshi/references/data'),
      contains('added-later.json'),
      reason: 'ADR-0008 decision 5: a zero-change addition has to be observable at '
          'runtime, not only in a build log',
    );
  });

  group('a key that leaves the payload tree', () {
    test('is refused, and it is an ArgumentError rather than a read failure',
        () async {
      // The three ports disagreed about this list. macOS rejected the first three
      // and accepted the last two; Windows rejected the fourth; Android rejected
      // all five. Neither of the last two names anything the payload has, so the
      // strictest list wins.
      for (final String key in <String>[
        '../secrets.txt',
        'miaotoujunshi/../../secrets.txt',
        '/etc/passwd',
        '',
        r'\etc\passwd',
        'miaotoujunshi//data.json',
        'miaotoujunshi/references\\data.json',
      ]) {
        for (final Future<Object?> Function() call in <Future<Object?> Function()>[
          () => payload.read(key),
          () => payload.list(key),
        ]) {
          await expectLater(
            call(),
            throwsArgumentError,
            reason: '"$key" must not resolve: a key that walked out of the '
                'payload would read a file the application does not ship, which '
                'is the one thing resolving keys against the payload is for',
          );
        }
      }
    });

    test('but a name that merely contains ".." is not a traversal', () async {
      // The boundary of the rule: `..` is matched as a whole segment, not as a
      // substring, and a payload file is allowed to be called `a..b.json`. A
      // substring test would refuse a legal key, which is a different bug from
      // the one the guard exists for.
      tree.put('miaotoujunshi/references/data/v1..2.json', '{}');

      expect(
        utf8.decode(await payload.read('miaotoujunshi/references/data/v1..2.json')),
        '{}',
      );
    });
  });
}
