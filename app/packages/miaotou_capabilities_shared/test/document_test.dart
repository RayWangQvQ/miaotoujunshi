import 'dart:convert';

import 'package:miaotou_capabilities_shared/miaotou_capabilities_shared.dart';
import 'package:test/test.dart';

import 'fake_documents.dart';

/// [JsonDocument]'s own behaviour, over the in-process seam.
///
/// Everything the three stores rest on lives here rather than in three ports'
/// suites: what an absent document means, what a damaged one means, and the one
/// property that makes the design safe — that nothing is remembered between calls,
/// so two stores over one document cannot lose each other's writes.
void main() {
  late FakeDocuments documents;
  late JsonDocument file;

  setUp(() {
    documents = FakeDocuments();
    file = JsonDocument(documents, 'x.json');
  });

  test('a document that has never been written holds nothing', () async {
    expect(await file.read(), <String, Object?>{});
  });

  test('an empty or whitespace-only document holds nothing', () async {
    // Both shapes are what a create-and-truncate leaves behind, and neither is a
    // parse error worth refusing a store over.
    for (final String blank in <String>['', '   ', '\n\t ']) {
      documents.put('x.json', blank);

      expect(
        await file.read(),
        <String, Object?>{},
        reason: 'a $blank document is nothing stored, not a corrupt one',
      );
    }
  });

  test('a document that is not a JSON object is refused, and names itself',
      () async {
    // The scenario is a half-written file from a crash. Reading it as an empty
    // store would present "you have nothing" as the truth and then write over
    // whatever was salvageable on the next save.
    for (final String corrupt in <String>[
      '{"route": "dee', // truncated mid-value: fails inside the decoder
      '[1, 2, 3]', // valid JSON, wrong shape: reaches the object guard
      'not json at all', // not JSON: fails inside the decoder
      '"a string"', // valid JSON, deliberately the wrong shape
      '7',
    ]) {
      documents.put('x.json', corrupt);

      await expectLater(
        file.read(),
        throwsFormatException,
        reason: '"$corrupt" must not read as an empty store',
      );
    }
  });

  test('the refusal names the file a reader has to go and look at', () async {
    documents.put('x.json', '[1, 2, 3]');

    await expectLater(
      file.read(),
      throwsA(
        isA<FormatException>().having(
          (FormatException error) => error.message,
          'message',
          contains('x.json'),
        ),
      ),
      reason: 'a refusal that does not say which document is damaged leaves the '
          'reader with a stack trace and no file name',
    );
  });

  test('what is written is indented JSON, so the file stays readable', () async {
    await file.write(<String, Object?>{'route': 'deepseek'});

    expect(documents.raw('x.json'), '{\n  "route": "deepseek"\n}');
  });

  test('a failed read is not remembered, so a store recovers on its own',
      () async {
    // A read can fail for a reason that goes away — a file mid-rewrite, a volume
    // not yet mounted. Caching the failure would make the store permanently
    // unreadable until a relaunch, with nothing to tell the user what happened.
    documents.put('x.json', '{"route": "dee');

    await expectLater(file.read(), throwsFormatException);

    documents.put('x.json', '{"route":"deepseek"}');

    expect(
      await file.read(),
      <String, Object?>{'route': 'deepseek'},
      reason: 'the same object, after the document became readable again',
    );
  });

  test('a second document over the same name sees the first one\'s write',
      () async {
    // The property that makes this class safe to build three stores over. Two
    // documents over one name is not a contrived setup: every port builds a fresh
    // set of stores whenever its bundle factory is called, and the application
    // resolves them through `capabilitiesForCurrentPlatform()`, which memoises
    // nothing.
    expect(await file.read(), isEmpty);

    await JsonDocument(documents, 'x.json').write(
      <String, Object?>{'route': 'deepseek'},
    );

    expect(
      await file.read(),
      <String, Object?>{'route': 'deepseek'},
      reason: 'the first document did not write this and is still the object a '
          'caller holds; it must not answer from a value that was current when it '
          'was first asked',
    );
  });

  test('the document is asked for on every call, never held', () async {
    await file.read();
    await file.read();
    await file.write(<String, Object?>{});

    expect(
      documents.reads,
      <String>['x.json', 'x.json'],
      reason: 'a read that named the document twice is the evidence that nothing '
          'is cached; the count, not the answer, is the thing under test',
    );
    expect(documents.writeCount('x.json'), 1);
  });

  test('a write replaces the whole document rather than merging into it',
      () async {
    await file.write(<String, Object?>{'route': 'deepseek', 'model': 'gpt'});
    await file.write(<String, Object?>{'route': 'jev'});

    expect(
      decoded(documents.raw('x.json')!),
      <String, Object?>{'route': 'jev'},
      reason: 'the stores merge by reading first and writing the union; a '
          'document that merged here would make that read-then-write advisory '
          'rather than the thing that decides the contents',
    );
  });
}

Map<String, Object?> decoded(String text) =>
    (jsonDecode(text) as Map<String, Object?>);
