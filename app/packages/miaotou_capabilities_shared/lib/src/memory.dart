import 'package:miaotou_capabilities/miaotou_capabilities.dart';

import 'document.dart';

/// The remembered-profile store, in the one form all three ports use.
///
/// **Pure Dart on all three ports, no Python runtime** (ADR-0010 decision 5), so
/// this is the whole implementation and `goutoujunshi/scripts/memory_store.py` is
/// a semantic reference rather than the thing being called. The archived Python
/// port (`archive/jev-mac-python-final`) used to shell out to it; this
/// implementation loses that subprocess, its ten-second timeout and its generic
/// "check local storage permission" error that hid which of several failures had
/// happened.
///
/// ## What was kept and what was dropped
///
/// Kept, because they are this product's safety promises and `PRIVACY.md`
/// describes them: the **consent gate**, the **pause flag**, a **capacity bound**
/// and the **undo stack** (ADR-0010 decision 2). Dropped, because no port calls
/// them and scope is not something the interface distinguishes: the per-scope
/// quota table, the five source types, the confidence levels and the operation-id
/// addressing.
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
/// | [policyVersion] = `'1'` | `POLICY_VERSION` | written into the document so a later format change can be recognised rather than guessed at |
///
/// ## Two deliberate divergences from upstream, recorded here as ADR-0010
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
/// person, and the domain can still delete through `undo` or clear the document.
///
/// ## The undo stack lives in memory, and this one was a decision
///
/// The three ports had answered this two ways. Android kept the stack in a field
/// and said so in a test named *"memory persists records but undo stays within one
/// open store"*; macOS and Windows wrote it into the document under an `undo` key,
/// and macOS justified that in a comment about a user who restarts the app and
/// presses undo.
///
/// The contract settles it: `undo` "rolls back every write made **since this store
/// was opened**", and the run boundary is the store's. A stack in memory is
/// exactly that sentence; a stack in the document also reaches a previous run's
/// writes, which is a different and larger claim. The interface package's own
/// in-memory double reads it the first way too.
///
/// The consequence worth naming: `undo` is **not wired up by the product**. The
/// only caller anywhere in `lib/` is the support probe table
/// (`member_manifest.dart`), so no user-facing path reaches it and no behaviour is
/// lost by choosing the narrower reading. macOS's `undo` key is gone from the
/// document's format; ADR-0009's Consequences record that.
///
/// ## A malformed row refuses the document
///
/// The three ports disagreed about a `records` entry whose fields are not strings:
/// Android kept only well-formed rows and **silently dropped the rest**, while the
/// two desktop ports kept any map and threw at the point a field was read as a
/// `String`. Neither is a good answer to damaged data — one loses a row without
/// saying so, the other fails somewhere far from the cause — and this module takes
/// the answer the codebase already gives for a damaged document: refuse it, name
/// what is wrong, and leave the file where a reader can look at it. See
/// [JsonDocument]'s class comment for the same argument about the document itself.
final class MemoryLedger implements MemoryStore {
  MemoryLedger(TextDocuments documents)
    : _file = JsonDocument(documents, fileName);

  /// The document this store owns, inside whatever directory the platform uses.
  static const String fileName = 'memory.json';

  /// From `MAX_VALUE_CHARS` in `goutoujunshi/scripts/memory_store.py`.
  static const int maxValueChars = 200;

  /// From `MAX_ROWS` there. The whole capacity rule: ADR-0010 decision 2 keeps
  /// "a capacity bound" and drops the per-scope quota table that shared it.
  static const int maxRows = 200;

  /// From `MAX_OPERATIONS` there: how many writes `undo` can still reach.
  static const int maxOperations = 20;

  /// From `POLICY_VERSION` there, written into the document rather than assumed.
  static const String policyVersion = '1';

  static const String _consent = 'consentEnabled';
  static const String _paused = 'paused';
  static const String _records = 'records';
  static const String _policy = 'policyVersion';

  final JsonDocument _file;

  /// The writes made since this store was opened, newest last. See the class
  /// comment for why this is not in the document.
  final List<_UndoEntry> _undo = <_UndoEntry>[];

  // -- the four contract members -------------------------------------------

  @override
  Future<MemoryStatus> status() async {
    final Map<String, Object?> contents = await _file.read();
    return MemoryStatus(
      // Default false on a document that has never been written: a store nobody
      // has consented to must not have to be told so before it behaves.
      consentEnabled: contents[_consent] == true,
      paused: contents[_paused] == true,
      atCapacity: _recordRows(contents).length >= maxRows,
    );
  }

  @override
  Future<List<MemoryRecord>> show(String subjectId) async {
    final Map<String, Object?> contents = await _file.read();
    if (contents[_consent] != true) {
      return const <MemoryRecord>[];
    }
    return <MemoryRecord>[
      for (final Map<String, Object?> row in _recordRows(contents))
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
    if (contents[_consent] != true) {
      throw StateError('长期记忆尚未获得用户同意');
    }
    if (contents[_paused] == true) {
      throw StateError('长期记忆当前已暂停');
    }

    final List<Map<String, Object?>> records = _recordRows(contents);
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

    // The entry records the value that was there *before* its own write, and a
    // field that did not exist is recorded as such so undoing removes it instead
    // of writing an empty string over it. Without the `before` value, unwinding
    // the newest entry of a full stack would delete the field rather than restore
    // it, and the value the user had two seconds ago would be gone.
    _undo.add(
      _UndoEntry(
        subjectId: subjectId,
        field: field,
        before: existing < 0 ? null : records[existing]['value'] as String?,
      ),
    );
    if (_undo.length > maxOperations) {
      // Keep the newest `maxOperations`, as upstream's `prune_operation_history`
      // did. Dropping the *oldest* is right: the recent run is the one a user can
      // still be holding an undo button for.
      _undo.removeRange(0, _undo.length - maxOperations);
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
    });
  }

  /// Rolls back every write made **since this store was opened**, newest first.
  ///
  /// "Since this store was opened" is the interface's own boundary and it is not
  /// the same as "the last N writes" — a stack that outlived the store would also
  /// roll back a previous run's writes. See the class comment for why this one
  /// stops at the store.
  @override
  Future<int> undo() async {
    if (_undo.isEmpty) {
      return 0;
    }
    final Map<String, Object?> contents = await _file.read();
    final List<Map<String, Object?>> records = _recordRows(contents);
    // Reverse order, so a field written twice in one run unwinds to its earliest
    // value rather than the intermediate one. The domain's `undoSave` reverses for
    // the same reason and says so.
    for (final _UndoEntry entry in _undo.reversed) {
      final int at = records.indexWhere(
        (Map<String, Object?> row) =>
            row['subjectId'] == entry.subjectId && row['field'] == entry.field,
      );
      if (at < 0) {
        // The row is already gone — a `clear` elsewhere, or an undo that has been
        // applied twice. Nothing to restore, and skipping is right: writing the old
        // value back would resurrect a record the store has since dropped.
        continue;
      }
      final String? before = entry.before;
      if (before == null) {
        records.removeAt(at);
      } else {
        records[at] = <String, Object?>{
          'subjectId': entry.subjectId,
          'field': entry.field,
          'value': before,
        };
      }
    }
    await _file.write(<String, Object?>{...contents, _records: records});
    final int count = _undo.length;
    _undo.clear();
    return count;
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
  // * `support_declaration_test.dart` casts to the concrete type to open the
  //   consent gate before probing the contract. **That cast is the signal, not the
  //   smell:** it is visible evidence that the contract cannot express something
  //   the port genuinely needs, and it should be read as "this is the gap", not as
  //   "add these to the interface".
  // * Adding them to `MemoryStore` would be the wrong fix. It would force every
  //   port to implement four members they have no use for, and ADR-0009 requires a
  //   member to be either answered or refused — so the cost of widening the
  //   contract is two new refusals, and a `MemoryStore` that can be told to consent
  //   but cannot is worse than one that cannot.
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
  /// Upstream's `revoke` without `--delete`. Deleting the document is the other
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
  ///
  /// The stack goes with it: a store that has forgotten every row has nothing left
  /// for an undo to reach, and leaving entries that address rows which are gone
  /// would only make the next `undo` count writes it did not unwind.
  Future<void> clear() async {
    _undo.clear();
    await _file.write(<String, Object?>{});
  }

  // -- reading the document ------------------------------------------------

  /// The `records` entries, or a refusal naming what is wrong with them.
  ///
  /// Every member that touches records goes through here, `status` included: a
  /// document that cannot be read out is a fact about the document, not about the
  /// member that happened to open it, and a `status` that counted a malformed row
  /// as a row would report a capacity the store cannot actually serve.
  static List<Map<String, Object?>> _recordRows(Map<String, Object?> contents) {
    final Object? raw = contents[_records];
    if (raw == null) {
      return <Map<String, Object?>>[];
    }
    if (raw is! List) {
      throw StateError(
        '$_records must be a list, and memory.json holds a ${raw.runtimeType}',
      );
    }
    final List<Map<String, Object?>> rows = <Map<String, Object?>>[];
    for (final Object? row in raw) {
      if (row is! Map) {
        throw StateError(
          'every $_records entry must be an object, and one is a '
          '${row.runtimeType}',
        );
      }
      if (row['subjectId'] is! String ||
          row['field'] is! String ||
          row['value'] is! String) {
        throw StateError(
          'a $_records entry is not a subjectId/field/value of strings; '
          'refusing to read the store rather than dropping the row',
        );
      }
      rows.add(row.cast<String, Object?>());
    }
    return rows;
  }

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
}

/// One write this store made, and what was in its place before.
final class _UndoEntry {
  const _UndoEntry({
    required this.subjectId,
    required this.field,
    required this.before,
  });

  final String subjectId;
  final String field;

  /// The value the row held before this write, or null when there was no row —
  /// which is a different instruction to [MemoryLedger.undo] than the empty
  /// string would be.
  final String? before;
}
