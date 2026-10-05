import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miaotou_capabilities/miaotou_capabilities.dart';
import 'package:miaotou_capabilities_android/miaotou_capabilities_android.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannel permissions = MethodChannel(
    MethodChannelAndroidPermissionNative.channelName,
  );

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(permissions, null);
  });

  test('uses its own channel, not the control channel', () {
    expect(
      MethodChannelAndroidPermissionNative.channelName,
      'miaotoujunshi/android/permissions',
    );
    expect(
      MethodChannelAndroidPermissionNative.channelName,
      isNot(MethodChannelAndroidIngestNative.controlChannelName),
      reason:
          'the control channel refuses outright while the accessibility '
          'service is off, which is the one moment this one has to answer '
          '(ADR-0021)',
    );
  });

  test('read decodes the three-state answer, including 勾了但没绑定', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(permissions, (MethodCall call) async {
          expect(call.method, 'read');
          return <String, Object?>{
            'accessibility': 'inactive',
            'overlay': 'off',
          };
        });

    final PermissionReport report =
        await MethodChannelAndroidPermissionNative().readPermissions();

    expect(report.accessibility, PermissionState.inactive);
    expect(report.overlay, PermissionState.off);
  });

  test('a state this build does not understand is an error, not an off', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(permissions, (MethodCall call) async {
          return <String, Object?>{
            'accessibility': 'granted_but_frozen',
            'overlay': 'ready',
          };
        });

    expect(
      MethodChannelAndroidPermissionNative().readPermissions(),
      throwsFormatException,
      reason:
          'silently answering `off` would tell a user who granted it that they '
          'never did, which is the reading ADR-0018 was lost in once already',
    );
  });

  test('open sends the kind under the enum name the Kotlin half reads', () async {
    final List<MethodCall> calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(permissions, (MethodCall call) async {
          calls.add(call);
          return null;
        });

    final AndroidPermissions capabilities = AndroidPermissions(
      MethodChannelAndroidPermissionNative(),
    );
    await capabilities.openSettings(PermissionKind.accessibility);
    await capabilities.openSettings(PermissionKind.overlay);

    expect(calls.map((MethodCall call) => call.method), <String>['open', 'open']);
    expect(calls[0].arguments, <String, Object?>{'kind': 'accessibility'});
    expect(calls[1].arguments, <String, Object?>{'kind': 'overlay'});
  });
}
