import 'dart:typed_data';

import 'package:miaotou_capabilities_android/miaotou_capabilities_android.dart';
import 'package:miaotou_capabilities_android/testing.dart';
import 'package:test/test.dart';

void main() {
  test('reads and lists packaged assets through the native seam', () async {
    final MemoryAndroidStorageNative native = MemoryAndroidStorageNative(
      payload: <String, Uint8List>{
        'miaotoujunshi/references/data/trend-rules.json': Uint8List.fromList(
          '{"version":1}'.codeUnits,
        ),
      },
    );
    final AndroidSharedPayload payload = AndroidSharedPayload(native);

    expect(
      await payload.read('miaotoujunshi/references/data/trend-rules.json'),
      Uint8List.fromList('{"version":1}'.codeUnits),
    );
    expect(await payload.list('miaotoujunshi/references/data'), <String>[
      'trend-rules.json',
    ]);
  });

  test(
    'a new payload file appears without a Dart or build-list change',
    () async {
      final MemoryAndroidStorageNative native = MemoryAndroidStorageNative(
        payload: <String, Uint8List>{
          'miaotoujunshi/references/data/trend-rules.json': Uint8List(0),
        },
      );
      final AndroidSharedPayload payload = AndroidSharedPayload(native);
      native.payload['miaotoujunshi/references/data/new.json'] = Uint8List(0);

      expect(await payload.list('miaotoujunshi/references/data'), <String>[
        'new.json',
        'trend-rules.json',
      ]);
    },
  );

  test('escaping and missing keys are refused', () async {
    final AndroidSharedPayload payload = AndroidSharedPayload(
      MemoryAndroidStorageNative(),
    );

    expect(() => payload.read('../secret'), throwsArgumentError);
    await expectLater(
      payload.read('miaotoujunshi/missing.json'),
      throwsA(isA<StateError>()),
    );
    await expectLater(
      payload.list('miaotoujunshi/missing'),
      throwsA(isA<StateError>()),
    );
  });
}
