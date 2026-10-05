/// Small values the application remembers between runs.
///
/// This is configuration — routes, models, the relationship description, the
/// conversation whitelist, the panel's remembered position — and **never a
/// credential**. Credentials live in `SecretStore`, which the three platforms
/// back with the operating system's own store; putting a key here would land it
/// in a plain file on at least one of the three.
///
/// There is no `changed` stream. Nothing in the three ports reacts to a
/// preference changing; a settings page writes and then rebuilds, and inventing
/// a subscription would be inventing a requirement.
abstract interface class Preferences {
  Future<String?> getString(String key);

  Future<bool?> getBool(String key);

  Future<int?> getInt(String key);

  /// Stored as a set, so the order is not part of the value. Android's
  /// `SharedPreferences` has no ordered collection and neither do the two
  /// desktop stores the ports already use.
  Future<List<String>?> getStringList(String key);

  Future<void> setString(String key, String value);

  Future<void> setBool(String key, bool value);

  Future<void> setInt(String key, int value);

  Future<void> setStringList(String key, List<String> value);

  /// Removes one key. Removing a key that is not set is not an error.
  Future<void> remove(String key);

  /// Every key this store currently holds, so a caller can wipe the store
  /// without knowing what is in it.
  Future<Set<String>> keys();
}
