/// Credentials, in the operating system's own store.
///
/// macOS uses the Keychain, Windows the Credential Manager, Android a
/// Keystore-backed private store. Values are never logged, never written to a
/// plain file and never leave the device — the ports already hold to that, and
/// this interface is where it becomes a property of the product rather than a
/// habit of three implementations.
///
/// As with `Preferences`, a key that is not set reads back as null rather than
/// as an error.
abstract interface class SecretStore {
  /// The stored secret, or null when the key is not set.
  Future<String?> read(String key);

  Future<void> write(String key, String value);

  /// Removes one key. Removing a key that is not set is not an error.
  Future<void> delete(String key);

  /// The names of the keys this store holds — **names only, never values** —
  /// so a settings screen can say which routes are configured without reading
  /// anything secret.
  Future<Set<String>> keys();
}
