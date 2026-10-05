import 'package:flutter/services.dart';

/// Device-only storage operations behind one Android method channel.
///
/// AssetManager, SharedPreferences, Android Keystore and app-private files have
/// no Dart API. Everything else -- path validation, JSON formats and memory
/// policy -- stays above this seam where a unit test can exercise it.
abstract interface class AndroidStorageNative {
  Future<Uint8List> readPayload(String repoRelativePath);

  Future<List<String>> listPayload(String repoRelativeDir);

  Future<Object?> readPreference(String key, String type);

  Future<void> writePreference(String key, String type, Object value);

  Future<void> removePreference(String key);

  Future<Set<String>> preferenceKeys();

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
  Future<Uint8List> readPayload(String repoRelativePath) async {
    final Uint8List? bytes = await _channel.invokeMethod<Uint8List>(
      'payload.read',
      <String, Object?>{'path': repoRelativePath},
    );
    if (bytes == null) {
      throw StateError(
        'Android returned no bytes for $repoRelativePath; the packaged payload '
        'is incomplete',
      );
    }
    return bytes;
  }

  @override
  Future<List<String>> listPayload(String repoRelativeDir) async {
    final List<String>? names = await _channel.invokeListMethod<String>(
      'payload.list',
      <String, Object?>{'path': repoRelativeDir},
    );
    if (names == null) {
      throw StateError(
        'Android returned no listing for $repoRelativeDir; the packaged payload '
        'is incomplete',
      );
    }
    return names;
  }

  @override
  Future<Object?> readPreference(String key, String type) =>
      _channel.invokeMethod<Object?>('preferences.read', <String, Object?>{
        'key': key,
        'type': type,
      });

  @override
  Future<void> writePreference(String key, String type, Object value) =>
      _channel.invokeMethod<void>('preferences.write', <String, Object?>{
        'key': key,
        'type': type,
        'value': value,
      });

  @override
  Future<void> removePreference(String key) => _channel.invokeMethod<void>(
    'preferences.remove',
    <String, Object?>{'key': key},
  );

  @override
  Future<Set<String>> preferenceKeys() async => Set<String>.from(
    await _channel.invokeListMethod<String>('preferences.keys') ??
        const <String>[],
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
