import 'dart:typed_data';

import 'package:miaotou_capabilities_android/miaotou_capabilities_android.dart';
import 'package:miaotou_capabilities_android/testing.dart';
import 'package:test/test.dart';

/// What this port still owns of the shared payload: the assets in the APK.
///
/// What a key is, and what a missing one means, moved to
/// `miaotou_capabilities_shared` and is asserted there once for all three ports.
/// What is left here is the seam itself — that a key becomes an `assets` lookup
/// and an absence becomes a null rather than a plausible empty answer.
void main() {
  late MemoryAndroidStorageNative native;
  late PayloadReader payload;

  setUp(() {
    native = MemoryAndroidStorageNative(
      payload: <String, Uint8List>{
        'miaotoujunshi/references/data/trend-rules.json': Uint8List.fromList(
          '{"version":1}'.codeUnits,
        ),
      },
    );
    payload = PayloadReader(AndroidPayloadTree(native));
  });

  test('reads and lists packaged assets through the native seam', () async {
    expect(
      await payload.read('miaotoujunshi/references/data/trend-rules.json'),
      Uint8List.fromList('{"version":1}'.codeUnits),
    );
    expect(await payload.list('miaotoujunshi/references/data'), <String>[
      'trend-rules.json',
    ]);
  });

  test(
    'a payload file added to the package appears with no Dart change',
    () async {
      native.payload['miaotoujunshi/references/data/new.json'] = Uint8List(0);

      expect(await payload.list('miaotoujunshi/references/data'), <String>[
        'new.json',
        'trend-rules.json',
      ]);
    },
  );

  test('an asset the package does not have is nothing, not an empty buffer',
      () async {
    // The seam's own answer, asserted at the seam: null. The hard error is the
    // reader's, one level up, so that a caller cannot receive an empty list and
    // mistake it for a real one — and so that the words are the same on all three
    // ports. The reader half is asserted in `miaotou_capabilities_shared`.
    expect(await native.readPayload('miaotoujunshi/missing.json'), isNull);
    expect(await native.listPayload('miaotoujunshi/missing'), isNull);
  });

  test('and that null becomes the shared refusal, not an empty answer',
      () async {
    await expectLater(
      payload.read('miaotoujunshi/missing.json'),
      throwsA(
        isA<StateError>().having(
          (StateError error) => error.message,
          'message',
          contains('packaging fault'),
        ),
      ),
    );
    await expectLater(
      payload.list('miaotoujunshi/missing'),
      throwsA(isA<StateError>()),
    );
  });

  test('a key that leaves the assets tree is refused before the channel',
      () async {
    // The Kotlin half validates the same keys again, as the device-side boundary
    // it is; this asserts the refusal a Dart caller meets, which happens without a
    // round trip.
    await expectLater(payload.read('../secret'), throwsArgumentError);
    await expectLater(payload.read('/etc/passwd'), throwsArgumentError);
  });
}
