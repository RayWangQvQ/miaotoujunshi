import 'package:miaotou_capabilities/miaotou_capabilities.dart';

import 'container_file.dart';
import 'native.dart';

/// macOS's answer for the knowledge base.
///
/// Owned by #15. The union baseline (ADR-0007 decision 4) means this port keeps a
/// capability it never had: the knowledge base used to be Android's alone.
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
final class MacosKnowledgeStore implements KnowledgeStore {
  MacosKnowledgeStore(ContainerFile file) : _file = file;

  /// Over this port's own knowledge file in the application container.
  factory MacosKnowledgeStore.inContainer(MacosNative native) =>
      MacosKnowledgeStore(ContainerFile(native, 'knowledge.json'));

  final ContainerFile _file;

  static const String _notesKey = 'notes';
  static const String _contactsKey = 'contacts';
  static const String _logsKey = 'logs';

  @override
  Future<List<KnowledgeNote>> notes() async =>
      _notesFrom((await _file.read())[_notesKey]);

  @override
  Future<void> saveNote(KnowledgeNote note) async {
    final Map<String, Object?> contents = await _file.read();
    final List<Map<String, Object?>> all = _rows(contents[_notesKey]);
    all.removeWhere((Map<String, Object?> row) => row['id'] == note.id);
    all.add(_encodeNote(note));
    await _file.write(<String, Object?>{...contents, _notesKey: all});
  }

  @override
  Future<void> deleteNote(String id) async {
    final Map<String, Object?> contents = await _file.read();
    final List<Map<String, Object?>> all = _rows(contents[_notesKey]);
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
    final List<Map<String, Object?>> all = _rows(contents[_contactsKey]);
    all.removeWhere((Map<String, Object?> row) => row['id'] == contact.id);
    all.add(_encodeContact(contact));
    await _file.write(<String, Object?>{...contents, _contactsKey: all});
  }

  @override
  Future<void> deleteContact(String id) async {
    final Map<String, Object?> contents = await _file.read();
    final List<Map<String, Object?>> all = _rows(contents[_contactsKey]);
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
      // Appending nothing must not rewrite the file: `appendLog` is called after
      // every capture, and a no-op that touched the document would make its
      // timestamp mean nothing.
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
    final List<Map<String, Object?>> all =
        _anyRows(_map((await _file.read())[_logsKey])[contactId]);
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

  static String _normalise(String value) => value.trim().toLowerCase();

  /// Removes every row with this id, reporting whether there was one.
  ///
  /// Both halves matter: the callers use the answer to avoid rewriting the file
  /// for a delete of something that was never there, which matters because
  /// `deleteNote` is reachable from a swipe gesture and a rewrite on every empty
  /// swipe would make the file's timestamp meaningless. It is written by hand
  /// rather than with `removeWhere` because that returns `void`.
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
        packageName: _text(row['packageName']),
      );

  static List<KnowledgeNote> _notesFrom(Object? raw) => <KnowledgeNote>[
        for (final Map<String, Object?> row in _rows(raw)) _decodeNote(row),
      ];

  static List<KnowledgeContact> _contactsFrom(Object? raw) =>
      <KnowledgeContact>[
        for (final Map<String, Object?> row in _rows(raw)) _decodeContact(row),
      ];

  /// Absent and empty are the same thing in this file.
  ///
  /// Every text field of a contact is optional in the contract, and writing `''`
  /// for the unset ones keeps the file small and the decoder free of null checks
  /// that could not fail.
  static String _text(Object? raw) => raw is String ? raw : '';

  /// The rows of a keyed section — notes and contacts.
  ///
  /// A row with no `id` is **dropped**, not defaulted. An id is the only field
  /// that is not optional on either value type, and a row missing it is a file
  /// this store did not write. Giving it `''` would merge it with every other
  /// idless row into one record that the next save would then overwrite, so a
  /// damaged file loses the damaged rows rather than inventing an identity for
  /// them.
  static List<Map<String, Object?>> _rows(Object? raw) => <Map<String, Object?>>[
        for (final Object? row in _list(raw))
          if (row is Map && row['id'] is String)
            row.cast<String, Object?>(),
      ];

  /// The rows of an unkeyed section — the chat log.
  ///
  /// A separate reader from [_rows] because a log entry has **no id**: it is
  /// identified by its position and its timestamp, and `KnowledgeLogEntry` in the
  /// contract has no identifier field at all. Running the keyed filter over the
  /// log would drop every line, which is the bug this split exists to prevent —
  /// and which the mutation list records as caught.
  static List<Map<String, Object?>> _anyRows(Object? raw) => <Map<String, Object?>>[
        for (final Object? row in _list(raw))
          if (row is Map) row.cast<String, Object?>(),
      ];

  static Map<String, Object?> _map(Object? raw) => raw is Map
      ? raw.cast<String, Object?>()
      : <String, Object?>{};

  static List<Object?> _list(Object? raw) =>
      raw is List ? raw.cast<Object?>() : const <Object?>[];

  static List<String> _texts(Object? raw) => <String>[
        for (final Object? item in _list(raw))
          if (item is String) item,
      ];

  static DateTime _time(Object? raw) => raw is String
      ? DateTime.parse(raw).toLocal()
      : DateTime.fromMillisecondsSinceEpoch(0, isUtc: true).toLocal();

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
