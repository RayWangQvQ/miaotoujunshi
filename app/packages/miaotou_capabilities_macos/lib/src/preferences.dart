import 'package:miaotou_capabilities/miaotou_capabilities.dart';

import 'container_file.dart';
import 'native.dart';

/// macOS's answer for small remembered values.
///
/// Owned by #15. A JSON object under the application container, one file, keyed
/// by whatever the caller passes.
///
/// ## No credential ever comes here
///
/// This is the store the contract calls configuration — routes, models, the
/// relationship description, the conversation whitelist, the panel's remembered
/// position — and the container file is a plain, readable, *unencrypted* JSON
/// document inside the app's own sandbox. Putting an API key here would mean one
/// `cat` away from leaking it, and `PRIVACY.md` promises the keys are in the
/// system Keychain. Credentials go to `MacosSecretStore`; the type system cannot
/// stop that, which is why the tests assert the two stores write to different
/// files and that the keychain is the only thing that ever holds a
/// secret-shaped value.
///
/// ## Why types round-trip rather than being coerced
///
/// `getString` on a key that was set as a bool returns null; it does not return
/// `"true"`. The alternative is a store that answers a question nobody asked, and
/// a route silently becoming the string `"false"` is the sort of thing found in a
/// log rather than in a test. The tag written alongside each value is what makes
/// the round trip exact, and it is why the file is a map of records rather than a
/// map of bare JSON values.
final class MacosPreferences implements Preferences {
  /// Over a container file the caller names, for a test that wants to watch the
  /// file itself.
  MacosPreferences(ContainerFile file) : _file = file;

  /// Over this port's own preferences file in the application container.
  factory MacosPreferences.inContainer(MacosNative native) =>
      MacosPreferences(ContainerFile(native, 'preferences.json'));

  final ContainerFile _file;

  static const String _string = 'string';
  static const String _bool = 'bool';
  static const String _int = 'int';
  static const String _stringList = 'stringList';

  @override
  Future<String?> getString(String key) async {
    final Map<String, Object?>? record = await _typed(key, _string);
    return record == null ? null : record['value']! as String;
  }

  @override
  Future<bool?> getBool(String key) async {
    final Map<String, Object?>? record = await _typed(key, _bool);
    return record == null ? null : record['value']! as bool;
  }

  @override
  Future<int?> getInt(String key) async {
    final Map<String, Object?>? record = await _typed(key, _int);
    return record == null ? null : record['value']! as int;
  }

  @override
  Future<List<String>?> getStringList(String key) async {
    final Map<String, Object?>? record = await _typed(key, _stringList);
    if (record == null) {
      return null;
    }
    return List<String>.from(record['value']! as List<Object?>);
  }

  @override
  Future<void> setString(String key, String value) => _put(key, _string, value);

  @override
  Future<void> setBool(String key, bool value) => _put(key, _bool, value);

  @override
  Future<void> setInt(String key, int value) => _put(key, _int, value);

  /// Stores the list **as a set**, which is the contract's own word.
  ///
  /// Order is not part of the value, so a caller that wrote `['a', 'b']` and one
  /// that wrote `['b', 'a']` have stored the same thing and must read back the
  /// same thing. Sorting on the way in makes that true of the file as well as of
  /// the return value: without it the order would be whatever the caller happened
  /// to type, two equivalent writes would produce two different files, and a diff
  /// of the settings would show a change that never happened.
  @override
  Future<void> setStringList(String key, List<String> value) =>
      _put(key, _stringList, value.toSet().toList()..sort());

  @override
  Future<void> remove(String key) async {
    final Map<String, Object?> contents = await _file.read();
    if (!contents.containsKey(key)) {
      // Removing a key that is not set is not an error, and rewriting the file
      // for it would touch the settings document on a no-op.
      return;
    }
    contents.remove(key);
    await _file.write(contents);
  }

  @override
  Future<Set<String>> keys() async => (await _file.read()).keys.toSet();

  /// The record for [key], or null when it is absent **or of another type**.
  Future<Map<String, Object?>?> _typed(String key, String type) async {
    final Object? record = (await _file.read())[key];
    if (record is! Map) {
      return null;
    }
    final Map<String, Object?> typed = record.cast<String, Object?>();
    return typed['type'] == type ? typed : null;
  }

  Future<void> _put(String key, String type, Object? value) async {
    final Map<String, Object?> contents = await _file.read();
    contents[key] = <String, Object?>{'type': type, 'value': value};
    await _file.write(contents);
  }
}
