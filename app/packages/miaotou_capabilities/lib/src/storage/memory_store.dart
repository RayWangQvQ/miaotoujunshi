/// The state the memory store is gated on.
///
/// Consent, pausing and a capacity bound are the three safety semantics kept
/// from the upstream script (ADR-0010 decision 2). They are now this
/// repository's own promise rather than the skill's, which is why `PRIVACY.md`
/// describes them.
final class MemoryStatus {
  const MemoryStatus({
    required this.consentEnabled,
    required this.paused,
    required this.atCapacity,
  });

  /// The user has consented to memories being stored at all. Default false: with
  /// no consent nothing is written, and nothing that was written is read out.
  final bool consentEnabled;

  /// The user paused writing without revoking consent.
  final bool paused;

  /// The store has reached its capacity bound and refuses further writes.
  final bool atCapacity;

  /// True only when a write may proceed. A caller must ask before offering the
  /// action, not discover the refusal afterwards.
  bool get acceptsWrites => consentEnabled && !paused && !atCapacity;

  @override
  String toString() => 'MemoryStatus(consent: $consentEnabled, paused: $paused, '
      'atCapacity: $atCapacity)';
}

/// One remembered field of one subject.
final class MemoryRecord {
  const MemoryRecord({
    required this.subjectId,
    required this.field,
    required this.value,
  });

  /// Who the memory is about. Opaque to the store.
  final String subjectId;

  /// Which field of that subject, e.g. `stage` or `display_label`.
  final String field;

  final String value;

  @override
  String toString() => 'MemoryRecord($subjectId.$field)';
}

/// The remembered-profile store.
///
/// **Only the subset the application uses** (ADR-0010): the four operations
/// below and no others. The upstream script's per-scope quotas, its source-type
/// taxonomy and its operation-id addressing are deliberately absent — nothing
/// calls them, and scope is not something the interface distinguishes.
///
/// This store is implemented in Dart on all three ports. No Python runtime is
/// bundled anywhere (ADR-0010 decision 5), so the upstream script is a semantic
/// reference rather than the implementation, and a divergence from it is
/// recorded in that ADR instead of being found by diffing.
abstract interface class MemoryStore {
  /// Reads the consent, pause and capacity state.
  Future<MemoryStatus> status();

  /// Every remembered field for one subject. Empty when nothing is stored —
  /// which is not an error, but a caller must check [status] first: with no
  /// consent nothing may be read out either.
  Future<List<MemoryRecord>> show(String subjectId);

  /// Writes one field.
  ///
  /// Refuses when the status does not accept writes, rather than writing and
  /// reporting afterwards. Each successful call is one entry on the undo stack.
  Future<void> apply({
    required String subjectId,
    required String field,
    required String value,
  });

  /// Rolls back every write made since this store was opened, and returns how
  /// many were rolled back.
  ///
  /// The run boundary is the store's. The upstream script addressed operations
  /// by id; the bridge never used that, so neither does this interface
  /// (ADR-0010 decision 1).
  Future<int> undo();
}
