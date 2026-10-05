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
            'preferences.read' => 'value',
            'preferences.keys' => <String>['route'],
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
      expect(await native.readPreference('route', 'string'), 'value');
      await native.writePreference('route', 'string', 'deepseek');
      await native.removePreference('route');
      expect(await native.preferenceKeys(), <String>{'route'});
      expect(await native.readSecret('deepseek'), 'secret');
      await native.writeSecret('deepseek', 'secret');
      await native.deleteSecret('deepseek');
      expect(await native.secretKeys(), <String>{'deepseek'});
      expect(await native.readDocument('memory.json'), '{"value":1}');
      await native.writeDocument('memory.json', '{"value":2}');

      expect(calls.map((MethodCall call) => call.method), <String>[
        'payload.read',
        'payload.list',
        'preferences.read',
        'preferences.write',
        'preferences.remove',
        'preferences.keys',
        'secret.read',
        'secret.write',
        'secret.delete',
        'secret.keys',
        'document.read',
        'document.write',
      ]);
    },
  );

  test('a missing native payload listing is a hard error', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async => null);
    final MethodChannelAndroidStorageNative native =
        MethodChannelAndroidStorageNative(channel: channel);

    await expectLater(
      native.listPayload('miaotoujunshi/references/data'),
      throwsStateError,
    );
  });
}
