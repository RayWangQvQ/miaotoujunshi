import 'package:flutter/services.dart';

/// Device-only storage operations behind one Android method channel.
///
/// AssetManager, the Android Keystore and app-private files have no Dart API.
/// Everything else -- path validation, JSON formats, the record shapes and memory
/// policy -- stays above this seam where a unit test can exercise it.
///
/// **Preferences used to be here and are not any more.** Four members
/// (`preferences.read` / `write` / `remove` / `keys`) forwarded this app's
/// settings to `SharedPreferences` in Kotlin, which is to say the *record shape*
/// of a settings document was decided on the far side of a language boundary and
/// twice: once here and once in the two desktop ports. The stores are one shared
/// module now, so the same capability is answered over [readDocument] and
/// [writeDocument] like the knowledge base and the memory store, and the four
/// Kotlin members are gone with them. ADR-0009's Consequences record the move.
abstract interface class AndroidStorageNative {
  /// The bytes at a packaged payload path, or null when the package has no file
  /// there.
  ///
  /// Null rather than a refusal because on this port the payload is inside the APK:
  /// an absent key *is* an incomplete package, and the caller above this seam is
  /// the one that gets to say so. See `PayloadTree` in
  /// `miaotou_capabilities_shared`.
  Future<Uint8List?> readPayload(String repoRelativePath);

  /// The file names directly inside a packaged payload directory, or null when
  /// there is none.
  Future<List<String>?> listPayload(String repoRelativeDir);

  Future<String?> readSecret(String key);

  Future<void> writeSecret(String key, String value);

  Future<void> deleteSecret(String key);

  Future<Set<String>> secretKeys();

  Future<String?> readDocument(String name);

  Future<void> writeDocument(String name, String contents);
}

final class MethodChannelAndroidStorageNative implements AndroidStorageNative {
  MethodChannelAndroidStorageNative({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(channelName);

  static const String channelName = 'miaotoujunshi/android/storage';

  final MethodChannel _channel;

  @override
  Future<Uint8List?> readPayload(String repoRelativePath) =>
      _channel.invokeMethod<Uint8List>(
        'payload.read',
        <String, Object?>{'path': repoRelativePath},
      );

  @override
  Future<List<String>?> listPayload(String repoRelativeDir) =>
      _channel.invokeListMethod<String>(
        'payload.list',
        <String, Object?>{'path': repoRelativeDir},
      );

  @override
  Future<String?> readSecret(String key) => _channel.invokeMethod<String>(
    'secret.read',
    <String, Object?>{'key': key},
  );

  @override
  Future<void> writeSecret(String key, String value) =>
      _channel.invokeMethod<void>('secret.write', <String, Object?>{
        'key': key,
        'value': value,
      });

  @override
  Future<void> deleteSecret(String key) => _channel.invokeMethod<void>(
    'secret.delete',
    <String, Object?>{'key': key},
  );

  @override
  Future<Set<String>> secretKeys() async => Set<String>.from(
    await _channel.invokeListMethod<String>('secret.keys') ?? const <String>[],
  );

  @override
  Future<String?> readDocument(String name) => _channel.invokeMethod<String>(
    'document.read',
    <String, Object?>{'name': name},
  );

  @override
  Future<void> writeDocument(String name, String contents) =>
      _channel.invokeMethod<void>('document.write', <String, Object?>{
        'name': name,
        'contents': contents,
      });
}
