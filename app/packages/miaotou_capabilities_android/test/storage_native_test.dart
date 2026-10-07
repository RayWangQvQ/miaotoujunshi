import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miaotou_capabilities_android/miaotou_capabilities_android.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const MethodChannel channel = MethodChannel(
    MethodChannelAndroidStorageNative.channelName,
  );
  final List<MethodCall> calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
          calls.add(call);
          return switch (call.method) {
            'payload.read' => Uint8List.fromList(<int>[1, 2]),
            'payload.list' => <String>['b', 'a'],
            'secret.read' => 'secret',
            'secret.keys' => <String>['deepseek'],
            'document.read' => '{"value":1}',
            _ => null,
          };
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test(
    'uses the one Android storage channel with stable method names',
    () async {
      final MethodChannelAndroidStorageNative native =
          MethodChannelAndroidStorageNative(channel: channel);

      expect(await native.readPayload('miaotoujunshi/a.json'), <int>[1, 2]);
      expect(await native.listPayload('miaotoujunshi'), <String>['b', 'a']);
      expect(await native.readSecret('deepseek'), 'secret');
      await native.writeSecret('deepseek', 'secret');
      await native.deleteSecret('deepseek');
      expect(await native.secretKeys(), <String>{'deepseek'});
      expect(await native.readDocument('memory.json'), '{"value":1}');
      await native.writeDocument('memory.json', '{"value":2}');

      expect(calls.map((MethodCall call) => call.method), <String>[
        'payload.read',
        'payload.list',
        'secret.read',
        'secret.write',
        'secret.delete',
        'secret.keys',
        'document.read',
        'document.write',
      ]);
    },
  );

  test('the settings members are gone from the channel', () async {
    // The four `preferences.*` members used to be here, and the point of removing
    // them is that nothing may quietly reintroduce a second route to the settings
    // document: the record shape is the shared module's decision, and a Kotlin
    // side that answered `preferences.read` would be a fourth implementation of
    // it. A name that is not on the interface cannot be called, so this asserts
    // the *absence* on the wire rather than on the type.
    final MethodChannelAndroidStorageNative native =
        MethodChannelAndroidStorageNative(channel: channel);

    await native.readPayload('miaotoujunshi/a.json');
    await native.readSecret('deepseek');
    await native.readDocument('preferences.json');

    expect(
      calls
          .map((MethodCall call) => call.method)
          .where((String method) => method.startsWith('preferences.')),
      isEmpty,
    );
  });

  test('a listing the package does not have is nothing, not an empty list',
      () async {
    // `null` and `[]` are different answers and this seam keeps them apart: an
    // empty list would reach a caller as "this payload directory is empty", which
    // is indistinguishable from a real answer. Android answers null for a missing
    // directory and for an empty one alike, because inside an APK those are the
    // same fact — and the shared reader turns the null into the refusal, so the
    // diagnosis is written once rather than here.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async => null);
    final MethodChannelAndroidStorageNative native =
        MethodChannelAndroidStorageNative(channel: channel);

    expect(await native.readPayload('miaotoujunshi/references/data'), isNull);
    expect(await native.listPayload('miaotoujunshi/references/data'), isNull);
  });
}
