import 'package:miaotou_capabilities/miaotou_capabilities.dart';

import 'storage_native.dart';

final class AndroidPreferences implements Preferences {
  AndroidPreferences(this._native);

  final AndroidStorageNative _native;

  @override
  Future<String?> getString(String key) => _get<String>(key, 'string');

  @override
  Future<bool?> getBool(String key) => _get<bool>(key, 'bool');

  @override
  Future<int?> getInt(String key) => _get<int>(key, 'int');

  @override
  Future<List<String>?> getStringList(String key) async {
    final Object? value = await _native.readPreference(key, 'stringList');
    if (value is! List) {
      return null;
    }
    return List<String>.from(value)..sort();
  }

  @override
  Future<void> setString(String key, String value) =>
      _native.writePreference(key, 'string', value);

  @override
  Future<void> setBool(String key, bool value) =>
      _native.writePreference(key, 'bool', value);

  @override
  Future<void> setInt(String key, int value) =>
      _native.writePreference(key, 'int', value);

  @override
  Future<void> setStringList(String key, List<String> value) => _native
      .writePreference(key, 'stringList', value.toSet().toList()..sort());

  @override
  Future<void> remove(String key) => _native.removePreference(key);

  @override
  Future<Set<String>> keys() => _native.preferenceKeys();

  Future<T?> _get<T>(String key, String type) async {
    final Object? value = await _native.readPreference(key, type);
    return value is T ? value : null;
  }
}
