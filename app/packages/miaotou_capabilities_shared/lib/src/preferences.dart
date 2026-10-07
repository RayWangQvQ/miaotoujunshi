import 'package:miaotou_capabilities/miaotou_capabilities.dart';

import 'document.dart';

/// Small remembered values, in the one form all three ports use.
///
/// A JSON object under the platform's document directory, one document, keyed by
/// whatever the caller passes.
///
/// ## No credential ever comes here
///
/// This is the store the contract calls configuration — routes, models, the
/// relationship description, the conversation whitelist, the panel's remembered
/// position — and the document is a plain, readable, *unencrypted* JSON file
/// inside the app's own sandbox. Putting an API key here would mean one `cat` away
/// from leaking it, and `PRIVACY.md` promises the keys are in the system store.
/// Credentials go to `SecretStore`; the type system cannot stop that, which is why
/// the tests assert the two stores write to different documents and that the
/// system store is the only thing that ever holds a secret-shaped value.
///
/// Android used to answer this capability out of `SharedPreferences` instead, with
/// the record shape delegated to Kotlin. It now uses this class like the other two,
/// which is what let the platform channel lose four members; ADR-0009's
/// Consequences record the move and the licence for it (ADR-0010 decision 3 — the
/// product has never been released, so there is no installed data to honour).
///
/// ## Why types round-trip rather than being coerced
///
/// `getString` on a key that was set as a bool returns null; it does not return
/// `"true"`. The alternative is a store that answers a question nobody asked, and
/// a route silently becoming the string `"false"` is the sort of thing found in a
/// log rather than in a test. The tag written alongside each value is what makes
/// the round trip exact, and it is why the document is a map of records rather
/// than a map of bare JSON values.
///
/// The tag is also where the line about damaged data sits, and it is drawn one
/// notch tighter than the two desktop ports had it. A key that holds a *different*
/// type is not damaged — it is a different question, and null is its answer. A key
/// whose tag says `string` and whose value is a number is damaged: there is no
/// answer to that which is not a guess, so it is reported rather than coerced. The
/// two desktop ports disagreed here (one cast and threw a bare `TypeError`, one
/// answered null) and neither answer named the key.
///
/// ## Why the list is stored sorted
///
/// The contract stores a string list **as a set**, so the order is not part of the
/// value: a caller that wrote `['a', 'b']` and one that wrote `['b', 'a']` have
/// stored the same thing and must read back the same thing. Sorting on the way in
/// makes that true of the document as well as of the return value — without it the
/// order would be whatever the caller happened to type, two equivalent writes would
/// produce two different files, and a diff of the settings would show a change that
/// never happened.
///
/// Reading does **not** sort. Android used to, which meant a hand-edited file read
/// back in a different order from the same file on the other two ports; with the
/// write already canonical there is nothing for a second normalisation to fix, and
/// a rule that only some reads obey is a rule nobody can rely on.
final class PreferenceLedger implements Preferences {
  PreferenceLedger(TextDocuments documents)
    : _file = JsonDocument(documents, fileName);

  /// The document this store owns, inside whatever directory the platform uses.
  static const String fileName = 'preferences.json';

  static const String _string = 'string';
  static const String _bool = 'bool';
  static const String _int = 'int';
  static const String _stringList = 'stringList';

  final JsonDocument _file;

  @override
  Future<String?> getString(String key) => _typed<String>(key, _string);

  @override
  Future<bool?> getBool(String key) => _typed<bool>(key, _bool);

  @override
  Future<int?> getInt(String key) => _typed<int>(key, _int);

  @override
  Future<List<String>?> getStringList(String key) async {
    final List<Object?>? value = await _typed<List<Object?>>(key, _stringList);
    if (value == null) {
      return null;
    }
    final List<String> items = <String>[];
    for (final Object? item in value) {
      if (item is! String) {
        throw StateError(
          '$key is stored as a string list and holds a ${item.runtimeType}',
        );
      }
      items.add(item);
    }
    return items;
  }

  @override
  Future<void> setString(String key, String value) => _put(key, _string, value);

  @override
  Future<void> setBool(String key, bool value) => _put(key, _bool, value);

  @override
  Future<void> setInt(String key, int value) => _put(key, _int, value);

  @override
  Future<void> setStringList(String key, List<String> value) =>
      _put(key, _stringList, value.toSet().toList()..sort());

  @override
  Future<void> remove(String key) async {
    final Map<String, Object?> contents = await _file.read();
    if (!contents.containsKey(key)) {
      // Removing a key that is not set is not an error, and rewriting the document
      // for it would touch the settings on a no-op. The test is `containsKey`
      // rather than "was anything removed": a key explicitly holding JSON null
      // still has to go, or `remove` would report success and leave it behind.
      return;
    }
    contents.remove(key);
    await _file.write(contents);
  }

  @override
  Future<Set<String>> keys() async => (await _file.read()).keys.toSet();

  /// The value for [key], or null when it is absent **or held as another type**.
  ///
  /// Throws when the record's tag and its value disagree; see the class comment.
  Future<T?> _typed<T>(String key, String type) async {
    final Object? record = (await _file.read())[key];
    if (record is! Map) {
      return null;
    }
    final Map<String, Object?> held = record.cast<String, Object?>();
    if (held['type'] != type) {
      return null;
    }
    final Object? value = held['value'];
    if (value is! T) {
      throw StateError(
        '$key is stored as a $type and holds a ${value.runtimeType}',
      );
    }
    return value;
  }

  Future<void> _put(String key, String type, Object? value) async {
    final Map<String, Object?> contents = await _file.read();
    contents[key] = <String, Object?>{'type': type, 'value': value};
    await _file.write(contents);
  }
}
