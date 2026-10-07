import 'dart:io';
import 'dart:typed_data';

import 'package:miaotou_capabilities_windows/miaotou_capabilities_windows.dart';
import 'package:test/test.dart';

/// What this port still owns of the shared payload: the directory the build
/// copied it into.
///
/// What a key is, and what a missing one means, moved to
/// `miaotou_capabilities_shared` and is asserted there once for all three ports.
/// What is left here is the join — a `/`-separated key onto a Windows path — and
/// the fact that the tree is real files rather than anything inlined.
void main() {
  late Directory root;
  late PayloadReader payload;

  setUp(() {
    root = Directory.systemTemp.createTempSync('miaotou-payload-');
    Directory(
      '${root.path}/miaotoujunshi/references/data',
    ).createSync(recursive: true);
    File(
      '${root.path}/miaotoujunshi/references/data/trend-rules.json',
    ).writeAsStringSync('{"version":1}');
    payload = PayloadReader(WindowsPayloadTree(root));
  });

  tearDown(() => root.deleteSync(recursive: true));

  test('reads and lists real files beside the executable', () async {
    expect(
      await payload.read('miaotoujunshi/references/data/trend-rules.json'),
      Uint8List.fromList('{"version":1}'.codeUnits),
      reason: 'the key is `/`-separated because it is a repository path, and the '
          'separator a Windows path needs is not',
    );
    expect(await payload.list('miaotoujunshi/references/data'), <String>[
      'trend-rules.json',
    ]);
  });

  test('a new payload file appears without a build-list change', () async {
    File(
      '${root.path}/miaotoujunshi/references/data/new.json',
    ).writeAsStringSync('{}');

    expect(await payload.list('miaotoujunshi/references/data'), <String>[
      'new.json',
      'trend-rules.json',
    ]);
  });

  test('a file that is not there is the shared refusal, not an empty buffer',
      () async {
    await expectLater(
      payload.read('miaotoujunshi/references/data/missing.json'),
      throwsA(
        isA<StateError>().having(
          (StateError error) => error.message,
          'message',
          contains('packaging fault'),
        ),
      ),
    );
  });

  test('a key that leaves the payload tree is refused', () async {
    await expectLater(payload.read('../secret'), throwsArgumentError);
    await expectLater(payload.read(r'miaotoujunshi\data.json'), throwsArgumentError);
  });
}
