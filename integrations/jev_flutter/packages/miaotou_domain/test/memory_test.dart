import 'package:test/test.dart';
import 'package:miaotou_capabilities/miaotou_capabilities.dart';
import 'package:miaotou_domain/miaotou_domain.dart';

/// One recorded `apply` call, for assertions in the memory tests.
final class RecordedApply {
  const RecordedApply({
    required this.subjectId,
    required this.field,
    required this.value,
  });

  final String subjectId;
  final String field;
  final String value;
}

/// A [MemoryStore] that records every `apply` and answers `status` with
/// whatever the test set. Its `undo` is deliberately not used by the domain:
/// the domain reverts by re-applying the previous values, and asserting that
/// here pins the decision.
final class RecordingMemoryStore implements MemoryStore {
  RecordingMemoryStore(this._status);

  MemoryStatus _status;
  final List<RecordedApply> applies = <RecordedApply>[];

  void setStatus(MemoryStatus status) => _status = status;

  @override
  Future<MemoryStatus> status() async => _status;

  @override
  Future<List<MemoryRecord>> show(String subjectId) async =>
      <MemoryRecord>[];

  @override
  Future<void> apply({
    required String subjectId,
    required String field,
    required String value,
  }) async {
    applies.add(RecordedApply(
        subjectId: subjectId, field: field, value: value));
  }

  @override
  Future<int> undo() async => 0;
}

const MemoryStatus _active =
    MemoryStatus(consentEnabled: true, paused: false, atCapacity: false);
const MemoryStatus _paused =
    MemoryStatus(consentEnabled: true, paused: true, atCapacity: false);
const MemoryStatus _atCapacity =
    MemoryStatus(consentEnabled: true, paused: false, atCapacity: true);
const MemoryStatus _noConsent =
    MemoryStatus(consentEnabled: false, paused: false, atCapacity: false);

void main() {
  Profile base() => Profile(
        id: 'mac-test',
        label: '小王',
        stage: '初识',
        goal: '主动邀约',
      );

  group('diffProfile', () {
    test('returns nothing when nothing changed', () {
      expect(diffProfile(base(), base()), <FieldChange>[]);
    });

    test('walks the payload field order, not map order', () {
      final Profile after = base()
          .withValue('goal', '减少投入')
          .withValue('label', '大王');
      final List<FieldChange> changes = diffProfile(base(), after);
      expect(changes.map((FieldChange c) => c.field).toList(),
          <String>['label', 'goal']);
    });

    test('records before as empty when the field was new', () {
      final Profile before = Profile(id: 'mac-test', label: '当前会话');
      final Profile after = base().withValue('notes', '要紧的');
      final List<FieldChange> changes = diffProfile(before, after);
      final FieldChange notes =
          changes.firstWhere((FieldChange c) => c.field == 'notes');
      expect(notes.before, '');
      expect(notes.after, '要紧的');
    });

    test('records after as empty when a field was cleared', () {
      final Profile before = base().withValue('notes', '要紧的');
      final Profile after = base().withValue('notes', '');
      final List<FieldChange> changes = diffProfile(before, after);
      expect(changes.single.field, 'notes');
      expect(changes.single.after, '');
    });
  });

  group('describeChange', () {
    test('names the field in the user-facing word', () {
      expect(
        describeChange(const FieldChange(
            field: 'label', before: '', after: '小王')),
        contains('称呼'),
      );
    });

    test('says 已清空 when a value was cleared', () {
      expect(
        describeChange(const FieldChange(
            field: 'notes', before: '旧的', after: '')),
        contains('已清空'),
      );
    });

    test('joins old and new when both are present', () {
      final String line = describeChange(const FieldChange(
          field: 'goal', before: '主动邀约', after: '减少投入'));
      expect(line, contains('主动邀约'));
      expect(line, contains('减少投入'));
    });
  });

  group('applySave', () {
    test('writes one apply per change, in order, with the store field name',
        () async {
      final RecordingMemoryStore store = RecordingMemoryStore(_active);
      final Profile before = base();
      final Profile after = base()
          .withValue('label', '大王')
          .withValue('notes', '旧的');
      final ProfileSave save = ProfileSave(
          subjectId: 'mac-test', changes: diffProfile(before, after));

      final int n = await applySave(store, _active, save);

      expect(n, 2);
      expect(store.applies.first.field, 'display_label');
      expect(store.applies.first.value, '大王');
      expect(store.applies.last.field, 'notes');
      expect(store.applies.last.value, '旧的');
    });

    test('writes the neutral marker for an empty value, except stage and goal',
        () async {
      final RecordingMemoryStore store = RecordingMemoryStore(_active);
      final Profile before =
          base().withValue('notes', '旧的').withValue('my_mbti', 'INTJ');
      final Profile after = base(); // both cleared
      final ProfileSave save = ProfileSave(
          subjectId: 'mac-test', changes: diffProfile(before, after));

      await applySave(store, _active, save);

      final List<String> values = store.applies
          .map((RecordedApply a) => a.value)
          .toList();
      expect(values, everyElement(neutralMarker));
    });

    test('writes the stage named 未填写 verbatim, not as a marker', () async {
      final RecordingMemoryStore store = RecordingMemoryStore(_active);
      // 未填写 is the first stage AND the neutral marker for empty optional
      // fields. For stage/goal it is a real value, so it must pass through
      // unchanged — translating it to empty would lose the user's pick, and
      // translating empty to the marker for these two fields would invent a
      // stage the user did not choose.
      final Profile before = base().withValue('stage', '初识');
      final Profile after = base().withValue('stage', '未填写');
      final ProfileSave save = ProfileSave(
          subjectId: 'mac-test', changes: diffProfile(before, after));

      await applySave(store, _active, save);

      expect(store.applies.single.field, 'stage');
      expect(store.applies.single.value, '未填写');
    });

    test('refuses every write when the store is not accepting, before writing any',
        () async {
      for (final MemoryStatus status
          in <MemoryStatus>[_paused, _atCapacity, _noConsent]) {
        final RecordingMemoryStore store = RecordingMemoryStore(status);
        final ProfileSave save = ProfileSave(
          subjectId: 'mac-test',
          changes: <FieldChange>[
            const FieldChange(field: 'notes', before: '', after: '新的'),
          ],
        );
        await expectLater(
          applySave(store, status, save),
          throwsA(isA<DomainException>()),
        );
        expect(store.applies, <dynamic>[],
            reason: 'a paused store must not be left half-written');
      }
    });

    test('writes zero fields and touches the store zero times on an empty save',
        () async {
      final RecordingMemoryStore store = RecordingMemoryStore(_active);
      final int n = await applySave(store, _active,
          const ProfileSave(subjectId: 'mac-test', changes: <FieldChange>[]));
      expect(n, 0);
      expect(store.applies, <dynamic>[]);
    });
  });

  group('undoSave', () {
    test('rewrites before in reverse order, so applySave then undoSave cancels',
        () async {
      final RecordingMemoryStore store = RecordingMemoryStore(_active);
      final Profile before =
          base().withValue('notes', '原本的');
      final Profile after = base()
          .withValue('label', '大王')
          .withValue('stage', '了解中')
          .withValue('notes', '旧的');
      final ProfileSave save = ProfileSave(
          subjectId: 'mac-test', changes: diffProfile(before, after));

      await applySave(store, _active, save);
      await undoSave(store, save);

      // Six applies total: 3 forward + 3 reverse, and the reverse series
      // carries the before-values in reverse field order.
      expect(store.applies, hasLength(6));
      expect(store.applies[3].field, 'notes');
      expect(store.applies[3].value, before.notes);
      expect(store.applies[4].field, 'stage');
      expect(store.applies[4].value, before.stage);
      expect(store.applies[5].field, 'display_label');
      expect(store.applies[5].value, before.label);
    });

    test('does nothing on an empty save', () async {
      final RecordingMemoryStore store = RecordingMemoryStore(_active);
      await undoSave(store, const ProfileSave(
          subjectId: 'mac-test', changes: <FieldChange>[]));
      expect(store.applies, <dynamic>[]);
    });

    test('reverting a create writes the neutral marker, not a deletion',
        () async {
      // The new memory interface dropped per-op addressing, so the domain
      // cannot *delete* a row — it can only write the previous value. For a
      // field that was new, the previous value is empty, which becomes the
      // marker. The store row stays, holding 未填写; that is the documented
      // divergence from the upstream op-id undo.
      final RecordingMemoryStore store = RecordingMemoryStore(_active);
      final Profile before = base(); // notes empty
      final Profile after = base().withValue('notes', '要紧的');
      final ProfileSave save = ProfileSave(
          subjectId: 'mac-test', changes: diffProfile(before, after));

      await applySave(store, _active, save);
      await undoSave(store, save);

      // Forward then reverse — two applies, and the reverse carries the
      // marker because the field was new (before was empty).
      expect(store.applies, hasLength(2));
      expect(store.applies.last.value, neutralMarker);
    });
  });

  group('the round-trip the bridge used to make', () {
    test('save two fields, undo, and the before-values are back in the log',
        () async {
      final RecordingMemoryStore store = RecordingMemoryStore(_active);
      final Profile before = base().withValue('my_mbti', 'INTJ');
      final Profile after =
          base().withValue('my_mbti', 'ENTP').withValue('notes', '新的');
      final ProfileSave save = ProfileSave(
          subjectId: 'mac-test', changes: diffProfile(before, after));

      await applySave(store, _active, save);
      expect(
          store.applies.map((RecordedApply a) => a.field).toList(),
          <String>['my_mbti', 'notes']);
      expect(store.applies.first.value, 'ENTP');

      await undoSave(store, save);
      // Reverse order: notes first, then my_mbti. notes was new (before empty),
      // so its revert writes the marker; my_mbti had a real before value.
      expect(store.applies[2].field, 'notes');
      expect(store.applies[2].value, neutralMarker);
      expect(store.applies[3].field, 'my_mbti');
      expect(store.applies[3].value, 'INTJ');
      expect(store.applies[3].value, 'INTJ');
    });
  });

  group('Profile.withValue', () {
    test('round-trips every field through value', () {
      // The diff and apply loops both address fields by payload key, so the
      // pair must agree on every key. This test is what fails if a field is
      // added to the payload but not to withValue.
      final Profile p = base();
      for (final String key in <String>[
        'label',
        'stage',
        'goal',
        'background',
        'my_mbti',
        'their_mbti',
        'my_score',
        'their_score',
        'notes',
      ]) {
        final Profile q = p.withValue(key, '试');
        expect(q.value(key), '试', reason: 'round-trip failed for $key');
      }
    });
  });
}