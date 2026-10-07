import 'dart:typed_data';

import '../storage_native.dart';

final class MemoryAndroidStorageNative implements AndroidStorageNative {
  MemoryAndroidStorageNative({Map<String, Uint8List>? payload})
    : payload = payload ?? <String, Uint8List>{};

  final Map<String, Uint8List> payload;
  final Map<String, String> secrets = <String, String>{};
  final Map<String, String> documents = <String, String>{};

  @override
  Future<Uint8List?> readPayload(String repoRelativePath) async {
    final Uint8List? bytes = payload[repoRelativePath];
    return bytes == null ? null : Uint8List.fromList(bytes);
  }

  @override
  Future<List<String>?> listPayload(String repoRelativeDir) async {
    final String prefix = '$repoRelativeDir/';
    final List<String> files = <String>[
      for (final String key in payload.keys)
        if (key.startsWith(prefix) &&
            !key.substring(prefix.length).contains('/'))
          key.substring(prefix.length),
    ];
    return files.isEmpty ? null : (files..sort());
  }

  @override
  Future<String?> readSecret(String key) async => secrets[key];

  @override
  Future<void> writeSecret(String key, String value) async {
    secrets[key] = value;
  }

  @override
  Future<void> deleteSecret(String key) async {
    secrets.remove(key);
  }

  @override
  Future<Set<String>> secretKeys() async => secrets.keys.toSet();

  @override
  Future<String?> readDocument(String name) async => documents[name];

  @override
  Future<void> writeDocument(String name, String contents) async {
    documents[name] = contents;
  }
}
