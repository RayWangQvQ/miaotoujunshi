import 'package:miaotou_capabilities/miaotou_capabilities.dart';

import 'native.dart';

/// macOS's answer for credentials.
///
/// Owned by #15. The Keychain, through `Security.framework`.
///
/// ## This is the only storage member with no pure-Dart half
///
/// `SecItem*` is C API. The frozen Python port reached it by running
/// `/usr/bin/security` as a subprocess with the secret on stdin (the port is
/// preserved by `archive/jev-mac-python-final`), and that is not available here:
/// the app is sandboxed (`apps/miaotou_app/macos/Runner/Release.entitlements` sets
/// `com.apple.security.app-sandbox`), `security` is not on a sandboxed app's
/// allowed surface, and a subprocess could not be given the keychain access the
/// framework grants in-process anyway. So the four members below are thin
/// forwarders and the work is native — which is exactly the split #14's header
/// describes, applied to storage.
///
/// ## An honest statement about which keychain this is
///
/// **The data protection keychain and the login keychain the old Python port
/// wrote to are not the same keychain, and this port cannot read what that port
/// wrote.** A user who saved a DeepSeek or Jev key in the previous build will
/// find the field empty here and has to paste it once more.
///
/// The reason is `kSecUseDataProtectionKeychain: true`, set on every call in
/// `KeychainStore.swift`. Without it a macOS app reads the *file-based* login
/// keychain, and every access from an unsandboxed or differently-identified
/// binary raises an authorisation dialog; with it, the item lives in the
/// data protection keychain, which is per-application and never prompts. That is
/// the right trade for a sandboxed app, and the cost of it is the migration above.
///
/// The tempting fix is a `keychain-access-groups` entitlement, which would let
/// the app name a shared group and find the old items. It is not added: an
/// access group has to be provisioned against a developer **team**, and this
/// repository has no team to provision. A build that asked for one would fail to
/// sign on any machine but the author's, which is a worse outcome than asking the
/// user to paste a key once. If a team identifier ever exists, the item's
/// `kSecAttrAccessGroup` is the one line to add and the migration becomes a read.
///
/// `keys()` returns names only, and that is enforced on the native side by
/// listing attributes without asking for data — see the Swift.
final class MacosSecretStore implements SecretStore {
  const MacosSecretStore(this._native);

  final MacosNative _native;

  @override
  Future<String?> read(String key) => _native.keychainRead(key);

  @override
  Future<void> write(String key, String value) =>
      _native.keychainWrite(key, value);

  @override
  Future<void> delete(String key) => _native.keychainDelete(key);

  /// The names of the stored keys, never their values.
  ///
  /// A settings screen asks this to say which of the three providers is
  /// configured. It must be able to do that without being able to obtain the key
  /// it is describing, so the native side lists `kSecAttrAccount` and never asks
  /// for `kSecReturnData` — see the guard in `secrets_test.dart`, which reads the
  /// Swift and fails if a data attribute is ever requested on this path.
  @override
  Future<Set<String>> keys() async => (await _native.keychainKeys()).toSet();
}
