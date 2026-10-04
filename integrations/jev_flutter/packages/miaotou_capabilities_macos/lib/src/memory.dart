import 'package:miaotou_capabilities/miaotou_capabilities.dart';

import 'container_file.dart';
import 'native.dart';

/// macOS's answer for the memory store.
///
/// Owned by #15. **Pure Dart on all three ports, no Python runtime** (ADR-0010
/// decision 5), so this is the whole implementation and
/// `goutoujunshi/scripts/memory_store.py` is a semantic reference rather than
/// the thing being called. The archived Python port
/// (`archive/jev-mac-python-final`) used to shell out to it; this implementation
/// loses that subprocess, its ten-second timeout and its generic "check local
/// storage permission" error that hid which of several failures had happened.
///
/// ## What was kept and what was dropped
///
/// Kept, because they are this product's safety promises and `PRIVACY.md`
/// describes them: the **consent gate**, the **pause flag**, a **capacity
/// bound** and the **undo stack** (ADR-0010 decision 2). Dropped, because no port
/// calls them and scope is not something the interface distinguishes: the
/// per-scope quota table, the five source types, the confidence levels and the
/// operation-id addressing.
///
/// ## The numbers, and where each came from
///
/// Not invented. All four are copied from the top of
/// `goutoujunshi/scripts/memory_store.py`:
///
/// | here | upstream | why it is the same number |
/// |---|---|---|
/// | [maxValueChars] = 200 | `MAX_VALUE_CHARS` | one remembered field is a short label, and the cap is what stops a transcript being written into `notes` |
/// | [maxRows] = 200 | `MAX_ROWS` | the total-row bound; upstream also enforced per-scope quotas, which ADR-0010 decision 2 drops, so this is the whole capacity rule now |
/// | [maxOperations] = 20 | `MAX_OPERATIONS` | how many operations the undo history keeps; upstream pruned to the newest 20, and so does this |
/// | [policyVersion] = `'1'` | `POLICY_VERSION` | written into the file so a later format change can be recognised rather than guessed at |
///
/// ## One deliberate divergence from upstream, recorded here as ADR-0010
/// decision 4 asks
///
/// **Without consent, `show` returns nothing.** Upstream's `command_show` reads
/// the table regardless of the consent flag — only `apply` and `context` check
/// it. This store refuses to read out as well, because the contract says so in
/// its own words ("with no consent nothing may be read out either") and because
/// the rows are about a person: a store that will not write them without consent
/// has no business handing them to a prompt without it.
///
/// A second, smaller one: upstream prunes the oldest `event` and `hypothesis`
/// rows to make room, and refuses only when the total is still over the limit.
/// With the scope taxonomy gone there is nothing to prune *preferentially*, so
/// this store refuses at [maxRows] instead of silently forgetting something. An
/// unrecoverable-by-surprise store is the better failure for a record of a
/// person, and the domain can still delete through `undo` or clear the file.
final class MacosMemoryStore implements MemoryStore {
  MacosMemoryStore(ContainerFile file) : _file = file;

  /// Over this port's own memory file in the application container.
  factory MacosMemoryStore.inContainer(MacosNative native) =>
      MacosMemoryStore(ContainerFile(native, 'memory.json'));

  final ContainerFile _file;

  /// From `MAX_VALUE_CHARS` in `goutoujunshi/scripts/memory_store.py`.
  static const int maxValueChars = 200;

  /// From `MAX_ROWS` there. The whole capacity rule: ADR-0010 decision 2 keeps
  /// "a capacity bound" and drops the per-scope quota table that shared it.
  static const int maxRows = 200;

  /// From `MAX_OPERATIONS` there: how many writes `undo` can still reach.
  static const int maxOperations = 20;

  /// From `POLICY_VERSION` there, written into the file rather than assumed.
  static const String policyVersion = '1';

  static const String _consent = 'consentEnabled';
  static const String _paused = 'paused';
  static const String _records = 'records';
  static const String _undo = 'undo';
  static const String _policy = 'policyVersion';

  // -- the four contract members -------------------------------------------

  @override
  Future<MemoryStatus> status() async {
    final Map<String, Object?> contents = await _file.read();
    return MemoryStatus(
      // Default false on a file that has never been written: a store nobody has
      // consented to must not have to be told so before it behaves.
      consentEnabled: contents[_consent] == true,
      paused: contents[_paused] == true,
      atCapacity: _rows(contents[_records]).length >= maxRows,
    );
  }

  @override
  Future<List<MemoryRecord>> show(String subjectId) async {
    final Map<String, Object?> contents = await _file.read();
    if (contents[_consent] != true) {
      return const <MemoryRecord>[];
    }
    return <MemoryRecord>[
      for (final Map<String, Object?> row in _rows(contents[_records]))
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
    _validate(subjectId: subjectId, field: field, value: value);
    final Map<String, Object?> contents = await _file.read();
    final bool consent = contents[_consent] == true;
    final bool paused = contents[_paused] == true;
    if (!consent) {
      throw StateError('长期记忆尚未获得用户同意');
    }
    if (paused) {
      throw StateError('长期记忆当前已暂停');
    }

    final List<Map<String, Object?>> records = _rows(contents[_records]);
    final int existing = records.indexWhere(
      (Map<String, Object?> row) =>
          row['subjectId'] == subjectId && row['field'] == field,
    );
    // Updating a field the store already holds is not a new row, so it does not
    // count against the capacity. Upstream's `prune_rows` reasoned the same way
    // about an update.
    if (existing < 0 && records.length >= maxRows) {
      throw StateError('长期记忆已达 $maxRows 条上限，请先清空后再保存');
    }

    // The undo entry is what makes `undo` mean "this run" rather than "the last
    // thing". The previous value is recorded before the write, and a field that
    // did not exist is recorded as such so undoing removes it instead of writing
    // an empty string over it.
    final List<Map<String, Object?>> undo = _rows(contents[_undo]);
    undo.add(<String, Object?>{
      'subjectId': subjectId,
      'field': field,
      'before': existing < 0 ? null : records[existing]['value'],
    });
    if (undo.length > maxOperations) {
      // Keep the newest `maxOperations`, as upstream's `prune_operation_history`
      // did. Dropping the *oldest* is right: the recent run is the one a user
      // can still be holding an undo button for.
      undo.removeRange(0, undo.length - maxOperations);
    }

    final Map<String, Object?> row = <String, Object?>{
      'subjectId': subjectId,
      'field': field,
      'value': value,
    };
    if (existing < 0) {
      records.add(row);
    } else {
      records[existing] = row;
    }

    await _file.write(<String, Object?>{
      ...contents,
      _policy: policyVersion,
      _records: records,
      _undo: undo,
    });
  }

  /// Rolls back every write made **since this store was opened**, newest first.
  ///
  /// "Since this store was opened" is the interface's own boundary and it is not
  /// the same as "the last N writes": the stack is in the file, so it also holds
  /// the writes of a *previous* run that were never undone. Those are rolled back
  /// too, and that is deliberate — the alternative is a stack that grows across
  /// runs until it silently forgets, and a user who restarts the app and presses
  /// undo expects the profile to go back to how it was, not to have the last run's
  /// changes survive.
  @override
  Future<int> undo() async {
    final Map<String, Object?> contents = await _file.read();
    final List<Map<String, Object?>> undo = _rows(contents[_undo]);
    if (undo.isEmpty) {
      return 0;
    }
    final List<Map<String, Object?>> records = _rows(contents[_records]);
    // Reverse order, so a field written twice in one run unwinds to its earliest
    // value rather than the intermediate one. The domain's `undoSave` reverses for
    // the same reason and says so.
    for (final Map<String, Object?> entry in undo.reversed) {
      final int at = records.indexWhere(
        (Map<String, Object?> row) =>
            row['subjectId'] == entry['subjectId'] && row['field'] == entry['field'],
      );
      if (at < 0) {
        // The row is already gone — a `clearAll` elsewhere, or an undo that has
        // been applied twice. Nothing to restore, and skipping is right: writing
        // the old value back would resurrect a record the store has since dropped.
        continue;
      }
      final Object? before = entry['before'];
      if (before == null) {
        records.removeAt(at);
      } else {
        records[at] = <String, Object?>{
          'subjectId': entry['subjectId'],
          'field': entry['field'],
          'value': before,
        };
      }
    }
    await _file.write(<String, Object?>{
      ...contents,
      _records: records,
      _undo: const <Object?>[],
    });
    return undo.length;
  }

  // -- the port's own affordances ------------------------------------------
  //
  // Not on the contract, and deliberately so: ADR-0010 decision 1 keeps the
  // interface to the four operations the bridge used. But a store whose consent
  // can never be granted is inert, so the switches live here on the concrete
  // type. A caller holding a `MemoryStore` cannot reach them without casting —
  // see the note in the delivery report; the contract has no member for "the user
  // agreed", and adding one is a decision above this ticket.
  //
  // **These four methods are extensions on this concrete type and are not part of
  // the `MemoryStore` contract**, which is a deliberate boundary rather than an
  // oversight:
  //
  // * [grantConsent], [revokeConsent], [setPaused] and [clear] are unreachable
  //   through a `MemoryStore` handle, so no port can depend on them being there —
  //   which is what keeps the three implementations substitutable.
  // * `support_declaration_test.dart` casts to `MacosMemoryStore` to open the
  //   consent gate before probing the contract. **That cast is the signal, not the
  //   smell:** it is visible evidence that the contract cannot express something
  //   the port genuinely needs, and it should be read as "this is the gap", not as
  //   "add these to the interface".
  // * Adding them to `MemoryStore` would be the wrong fix. It would force the
  //   Android and Windows ports to implement four members they have no use for,
  //   and ADR-0009 requires a member to be either answered or refused — so the
  //   cost of widening the contract is two new refusals, and a `MemoryStore` that
  //   can be told to consent but cannot is worse than one that cannot.
  //
  // The right resolution is a contract ticket, above this one. Until it lands,
  // this comment and the cast are where the gap is recorded.

  /// Records the user's consent, which is the only thing that opens this store.
  ///
  /// [confirmed] must be true, mirroring upstream's `--confirm`: the upstream CLI
  /// refused to enable the store without it, because "enable" is the one action
  /// here that starts storing something about a person.
  Future<void> grantConsent({required bool confirmed}) async {
    if (!confirmed) {
      throw StateError('需要用户明确确认才能启用长期记忆');
    }
    final Map<String, Object?> contents = await _file.read();
    await _file.write(<String, Object?>{
      ...contents,
      _policy: policyVersion,
      _consent: true,
      // Granting consent clears a pause, as upstream's `command_enable` did: the
      // user was asked again and said yes, so a pause from before the question
      // is not a refusal of the answer.
      _paused: false,
    });
  }

  /// Withdraws consent and stops writing, keeping what was already stored.
  ///
  /// Upstream's `revoke` without `--delete`. Deleting the file is the other
  /// operation, and the two are separate on purpose: a user who turns the feature
  /// off and a user who wants their data gone are different requests.
  Future<void> revokeConsent() async {
    final Map<String, Object?> contents = await _file.read();
    await _file.write(<String, Object?>{
      ...contents,
      _consent: false,
      _paused: true,
    });
  }

  /// Pauses or resumes writing without touching consent.
  Future<void> setPaused({required bool paused}) async {
    final Map<String, Object?> contents = await _file.read();
    if (contents[_consent] != true) {
      // Upstream's `command_pause` checks this too: pausing a store that was
      // never enabled is a request that does not mean anything, and answering it
      // would suggest the store is on.
      throw StateError('长期记忆尚未获得用户同意');
    }
    await _file.write(<String, Object?>{...contents, _paused: paused});
  }

  /// Empties the store completely, as `command_clear` did.
  Future<void> clear() => _file.write(<String, Object?>{});

  // -- validation ----------------------------------------------------------

  /// The rules from upstream's `validate_text`, minus the taxonomy.
  ///
  /// Whitespace-trimmed, required, length-capped and control-character-free,
  /// because each of those is a way a stored value stops being what it claims to
  /// be: an all-whitespace label is empty, a 5000-character one is a transcript
  /// in a field meant for a phrase, and a control character is what a terminal
  /// escape looks like when it comes back out in a prompt.
  static void _validate({
    required String subjectId,
    required String field,
    required String value,
  }) {
    if (subjectId.trim().isEmpty) {
      throw StateError('记忆必须有归属对象');
    }
    if (field.trim().isEmpty) {
      throw StateError('记忆必须有字段名');
    }
    final String trimmed = value.trim();
    if (trimmed.isEmpty) {
      // Upstream's `required=True`. The domain never sends an empty value — it
      // writes `未填写` for "unknown" (see `memory.dart`'s `_toStoreValue`) — so
      // an empty one here means a caller bypassed the translation, and storing it
      // would make "unset" and "set to nothing" the same row.
      throw StateError('记忆值不能为空');
    }
    if (trimmed.length > maxValueChars) {
      throw StateError('记忆值超过 $maxValueChars 字符');
    }
    if (trimmed.runes.any((int rune) => rune < 32 && rune != 9 && rune != 10)) {
      throw StateError('记忆值包含控制字符');
    }
  }

  static List<Map<String, Object?>> _rows(Object? raw) => <Map<String, Object?>>[
        for (final Object? row in raw is List ? raw.cast<Object?>() : const <Object?>[])
          if (row is Map) row.cast<String, Object?>(),
      ];
}
