import 'dart:typed_data';

import 'package:miaotou_capabilities/miaotou_capabilities.dart';

import 'storage_native.dart';

final class AndroidSharedPayload implements SharedPayload {
  AndroidSharedPayload(this._native);

  final AndroidStorageNative _native;

  @override
  Future<Uint8List> read(String repoRelativePath) {
    _validate(repoRelativePath, 'repoRelativePath');
    return _native.readPayload(repoRelativePath);
  }

  @override
  Future<List<String>> list(String repoRelativeDir) async {
    _validate(repoRelativeDir, 'repoRelativeDir');
    final List<String> names = await _native.listPayload(repoRelativeDir);
    return names..sort();
  }

  static void _validate(String key, String argument) {
    final List<String> segments = key.split('/');
    if (key.isEmpty ||
        key.startsWith('/') ||
        key.startsWith(r'\') ||
        segments.contains('..') ||
        segments.any(
          (String segment) => segment.isEmpty || segment.contains(r'\'),
        )) {
      throw ArgumentError.value(
        key,
        argument,
        'must remain inside the packaged payload tree',
      );
    }
  }
}
