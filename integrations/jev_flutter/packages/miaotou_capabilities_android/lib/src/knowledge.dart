import 'package:miaotou_capabilities/miaotou_capabilities.dart';

import 'json_document.dart';
import 'storage_native.dart';

final class AndroidKnowledgeStore implements KnowledgeStore {
  AndroidKnowledgeStore(AndroidStorageNative native)
    : _document = AndroidJsonDocument(native, 'knowledge.json');

  final AndroidJsonDocument _document;

  static const String _notesKey = 'notes';
  static const String _contactsKey = 'contacts';
  static const String _logsKey = 'logs';

  @override
  Future<List<KnowledgeNote>> notes() async => <KnowledgeNote>[
    for (final Map<String, Object?> row in _keyedRows(
      (await _document.read())[_notesKey],
    ))
      KnowledgeNote(
        id: _text(row['id']),
        title: _text(row['title']),
        content: _text(row['content']),
        updatedAt: _time(row['updatedAt']),
        tags: _texts(row['tags']),
        alwaysOn: row['alwaysOn'] == true,
        enabled: row['enabled'] != false,
      ),
  ];

  @override
  Future<void> saveNote(KnowledgeNote note) async {
    final Map<String, Object?> contents = await _document.read();
    final List<Map<String, Object?>> rows = _keyedRows(contents[_notesKey])
      ..removeWhere((Map<String, Object?> row) => row['id'] == note.id)
      ..add(<String, Object?>{
        'id': note.id,
        'title': note.title,
        'content': note.content,
        'updatedAt': note.updatedAt.toUtc().toIso8601String(),
        'tags': note.tags,
        'alwaysOn': note.alwaysOn,
        'enabled': note.enabled,
      });
    await _document.write(<String, Object?>{...contents, _notesKey: rows});
  }

  @override
  Future<void> deleteNote(String id) => _deleteRow(_notesKey, id);

  @override
  Future<List<KnowledgeContact>> contacts() async => <KnowledgeContact>[
    for (final Map<String, Object?> row in _keyedRows(
      (await _document.read())[_contactsKey],
    ))
      KnowledgeContact(
        id: _text(row['id']),
        name: _text(row['name']),
        updatedAt: _time(row['updatedAt']),
        aliases: _texts(row['aliases']),
        packageNames: _texts(row['packageNames']),
        relationship: _text(row['relationship']),
        notes: _text(row['notes']),
        stage: _text(row['stage']),
        goal: _text(row['goal']),
        autoSummary: _text(row['autoSummary']),
      ),
  ];

  @override
  Future<KnowledgeContact?> findContact({
    required String title,
    required String packageName,
  }) async {
    final String wantedTitle = _normalise(title);
    final String wantedPackage = _normalise(packageName);
    if (wantedTitle.isEmpty || wantedPackage.isEmpty) {
      return null;
    }
    for (final KnowledgeContact contact in await contacts()) {
      final bool packageMatches = contact.packageNames
          .map(_normalise)
          .contains(wantedPackage);
      final bool titleMatches = <String>[
        contact.name,
        ...contact.aliases,
      ].map(_normalise).contains(wantedTitle);
      if (packageMatches && titleMatches) {
        return contact;
      }
    }
    return null;
  }

  @override
  Future<void> saveContact(KnowledgeContact contact) async {
    final Map<String, Object?> contents = await _document.read();
    final List<Map<String, Object?>> rows = _keyedRows(contents[_contactsKey])
      ..removeWhere((Map<String, Object?> row) => row['id'] == contact.id)
      ..add(<String, Object?>{
        'id': contact.id,
        'name': contact.name,
        'updatedAt': contact.updatedAt.toUtc().toIso8601String(),
        'aliases': contact.aliases,
        'packageNames': contact.packageNames,
        'relationship': contact.relationship,
        'notes': contact.notes,
        'stage': contact.stage,
        'goal': contact.goal,
        'autoSummary': contact.autoSummary,
      });
    await _document.write(<String, Object?>{...contents, _contactsKey: rows});
  }

  @override
  Future<void> deleteContact(String id) async {
    final Map<String, Object?> contents = await _document.read();
    final List<Map<String, Object?>> rows = _keyedRows(contents[_contactsKey])
      ..removeWhere((Map<String, Object?> row) => row['id'] == id);
    final Map<String, Object?> logs = _map(contents[_logsKey])..remove(id);
    await _document.write(<String, Object?>{
      ...contents,
      _contactsKey: rows,
      _logsKey: logs,
    });
  }

  @override
  Future<void> appendLog(
    String contactId,
    List<KnowledgeLogEntry> entries,
  ) async {
    if (entries.isEmpty) {
      return;
    }
    final Map<String, Object?> contents = await _document.read();
    final Map<String, Object?> logs = _map(contents[_logsKey]);
    final List<Map<String, Object?>> rows = _rows(logs[contactId])
      ..addAll(<Map<String, Object?>>[
        for (final KnowledgeLogEntry entry in entries)
          <String, Object?>{
            'speaker': entry.speaker.name,
            'text': entry.text,
            'timestamp': entry.timestamp.toUtc().toIso8601String(),
            'packageName': entry.packageName,
          },
      ]);
    logs[contactId] = rows;
    await _document.write(<String, Object?>{...contents, _logsKey: logs});
  }

  @override
  Future<List<KnowledgeLogEntry>> recentLog(
    String contactId, {
    required int limit,
  }) async {
    if (limit <= 0) {
      return const <KnowledgeLogEntry>[];
    }
    final List<Map<String, Object?>> rows = _rows(
      _map((await _document.read())[_logsKey])[contactId],
    );
    final int start = rows.length > limit ? rows.length - limit : 0;
    return <KnowledgeLogEntry>[
      for (final Map<String, Object?> row in rows.sublist(start))
        KnowledgeLogEntry(
          speaker: Speaker.values.firstWhere(
            (Speaker speaker) => speaker.name == row['speaker'],
            orElse: () => Speaker.other,
          ),
          text: _text(row['text']),
          timestamp: _time(row['timestamp']),
          packageName: _text(row['packageName']),
        ),
    ];
  }

  @override
  Future<void> clearAll() => _document.write(<String, Object?>{});

  Future<void> _deleteRow(String section, String id) async {
    final Map<String, Object?> contents = await _document.read();
    final List<Map<String, Object?>> rows = _keyedRows(contents[section]);
    final int before = rows.length;
    rows.removeWhere((Map<String, Object?> row) => row['id'] == id);
    if (rows.length != before) {
      await _document.write(<String, Object?>{...contents, section: rows});
    }
  }

  static String _normalise(String value) => value.trim().toLowerCase();
  static String _text(Object? value) => value is String ? value : '';
  static DateTime _time(Object? value) => value is String
      ? DateTime.parse(value).toLocal()
      : DateTime.fromMillisecondsSinceEpoch(0, isUtc: true).toLocal();
  static List<String> _texts(Object? value) => <String>[
    for (final Object? item
        in value is List ? value.cast<Object?>() : const <Object?>[])
      if (item is String) item,
  ];
  static Map<String, Object?> _map(Object? value) =>
      value is Map ? value.cast<String, Object?>() : <String, Object?>{};
  static List<Map<String, Object?>> _rows(Object? value) =>
      <Map<String, Object?>>[
        for (final Object? row
            in value is List ? value.cast<Object?>() : const <Object?>[])
          if (row is Map) row.cast<String, Object?>(),
      ];
  static List<Map<String, Object?>> _keyedRows(Object? value) =>
      _rows(value)
          .where((Map<String, Object?> row) => row['id'] is String)
          .toList();
}
