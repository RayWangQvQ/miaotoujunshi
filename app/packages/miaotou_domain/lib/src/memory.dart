import 'package:miaotou_capabilities/miaotou_capabilities.dart';

import 'errors.dart';
import 'relationship.dart';

/// The store-level marker for "no value". The upstream CLI does not accept
/// empty strings, so the bridge wrote this marker and read it back; the
/// domain works in the empty string for unknown, and the marker stays at the
/// store boundary, here.
const String neutralMarker = '未填写';

/// Fields whose payload value really is `未填写` (the first stage is named that),
/// so the marker is never translated to or from the empty string for them.
const List<String> markerInvariantFields = <String>['stage', 'goal'];

/// One field's worth of change between two profiles.
///
/// [before] is the empty string when the field did not exist. [after] is the
/// new value, also possibly empty — empty `after` means "clear this field",
/// which the store represents by writing [neutralMarker] (see [applySave]).
final class FieldChange {
  const FieldChange({
    required this.field,
    required this.before,
    required this.after,
  });

  final String field;
  final String before;
  final String after;

  bool get isChange => before != after;

  @override
  String toString() => '$field: "$before" → "$after"';
}

/// One save's worth of changes, addressed to one subject.
final class ProfileSave {
  const ProfileSave({required this.subjectId, required this.changes});

  final String subjectId;
  final List<FieldChange> changes;

  bool get isEmpty => changes.isEmpty;

  /// The fields this save touches, in order. Used by the caller to surface what
  /// is about to be written before it is.
  List<String> get fields =>
      <String>[for (final FieldChange c in changes) c.field];

  @override
  String toString() => 'ProfileSave($subjectId, ${changes.length} changes)';
}

/// The diff the bridge used to ship to the store. Pure: it does not touch the
/// store, so a caller can show it for confirmation before applying.
///
/// Walks [profileFields] in order so the diff is stable across runs regardless
/// of map iteration order — the existing suite locks the order of operations,
/// and a diff that reordered them would undo that lock without anything to
/// show for it.
List<FieldChange> diffProfile(Profile before, Profile after) {
  final List<FieldChange> changes = <FieldChange>[];
  for (final String key in profileFields) {
    final String a = before.value(key);
    final String b = after.value(key);
    if (a != b) {
      changes.add(FieldChange(field: key, before: a, after: b));
    }
  }
  return changes;
}

/// One field's change as one user-facing line.
///
/// The sentence is the one macOS's settings page already showed; the test
/// suite asserts it, and "档案已更新：称呼 → 小王" is a better sentence than
/// "called display_label written with value 小王".
String describeChange(FieldChange change) {
  const Map<String, String> labels = <String, String>{
    'label': '称呼',
    'stage': '关系阶段',
    'goal': '本轮目标',
    'background': '背景',
    'my_mbti': '我的 MBTI',
    'their_mbti': '对方 MBTI',
    'my_score': '我的评分',
    'their_score': '对方评分',
    'notes': '备注',
  };
  final String name = labels[change.field] ?? change.field;
  if (change.before.isEmpty) {
    return '档案已更新：$name → ${change.after}';
  }
  if (change.after.isEmpty) {
    return '档案已更新：$name 已清空';
  }
  return '档案已更新：$name $change.before → $change.after';
}

/// Applies one save's worth of changes to the store.
///
/// Checks [MemoryStatus.acceptsWrites] once, up front, so a store that would
/// refuse is refused before any write happens — the upstream behaviour the
/// bridge kept, and the one the test asserts: a paused store does not write
/// half a profile and then fail. Each change is one write, in order.
///
/// Returns the number of writes. Zero is legitimate: it means the new profile
/// did not change any field, which the bridge reported as "0" and the UI left
/// at that — there is no "nothing to save" sentence because nothing failed.
Future<int> applySave(
  MemoryStore store,
  MemoryStatus status,
  ProfileSave save,
) async {
  if (save.isEmpty) return 0;
  if (!status.acceptsWrites) {
    throw const DomainException('档案未启用、已暂停或已达到容量上限');
  }
  for (final FieldChange change in save.changes) {
    await store.apply(
      subjectId: save.subjectId,
      field: Profile.storeField(change.field),
      value: _toStoreValue(change.field, change.after),
    );
  }
  return save.changes.length;
}

/// Reverts a save by rewriting each change's `before` value.
///
/// The new memory interface dropped per-op addressing (ADR-0010 decision 1),
/// so the only way to undo a save without it is to write the previous values
/// back. This matches the product's "undo my last save": the caller holds the
/// [ProfileSave] it just applied, and overwrites that hold on the next save —
/// so only the last save is revertable, which is the bridge's
/// `last_operations = list(operations)` line, restated.
///
/// The reverts run in reverse order, matching the bridge's pop-from-the-end
/// loop. It does not matter for an idempotent write, but the order is kept
/// anyway because keeping it is free and reversing it is not.
///
/// The store-level [MemoryStore.undo] is a separate, capability-owned "clear
/// everything since open" and the product does not wire it up; see the note in
/// [memory_store.dart].
Future<void> undoSave(MemoryStore store, ProfileSave save) async {
  if (save.isEmpty) return;
  for (final FieldChange change in save.changes.reversed) {
    await store.apply(
      subjectId: save.subjectId,
      field: Profile.storeField(change.field),
      value: _toStoreValue(change.field, change.before),
    );
  }
}

/// Maps an application value to the value the store actually holds.
///
/// The empty string becomes [neutralMarker] for every field except
/// [markerInvariantFields], where `未填写` is the field's real value rather
/// than its absence — translating those would invent a stage the user did not
/// pick.
String _toStoreValue(String field, String value) {
  if (value.isEmpty && !markerInvariantFields.contains(field)) {
    return neutralMarker;
  }
  return value;
}