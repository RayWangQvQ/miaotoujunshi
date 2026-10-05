import 'package:miaotou_capabilities/miaotou_capabilities.dart';

import 'storage_native.dart';

final class AndroidSecretStore implements SecretStore {
  AndroidSecretStore(this._native);

  final AndroidStorageNative _native;

  @override
  Future<String?> read(String key) => _native.readSecret(key);

  @override
  Future<void> write(String key, String value) =>
      _native.writeSecret(key, value);

  @override
  Future<void> delete(String key) => _native.deleteSecret(key);

  @override
  Future<Set<String>> keys() => _native.secretKeys();
}
