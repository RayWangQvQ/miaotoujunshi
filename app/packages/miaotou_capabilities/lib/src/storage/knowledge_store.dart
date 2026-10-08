import '../model/speaker.dart';

/// One free-text note the user maintains by hand.
final class KnowledgeNote {
  const KnowledgeNote({
    required this.id,
    required this.title,
    required this.content,
    required this.updatedAt,
    this.tags = const <String>[],
    this.alwaysOn = false,
    this.enabled = true,
  });

  final String id;
  final String title;
  final String content;
  final DateTime updatedAt;

  final List<String> tags;

  /// Injected regardless of what the conversation is about.
  final bool alwaysOn;

  /// Turned off notes stay stored and are not injected.
  final bool enabled;

  @override
  String toString() => 'KnowledgeNote($id, $title)';
}

/// One person (or group) the user chats with.
///
/// [aliases] is what makes a contact portable: the same person appears under a
/// different conversation title in each chat application, and every one of those
/// titles can be listed here. Without it a contact would be per-application, and
/// the union baseline (ADR-0007 decision 4) would not be reachable.
final class KnowledgeContact {
  const KnowledgeContact({
    required this.id,
    required this.name,
    required this.updatedAt,
    this.aliases = const <String>[],
    this.packageNames = const <String>[],
    this.packageAppNames = const <String, String>{},
    this.relationship = '',
    this.notes = '',
    this.stage = '',
    this.goal = '',
    this.autoSummary = '',
  });

  final String id;
  final String name;
  final DateTime updatedAt;

  /// Conversation titles this contact has been seen under.
  final List<String> aliases;

  /// Package names this contact has been seen in, e.g. `com.tencent.mm`.
  final List<String> packageNames;

  /// Display name for each package in [packageNames], e.g.
  /// `com.ss.android.ugc.aweme` → `抖音`. A package without an entry shows its
  /// bare package name. Kept beside the packages so the knowledge base can group
  /// by the name a person reads rather than the id the platform reports.
  final Map<String, String> packageAppNames;

  final String relationship;
  final String notes;

  /// Relationship stage. Empty means "not filled in", which is a legitimate
  /// state and not the same as any particular stage.
  final String stage;

  /// What this conversation is being steered towards right now.
  final String goal;

  /// Reserved for summarising long histories. Empty until something writes it.
  final String autoSummary;

  @override
  String toString() => 'KnowledgeContact($id, $name)';
}

/// One remembered chat line.
final class KnowledgeLogEntry {
  const KnowledgeLogEntry({
    required this.speaker,
    required this.text,
    required this.timestamp,
    required this.packageName,
  });

  final Speaker speaker;
  final String text;
  final DateTime timestamp;

  /// The application the line was seen in, so a merged history can still say
  /// where each part of it came from.
  final String packageName;

  @override
  String toString() => 'KnowledgeLogEntry(${speaker.name}, $text)';
}

/// What one analysis gets to see beyond the lines currently on screen: who the
/// other party is, older history with them, and the notes that matched.
///
/// This is the feature Android had alone before the migration and every port has
/// now (ADR-0007 decision 4). Everything in it is local: there is no database,
/// no network and no export, and one action empties the whole store.
abstract interface class KnowledgeStore {
  Future<List<KnowledgeNote>> notes();

  Future<void> saveNote(KnowledgeNote note);

  Future<void> deleteNote(String id);

  Future<List<KnowledgeContact>> contacts();

  /// The contact this conversation belongs to, matched on conversation title
  /// and package. Null when nothing matches — a legitimate state, not an error.
  ///
  /// Merging a match into an existing contact is not this interface's job.
  Future<KnowledgeContact?> findContact({
    required String title,
    required String packageName,
  });

  Future<void> saveContact(KnowledgeContact contact);

  Future<void> deleteContact(String id);

  /// Records a display name under [key].
  ///
  /// [key] is the package name when one is known, and the user's own entry when
  /// it is not (ADR-0030): a package the system cannot name has nothing else to
  /// be keyed by, and the name the user typed is the only stable handle left.
  /// The read side is not wired to the platform's name resolution yet — the
  /// mapping is stored so a later port can ask for it, and nothing displays it.
  Future<void> saveAppName(String key, String displayName);

  /// The display name recorded under [key], or null when there is none.
  Future<String?> appNameFor(String key);

  /// Appends lines to one contact's history, oldest first. Whether a line is
  /// worth keeping is the caller's decision.
  Future<void> appendLog(String contactId, List<KnowledgeLogEntry> entries);

  /// The most recent [limit] lines for one contact, oldest first.
  Future<List<KnowledgeLogEntry>> recentLog(String contactId, {required int limit});

  /// Empties the store. This is the user-visible "清空知识库与历史" action.
  Future<void> clearAll();
}
