import 'dart:io';

import 'package:test/test.dart';

void main() {
  final String source = File(
    'android/src/main/kotlin/com/miaotoujunshi/capabilities/android/'
    'AndroidStorageHost.kt',
  ).readAsStringSync();

  test('credentials are encrypted by an Android Keystore AES-GCM key', () {
    expect(source, contains('"AndroidKeyStore"'));
    expect(source, contains('"AES/GCM/NoPadding"'));
    expect(source, contains('KeyGenParameterSpec.Builder'));
    expect(source, contains('setRandomizedEncryptionRequired(true)'));
    expect(source, contains('cipher.updateAAD'));
  });

  test('secret values never enter preferences or logs unencrypted', () {
    final String secretClass = source.split(
      'private class KeystoreSecretStore',
    )[1];
    expect(secretClass, isNot(contains('Log.')));
    expect(secretClass, isNot(contains('putString(key, value)')));
    expect(secretClass, contains('putString(key, envelope)'));
  });
}
