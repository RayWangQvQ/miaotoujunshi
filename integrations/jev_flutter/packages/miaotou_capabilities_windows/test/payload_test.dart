import 'dart:io';
import 'dart:typed_data';

import 'package:miaotou_capabilities_windows/miaotou_capabilities_windows.dart';
import 'package:test/test.dart';

void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('miaotou-payload-');
    Directory(
      '${root.path}/miaotoujunshi/references/data',
    ).createSync(recursive: true);
    File(
      '${root.path}/miaotoujunshi/references/data/trend-rules.json',
    ).writeAsStringSync('{"version":1}');
  });
  tearDown(() => root.deleteSync(recursive: true));

  test('reads and lists real files beside the executable', () async {
    final WindowsSharedPayload payload = WindowsSharedPayload(root);
    expect(
      await payload.read('miaotoujunshi/references/data/trend-rules.json'),
      Uint8List.fromList('{"version":1}'.codeUnits),
    );
    expect(await payload.list('miaotoujunshi/references/data'), <String>[
      'trend-rules.json',
    ]);
  });

  test('a new payload file appears without a build-list change', () async {
    final WindowsSharedPayload payload = WindowsSharedPayload(root);
    File(
      '${root.path}/miaotoujunshi/references/data/new.json',
    ).writeAsStringSync('{}');

    expect(await payload.list('miaotoujunshi/references/data'), <String>[
      'new.json',
      'trend-rules.json',
    ]);
  });

  test('missing and escaping keys are refused', () async {
    final WindowsSharedPayload payload = WindowsSharedPayload(root);
    await expectLater(
      payload.read('miaotoujunshi/references/data/missing.json'),
      throwsA(isA<FileSystemException>()),
    );
    await expectLater(payload.read('../secret'), throwsArgumentError);
  });
}
