import 'dart:convert';

import 'storage_native.dart';

final class AndroidJsonDocument {
  AndroidJsonDocument(this._native, this.name);

  final AndroidStorageNative _native;
  final String name;

  Future<Map<String, Object?>> read() async {
    final String? text = await _native.readDocument(name);
    if (text == null || text.trim().isEmpty) {
      return <String, Object?>{};
    }
    final Object? decoded = jsonDecode(text);
    if (decoded is! Map) {
      throw FormatException(
        '$name does not hold a JSON object; refusing to hide data loss by '
        'treating it as an empty store',
      );
    }
    return decoded.cast<String, Object?>();
  }

  Future<void> write(Map<String, Object?> contents) => _native.writeDocument(
    name,
    const JsonEncoder.withIndent('  ').convert(contents),
  );
}
