import 'dart:io';

import 'package:miaotou_capabilities/miaotou_capabilities.dart';

import 'json_file.dart';

final class WindowsPreferences implements Preferences {
  WindowsPreferences(WindowsJsonFile file) : _file = file;

  factory WindowsPreferences.inApplicationData() =>
      WindowsPreferences(WindowsJsonFile.inApplicationData('preferences.json'));

  factory WindowsPreferences.inDirectory(Directory directory) =>
      WindowsPreferences(WindowsJsonFile(directory, 'preferences.json'));

  final WindowsJsonFile _file;

  @override
  Future<String?> getString(String key) => _get<String>(key, 'string');

  @override
  Future<bool?> getBool(String key) => _get<bool>(key, 'bool');

  @override
  Future<int?> getInt(String key) => _get<int>(key, 'int');

  @override
  Future<List<String>?> getStringList(String key) async {
    final Object? value = await _value(key, 'stringList');
    return value is List ? List<String>.from(value) : null;
  }

  @override
  Future<void> setString(String key, String value) =>
      _put(key, 'string', value);

  @override
  Future<void> setBool(String key, bool value) => _put(key, 'bool', value);

  @override
  Future<void> setInt(String key, int value) => _put(key, 'int', value);

  @override
  Future<void> setStringList(String key, List<String> value) =>
      _put(key, 'stringList', value.toSet().toList()..sort());

  @override
  Future<void> remove(String key) async {
    final Map<String, Object?> contents = await _file.read();
    if (contents.remove(key) != null) {
      await _file.write(contents);
    }
  }

  @override
  Future<Set<String>> keys() async => (await _file.read()).keys.toSet();

  Future<T?> _get<T>(String key, String type) async {
    final Object? value = await _value(key, type);
    return value is T ? value : null;
  }

  Future<Object?> _value(String key, String type) async {
    final Object? raw = (await _file.read())[key];
    if (raw is! Map) {
      return null;
    }
    final Map<String, Object?> record = raw.cast<String, Object?>();
    return record['type'] == type ? record['value'] : null;
  }

  Future<void> _put(String key, String type, Object value) async {
    final Map<String, Object?> contents = await _file.read();
    contents[key] = <String, Object?>{'type': type, 'value': value};
    await _file.write(contents);
  }
}
