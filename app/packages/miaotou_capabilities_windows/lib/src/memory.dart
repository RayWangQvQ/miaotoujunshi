import 'dart:io';

import 'package:miaotou_capabilities/miaotou_capabilities.dart';

import 'json_file.dart';

final class WindowsMemoryStore implements MemoryStore {
  WindowsMemoryStore(WindowsJsonFile file) : _file = file;

  factory WindowsMemoryStore.inApplicationData() =>
      WindowsMemoryStore(WindowsJsonFile.inApplicationData('memory.json'));

  factory WindowsMemoryStore.inDirectory(Directory directory) =>
      WindowsMemoryStore(WindowsJsonFile(directory, 'memory.json'));

  final WindowsJsonFile _file;

  static const int maxValueChars = 200;
  static const int maxRows = 200;
  static const int maxOperations = 20;
  static const String policyVersion = '1';

  @override
  Future<MemoryStatus> status() async {
    final Map<String, Object?> data = await _file.read();
    return MemoryStatus(
      consentEnabled: data['consentEnabled'] == true,
      paused: data['paused'] == true,
      atCapacity: _rows(data['records']).length >= maxRows,
    );
  }

  @override
  Future<List<MemoryRecord>> show(String subjectId) async {
    final Map<String, Object?> data = await _file.read();
    if (data['consentEnabled'] != true) {
      return const <MemoryRecord>[];
    }
    return <MemoryRecord>[
      for (final Map<String, Object?> row in _rows(data['records']))
        if (row['subjectId'] == subjectId)
          MemoryRecord(
            subjectId: row['subjectId']! as String,
            field: row['field']! as String,
            value: row['value']! as String,
          ),
    ];
  }

  @override
  Future<void> apply({
    required String subjectId,
    required String field,
    required String value,
  }) async {
    _validate(subjectId, field, value);
    final Map<String, Object?> data = await _file.read();
    if (data['consentEnabled'] != true) {
      throw StateError('长期记忆尚未获得用户同意');
    }
    if (data['paused'] == true) {
      throw StateError('长期记忆当前已暂停');
    }
    final List<Map<String, Object?>> records = _rows(data['records']);
    final int existing = records.indexWhere(
      (Map<String, Object?> row) =>
          row['subjectId'] == subjectId && row['field'] == field,
    );
    if (existing < 0 && records.length >= maxRows) {
      throw StateError('长期记忆已达 $maxRows 条上限，请先清空后再保存');
    }
    final List<Map<String, Object?>> undo = _rows(data['undo'])
      ..add(<String, Object?>{
        'subjectId': subjectId,
        'field': field,
        'before': existing < 0 ? null : records[existing]['value'],
      });
    if (undo.length > maxOperations) {
      undo.removeRange(0, undo.length - maxOperations);
    }
    final Map<String, Object?> row = <String, Object?>{
      'subjectId': subjectId,
      'field': field,
      'value': value,
    };
    existing < 0 ? records.add(row) : records[existing] = row;
    await _file.write(<String, Object?>{
      ...data,
      'policyVersion': policyVersion,
      'records': records,
      'undo': undo,
    });
  }

  @override
  Future<int> undo() async {
    final Map<String, Object?> data = await _file.read();
    final List<Map<String, Object?>> undo = _rows(data['undo']);
    if (undo.isEmpty) {
      return 0;
    }
    final List<Map<String, Object?>> records = _rows(data['records']);
    for (final Map<String, Object?> entry in undo.reversed) {
      final int index = records.indexWhere(
        (Map<String, Object?> row) =>
            row['subjectId'] == entry['subjectId'] &&
            row['field'] == entry['field'],
      );
      if (index < 0) {
        continue;
      }
      if (entry['before'] == null) {
        records.removeAt(index);
      } else {
        records[index] = <String, Object?>{
          'subjectId': entry['subjectId'],
          'field': entry['field'],
          'value': entry['before'],
        };
      }
    }
    await _file.write(<String, Object?>{
      ...data,
      'records': records,
      'undo': const <Object?>[],
    });
    return undo.length;
  }

  Future<void> grantConsent({required bool confirmed}) async {
    if (!confirmed) {
      throw StateError('需要用户明确确认才能启用长期记忆');
    }
    final Map<String, Object?> data = await _file.read();
    await _file.write(<String, Object?>{
      ...data,
      'policyVersion': policyVersion,
      'consentEnabled': true,
      'paused': false,
    });
  }

  Future<void> revokeConsent() async {
    final Map<String, Object?> data = await _file.read();
    await _file.write(<String, Object?>{
      ...data,
      'consentEnabled': false,
      'paused': true,
    });
  }

  Future<void> setPaused({required bool paused}) async {
    final Map<String, Object?> data = await _file.read();
    if (data['consentEnabled'] != true) {
      throw StateError('长期记忆尚未获得用户同意');
    }
    await _file.write(<String, Object?>{...data, 'paused': paused});
  }

  Future<void> clear() => _file.write(<String, Object?>{});

  static void _validate(String subjectId, String field, String value) {
    if (subjectId.trim().isEmpty || field.trim().isEmpty) {
      throw StateError('记忆必须有归属对象和字段名');
    }
    final String trimmed = value.trim();
    if (trimmed.isEmpty || trimmed.length > maxValueChars) {
      throw StateError('记忆值不能为空且不得超过 $maxValueChars 字符');
    }
    if (trimmed.runes.any((int rune) => rune < 32 && rune != 9 && rune != 10)) {
      throw StateError('记忆值包含控制字符');
    }
  }

  static List<Map<String, Object?>> _rows(Object? value) =>
      <Map<String, Object?>>[
        for (final Object? row
            in value is List ? value.cast<Object?>() : const <Object?>[])
          if (row is Map) row.cast<String, Object?>(),
      ];
}
