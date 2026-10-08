import 'package:miaotou_capabilities/miaotou_capabilities.dart';

import 'document.dart';

/// The knowledge base, in the one form all three ports use.
///
/// The union baseline (ADR-0007 decision 4) means every port keeps a capability
/// only Android had: the knowledge base, the contacts and the chat history.
///
/// ## The matching rule, and why it is the whole point
///
/// `findContact` matches on a **conversation title plus a package name**, and the
/// contact carries a list of both. The aliases are what make a contact portable:
/// the same person is a different window title in WeChat, in a browser and in a
/// phone mirror, and a contact that matched only one of them would be a contact
/// per application — which is the divergence the union baseline exists to remove.
///
/// So the rule is: the title matches the contact's name **or any of its aliases**,
/// **and** the package is one the contact has been seen in. Both halves. A title
/// alone would match a stranger with the same nickname in another app; a package
/// alone would match every conversation in the app. The pair is the identity.
///
/// Matching is case-insensitive and whitespace-trimmed, because a window title
/// arrives with whatever padding the chat application put on it and an alias the
/// user typed by hand will not match the title byte for byte. It is *not* fuzzy:
/// a partial match would merge two different people, and a wrong merge in a store
/// that holds someone's relationship stage is worse than a missed one.
///
/// ## The document's shape
///
/// Three keys: `notes` and `contacts` are lists of id-keyed rows, and `logs` is a
/// map from contact id to that contact's lines. Nothing else is read or written,
/// and an unknown key in the file rides along untouched — a forward-compatibility
/// courtesy the three ports shared before this module did.
///
/// ## What a damaged row does, and where the line is
///
/// **A row's identity must be sound.** A `notes` or `contacts` entry with no
/// `id` string refuses the document. macOS used to drop such a row and said so —
/// "a damaged file loses the damaged rows rather than inventing an identity for
/// them" — but dropping is not what happened: `saveNote` rebuilds the section from
/// the rows it decoded, so the dropped row disappeared from the file on the next
/// save, without a word. The same argument that makes a document which is not an
/// object a refusal ([JsonDocument]) makes a row that cannot be identified one.
///
/// **An optional field still reads back as empty.** Every text field of a note or
/// a contact is optional in the contract, and `''` is the contract's own spelling
/// of "not set", so a missing or mistyped `title` is `''` rather than a refusal.
/// The difference is not arbitrary: `id` has no default the store could invent,
/// and the other fields have exactly one.
final class KnowledgeLedger implements KnowledgeStore {
  KnowledgeLedger(TextDocuments documents)
    : _file = JsonDocument(documents, fileName);

  /// The document this store owns, inside whatever directory the platform uses.
  static const String fileName = 'knowledge.json';

  static const String _notesKey = 'notes';
  static const String _contactsKey = 'contacts';
  static const String _logsKey = 'logs';
  static const String _appNamesKey = 'appNames';

  final JsonDocument _file;

  @override
  Future<List<KnowledgeNote>> notes() async =>
      _notesFrom((await _file.read())[_notesKey]);

  @override
  Future<void> saveNote(KnowledgeNote note) async {
    final Map<String, Object?> contents = await _file.read();
    final List<Map<String, Object?>> all = _rows(contents[_notesKey], _notesKey);
    all.removeWhere((Map<String, Object?> row) => row['id'] == note.id);
    all.add(_encodeNote(note));
    await _file.write(<String, Object?>{...contents, _notesKey: all});
  }

  @override
  Future<void> deleteNote(String id) async {
    final Map<String, Object?> contents = await _file.read();
    final List<Map<String, Object?>> all = _rows(contents[_notesKey], _notesKey);
    if (!_removeById(all, id)) {
      return;
    }
    await _file.write(<String, Object?>{...contents, _notesKey: all});
  }

  @override
  Future<List<KnowledgeContact>> contacts() async =>
      _contactsFrom((await _file.read())[_contactsKey]);

  @override
  Future<KnowledgeContact?> findContact({
    required String title,
    required String packageName,
  }) async {
    final String wanted = _normalise(title);
    if (wanted.isEmpty) {
      // A window with no title is a window that has not reported itself yet.
      // Matching the empty string against a contact's empty name would attach a
      // conversation to an arbitrary record.
      return null;
    }
    final String wantedPackage = _normalise(packageName);
    if (wantedPackage.isEmpty) {
      // The mirror of the empty-title guard above, and for the mirror reason: the
      // two halves are the identity, so a caller that cannot name the application
      // has not named a conversation. Returning null here rather than matching on
      // the title alone is what keeps the rule this file's header states — "a
      // title alone would match a stranger with the same nickname in another
      // app" — true of the empty package as well as of a wrong one.
      //
      // It is a guard rather than an `isNotEmpty` test inside the loop because
      // "no package given" and "a package the contact has not been seen in" are
      // the same answer here, and both must be null. A loop that skipped the
      // package check for an empty string would answer a question nobody asked
      // with a contact the caller did not identify.
      return null;
    }
    for (final KnowledgeContact contact in await contacts()) {
      if (!contact.packageNames.map(_normalise).contains(wantedPackage)) {
        continue;
      }
      final bool titleMatches = <String>[
        contact.name,
        ...contact.aliases,
      ].map(_normalise).contains(wanted);
      if (titleMatches) {
        return contact;
      }
    }
    return null;
  }

  @override
  Future<void> saveContact(KnowledgeContact contact) async {
    final Map<String, Object?> contents = await _file.read();
    final List<Map<String, Object?>> all = _rows(contents[_contactsKey], _contactsKey);
    all.removeWhere((Map<String, Object?> row) => row['id'] == contact.id);
    all.add(_encodeContact(contact));
    await _file.write(<String, Object?>{...contents, _contactsKey: all});
  }

  /// Deletes the contact and its history, and writes nothing if there was neither.
  ///
  /// The early return is not an optimisation. `deleteNote` — and through it this
  /// shape of delete — is reachable from a swipe gesture, and a rewrite on every
  /// empty swipe would make the document's timestamp mean nothing. The `logs` key
  /// is written only when there was history to remove, so a delete that took no
  /// history does not materialise an empty object into a file that never had one.
  @override
  Future<void> deleteContact(String id) async {
    final Map<String, Object?> contents = await _file.read();
    final List<Map<String, Object?>> all = _rows(contents[_contactsKey], _contactsKey);
    if (!_removeById(all, id)) {
      return;
    }
    final Map<String, Object?> logs = _map(contents[_logsKey]);
    final bool hadLog = logs.remove(id) != null;
    await _file.write(<String, Object?>{
      ...contents,
      _contactsKey: all,
      // The history goes with the person. Leaving a deleted contact's lines
      // behind would mean the one action a user takes to remove someone does not
      // remove what was said to them, and the store's whole promise is that one
      // action empties it.
      if (hadLog) _logsKey: logs,
    });
  }

  @override
  Future<void> appendLog(
    String contactId,
    List<KnowledgeLogEntry> entries,
  ) async {
    if (entries.isEmpty) {
      // Appending nothing must not rewrite the document: `appendLog` is called
      // after every capture, and a no-op that touched it would make its timestamp
      // mean nothing.
      return;
    }
    final Map<String, Object?> contents = await _file.read();
    final Map<String, Object?> logs = _map(contents[_logsKey]);
    final List<Map<String, Object?>> existing = _anyRows(logs[contactId]);
    await _file.write(<String, Object?>{
      ...contents,
      _logsKey: <String, Object?>{
        ...logs,
        contactId: <Map<String, Object?>>[
          ...existing,
          for (final KnowledgeLogEntry entry in entries) _encodeEntry(entry),
        ],
      },
    });
  }

  @override
  Future<List<KnowledgeLogEntry>> recentLog(
    String contactId, {
    required int limit,
  }) async {
    if (limit <= 0) {
      // Not an error, and not the whole log: a caller asking for zero lines wants
      // none, and handing back everything would make a limit a suggestion.
      return const <KnowledgeLogEntry>[];
    }
    final List<Map<String, Object?>> all = _anyRows(
      _map((await _file.read())[_logsKey])[contactId],
    );
    final int from = all.length > limit ? all.length - limit : 0;
    // The most recent `limit`, still oldest first: the contract asks for the
    // lines in the order they were said, and a reversed window would render a
    // conversation backwards.
    return <KnowledgeLogEntry>[
      for (final Map<String, Object?> row in all.sublist(from)) _decodeEntry(row),
    ];
  }

  @override
  Future<void> clearAll() => _file.write(<String, Object?>{});

  @override
  Future<void> saveAppName(String key, String displayName) async {
    final Map<String, Object?> contents = await _file.read();
    final Map<String, Object?> appNames = _map(contents[_appNamesKey]);
    await _file.write(<String, Object?>{
      ...contents,
      _appNamesKey: <String, Object?>{
        ...appNames,
        key: displayName,
      },
    });
  }

  @override
  Future<String?> appNameFor(String key) async {
    final Map<String, Object?> appNames = _map(
      (await _file.read())[_appNamesKey],
    );
    final Object? value = appNames[key];
    return value is String ? value : null;
  }

  static String _normalise(String value) => value.trim().toLowerCase();

  /// Removes every row with this id, reporting whether there was one.
  ///
  /// The callers use the answer to avoid a write for a delete of something that
  /// was never there. It is written by hand rather than with `removeWhere` because
  /// that returns `void`.
  static bool _removeById(List<Map<String, Object?>> rows, String id) {
    final int before = rows.length;
    rows.removeWhere((Map<String, Object?> row) => row['id'] == id);
    return rows.length != before;
  }

  // -- encoding ------------------------------------------------------------
  // Explicit maps rather than `toJson`: the value types in the contract are
  // final classes with no serialisation of their own, and a hand-written pair is
  // what lets a field be renamed in one place instead of two.

  static Map<String, Object?> _encodeNote(KnowledgeNote note) =>
      <String, Object?>{
        'id': note.id,
        'title': note.title,
        'content': note.content,
        'updatedAt': note.updatedAt.toUtc().toIso8601String(),
        'tags': note.tags,
        'alwaysOn': note.alwaysOn,
        'enabled': note.enabled,
      };

  static Map<String, Object?> _encodeContact(KnowledgeContact contact) =>
      <String, Object?>{
        'id': contact.id,
        'name': contact.name,
        'updatedAt': contact.updatedAt.toUtc().toIso8601String(),
        'aliases': contact.aliases,
        'packageNames': contact.packageNames,
        'packageAppNames': contact.packageAppNames,
        'relationship': contact.relationship,
        'notes': contact.notes,
        'stage': contact.stage,
        'goal': contact.goal,
        'autoSummary': contact.autoSummary,
      };

  static Map<String, Object?> _encodeEntry(KnowledgeLogEntry entry) =>
      <String, Object?>{
        'speaker': entry.speaker.name,
        'text': entry.text,
        'timestamp': entry.timestamp.toUtc().toIso8601String(),
        'occurredAt': entry.occurredAt?.toUtc().toIso8601String(),
        'packageName': entry.packageName,
      };

  // -- decoding ------------------------------------------------------------

  static KnowledgeNote _decodeNote(Map<String, Object?> row) => KnowledgeNote(
    id: _text(row['id']),
    title: _text(row['title']),
    content: _text(row['content']),
    updatedAt: _time(row['updatedAt']),
    tags: _texts(row['tags']),
    alwaysOn: row['alwaysOn'] == true,
    enabled: row['enabled'] != false,
  );

  static KnowledgeContact _decodeContact(Map<String, Object?> row) =>
      KnowledgeContact(
        id: _text(row['id']),
        name: _text(row['name']),
        updatedAt: _time(row['updatedAt']),
        aliases: _texts(row['aliases']),
        packageNames: _texts(row['packageNames']),
        packageAppNames: _textMap(row['packageAppNames']),
        relationship: _text(row['relationship']),
        notes: _text(row['notes']),
        stage: _text(row['stage']),
        goal: _text(row['goal']),
        autoSummary: _text(row['autoSummary']),
      );

  static KnowledgeLogEntry _decodeEntry(Map<String, Object?> row) =>
      KnowledgeLogEntry(
        speaker: _speaker(row['speaker']),
        text: _text(row['text']),
        timestamp: _time(row['timestamp']),
        occurredAt: _optionalTime(row['occurredAt']),
        packageName: _text(row['packageName']),
      );

  static List<KnowledgeNote> _notesFrom(Object? raw) => <KnowledgeNote>[
    for (final Map<String, Object?> row in _rows(raw, _notesKey)) _decodeNote(row),
  ];

  static List<KnowledgeContact> _contactsFrom(Object? raw) =>
      <KnowledgeContact>[
        for (final Map<String, Object?> row in _rows(raw, _contactsKey))
          _decodeContact(row),
      ];

  /// Absent and empty are the same thing in this file.
  ///
  /// Every text field of a note and a contact is optional in the contract, and
  /// writing `''` for the unset ones keeps the file small and the decoder free of
  /// null checks that could not fail. See the class comment for why an optional
  /// field is coerced while an `id` is not.
  static String _text(Object? raw) => raw is String ? raw : '';

  /// The rows of a keyed section — notes and contacts.
  ///
  /// A row without an `id` string refuses the document rather than being dropped;
  /// the class comment has that argument.
  static List<Map<String, Object?>> _rows(Object? raw, String key) {
    final List<Map<String, Object?>> rows = _shape(raw, key);
    for (final Map<String, Object?> row in rows) {
      if (row['id'] is! String) {
        throw StateError(
          'every $key entry needs an id; refusing to read the knowledge base '
          'rather than dropping the row',
        );
      }
    }
    return rows;
  }

  /// The rows of an unkeyed section — the chat log.
  ///
  /// A separate reader from [_rows] because a log entry has **no id**: it is
  /// identified by its position and its timestamp, and [KnowledgeLogEntry] in the
  /// contract has no identifier field at all. Running the keyed filter over the
  /// log would drop every line, which is the bug this split exists to prevent —
  /// and which the mutation list records as caught.
  static List<Map<String, Object?>> _anyRows(Object? raw) => _shape(raw, _logsKey);

  /// Every entry of a section, as maps, or a refusal naming what is wrong.
  static List<Map<String, Object?>> _shape(Object? raw, String key) {
    if (raw == null) {
      return <Map<String, Object?>>[];
    }
    if (raw is! List) {
      throw StateError(
        '$key must be a list, and knowledge.json holds a ${raw.runtimeType}',
      );
    }
    final List<Map<String, Object?>> rows = <Map<String, Object?>>[];
    for (final Object? row in raw) {
      if (row is! Map) {
        throw StateError(
          'every $key entry must be an object, and one is a ${row.runtimeType}',
        );
      }
      rows.add(row.cast<String, Object?>());
    }
    return rows;
  }

  static Map<String, Object?> _map(Object? raw) =>
      raw is Map ? raw.cast<String, Object?>() : <String, Object?>{};

  static List<Object?> _list(Object? raw) =>
      raw is List ? raw.cast<Object?>() : const <Object?>[];

  static List<String> _texts(Object? raw) => <String>[
    for (final Object? item in _list(raw))
      if (item is String) item,
  ];

  /// A map of string keys to string values, with non-string entries dropped.
  static Map<String, String> _textMap(Object? raw) => raw is Map
      ? <String, String>{
          for (final MapEntry<Object?, Object?> entry in raw.entries)
            if (entry.key is String && entry.value is String)
              entry.key as String: entry.value as String,
        }
      : <String, String>{};

  static DateTime _time(Object? raw) => raw is String
      ? DateTime.parse(raw).toLocal()
      : DateTime.fromMillisecondsSinceEpoch(0, isUtc: true).toLocal();

  /// A time that is absent when it was never written, unlike [_time]'s epoch.
  ///
  /// `occurredAt` is optional in the contract and `''`/null is its spelling of
  /// "not set", so a missing field reads back as null rather than a fake epoch
  /// that would make every old line look like it happened at the dawn of 1970.
  static DateTime? _optionalTime(Object? raw) =>
      raw is String && raw.isNotEmpty ? DateTime.parse(raw).toLocal() : null;

  /// A speaker this store does not recognise reads back as [Speaker.other].
  ///
  /// The alternative is throwing, which would make one unrecognised line from an
  /// older build unreadable as a whole conversation. The other side is lost: the
  /// line is a chat line, and the two ends are the only two there are.
  static Speaker _speaker(Object? raw) => Speaker.values.firstWhere(
    (Speaker candidate) => candidate.name == raw,
    orElse: () => Speaker.other,
  );
}
