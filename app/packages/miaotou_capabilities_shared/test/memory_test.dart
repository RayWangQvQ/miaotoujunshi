import 'dart:convert';
import 'dart:io';

import 'package:miaotou_capabilities/miaotou_capabilities.dart';
import 'package:miaotou_capabilities_shared/miaotou_capabilities_shared.dart';
import 'package:test/test.dart';

import 'fake_documents.dart';

/// The remembered-profile store, in one suite for all three ports.
///
/// `goutoujunshi/scripts/memory_store.py` is the semantic reference and the
/// numbers below are copied from the top of it, so the assertions that name a
/// constant are also the record of where the number came from. The two places
/// this implementation deliberately diverges from the script are pinned at the
/// end of the relevant group, with the ADR-0010 decision that licenses them.
void main() {
  late FakeDocuments documents;
  late MemoryLedger memory;

  setUp(() {
    documents = FakeDocuments();
    memory = MemoryLedger(documents);
  });

  group('the consent gate', () {
    test('a store nobody has consented to writes nothing and reads nothing',
        () async {
      final MemoryStatus status = await memory.status();

      expect(status.consentEnabled, isFalse);
      expect(status.acceptsWrites, isFalse);
      await expectLater(
        memory.apply(subjectId: 's1', field: 'stage', value: '了解中'),
        throwsStateError,
      );
      expect(
        await memory.show('s1'),
        isEmpty,
        reason: 'the contract says "with no consent nothing may be read out '
            'either", which is narrower than upstream: its `command_show` read '
            'the table regardless of the flag',
      );
    });

    test('consent is required to be confirmed, mirroring the upstream --confirm',
        () async {
      await expectLater(
        memory.grantConsent(confirmed: false),
        throwsStateError,
        reason: '"enable" is the one action here that starts storing something '
            'about a person, and upstream refused to do it without an explicit '
            'confirmation',
      );
    });

    test('with consent, a field written is a field read back', () async {
      await memory.grantConsent(confirmed: true);
      await memory.apply(subjectId: 's1', field: 'display_label', value: '小王');

      final List<MemoryRecord> shown = await memory.show('s1');

      expect(shown, hasLength(1));
      expect(shown.single.subjectId, 's1');
      expect(shown.single.field, 'display_label');
      expect(shown.single.value, '小王');
    });

    test('a paused store refuses writes but still reads', () async {
      await memory.grantConsent(confirmed: true);
      await memory.apply(subjectId: 's1', field: 'display_label', value: '小王');
      await memory.setPaused(paused: true);

      final MemoryStatus status = await memory.status();
      expect(status.paused, isTrue);
      expect(status.acceptsWrites, isFalse);
      await expectLater(
        memory.apply(subjectId: 's1', field: 'stage', value: '了解中'),
        throwsStateError,
      );
      expect(
        await memory.show('s1'),
        hasLength(1),
        reason: 'pausing is about writing; a user who paused still wants to see '
            'what is already there',
      );
    });

    test('pausing a store that was never enabled is refused', () async {
      await expectLater(memory.setPaused(paused: true), throwsStateError);
    });

    test('granting consent clears a pause, as upstream\'s enable did', () async {
      await memory.grantConsent(confirmed: true);
      await memory.setPaused(paused: true);

      await memory.grantConsent(confirmed: true);

      expect(
        (await memory.status()).paused,
        isFalse,
        reason: 'the user was asked again and said yes, so a pause from before '
            'the question is not a refusal of the answer',
      );
    });

    test('revoking consent stops writes and stops reading out', () async {
      await memory.grantConsent(confirmed: true);
      await memory.apply(subjectId: 's1', field: 'display_label', value: '小王');

      await memory.revokeConsent();

      final MemoryStatus status = await memory.status();
      expect(status.consentEnabled, isFalse);
      expect(status.acceptsWrites, isFalse);
      expect(
        await memory.show('s1'),
        isEmpty,
        reason: 'a store that will not write a row without consent has no '
            'business handing it to a prompt without consent',
      );
    });

    test('revoking keeps what was already stored rather than deleting it',
        () async {
      // Upstream's `revoke` without `--delete`. A user who turns the feature off
      // and a user who wants their data gone are different requests, and only
      // `clear` answers the second.
      await memory.grantConsent(confirmed: true);
      await memory.apply(subjectId: 's1', field: 'stage', value: '了解中');
      await memory.revokeConsent();

      expect(
        documents.raw('memory.json'),
        contains('了解中'),
        reason: 'revoking closes the store; it does not empty it',
      );
    });
  });

  group('undo', () {
    test('rolls back exactly this run and reports how many', () async {
      await memory.grantConsent(confirmed: true);
      await memory.apply(subjectId: 's1', field: 'display_label', value: '小王');
      await memory.apply(subjectId: 's1', field: 'stage', value: '了解中');

      final int rolledBack = await memory.undo();

      expect(rolledBack, 2);
      expect(await memory.show('s1'), isEmpty);
    });

    test('unwinds a run back to where it started, not one step back', () async {
      await memory.grantConsent(confirmed: true);
      await memory.apply(subjectId: 's1', field: 'stage', value: '了解中');
      // A second write to the same field within the same run.
      await memory.apply(subjectId: 's1', field: 'stage', value: '约会中');
      expect((await memory.show('s1')).single.value, '约会中');

      final int rolledBack = await memory.undo();

      expect(rolledBack, 2);
      expect(
        await memory.show('s1'),
        isEmpty,
        reason: 'undo rolls back every write since the store was opened, so the '
            'field is gone rather than showing an intermediate value — the run\'s '
            'starting state had no stage at all',
      );
    });

    test('restores a value that predates the stack', () async {
      // A row that was already in the document when this store was opened: the
      // state a user is in after an upgrade, or after a `clear` that was
      // followed by a re-population elsewhere. Seeded by hand because no sequence
      // of `apply` calls on one store produces it.
      //
      // This is also the test that makes the recorded `before` value
      // load-bearing: without it, unwinding this write would *delete* the row
      // rather than put 了解中 back, and the value the user had before this run
      // would be gone.
      documents.put(
        'memory.json',
        jsonEncode(<String, Object?>{
          'policyVersion': MemoryLedger.policyVersion,
          'consentEnabled': true,
          'paused': false,
          'records': <Map<String, Object?>>[
            <String, Object?>{
              'subjectId': 's1',
              'field': 'stage',
              'value': '了解中',
            },
          ],
        }),
      );

      await memory.apply(subjectId: 's1', field: 'stage', value: '约会中');
      expect((await memory.show('s1')).single.value, '约会中');

      await memory.undo();

      expect(
        (await memory.show('s1')).single.value,
        '了解中',
        reason: 'the undo entry recorded the value before the write, so a field '
            'this run overwrote comes back rather than disappearing',
      );
    });

    test('undo with nothing to undo is zero, not an error', () async {
      await memory.grantConsent(confirmed: true);

      expect(await memory.undo(), 0);
    });

    test('reaches only the writes made since the store was opened', () async {
      // The one place this implementation diverges from the two desktop ports,
      // and the contract settles it in its own words: `undo` "rolls back every
      // write made **since this store was opened**", and the run boundary is the
      // store's. A stack written into the document would also reach a previous
      // run's writes, which is a different and larger claim.
      final MemoryLedger first = MemoryLedger(documents);
      await first.grantConsent(confirmed: true);
      await first.apply(subjectId: 's1', field: 'stage', value: '了解中');

      final MemoryLedger second = MemoryLedger(documents);
      await second.apply(subjectId: 's1', field: 'notes', value: '不吃香菜');
      expect(await second.undo(), 1);

      expect(
        (await second.show('s1')).map((MemoryRecord record) => record.field),
        <String>['stage'],
        reason: 'the first store wrote 了解中 and this one must not be able to '
            'unwind it; a stack in the document would have reached it',
      );
    });

    test('clear takes the stack with it', () async {
      await memory.grantConsent(confirmed: true);
      await memory.apply(subjectId: 's1', field: 'stage', value: '了解中');

      await memory.clear();

      expect(
        await memory.undo(),
        0,
        reason: 'a store that has forgotten every row has nothing left for an '
            'undo to reach, and counting writes it did not unwind would be a '
            'number that means nothing',
      );
    });

    test('the stack is bounded and keeps the newest entries', () async {
      await memory.grantConsent(confirmed: true);
      // One more than the bound, so the oldest must fall off the end.
      for (int i = 0; i <= MemoryLedger.maxOperations; i++) {
        await memory.apply(subjectId: 's1', field: 'field$i', value: 'v$i');
      }

      final int rolledBack = await memory.undo();

      expect(rolledBack, MemoryLedger.maxOperations);
      final List<MemoryRecord> left = await memory.show('s1');
      expect(left, hasLength(1));
      expect(
        left.single.field,
        'field0',
        reason: 'the oldest operation fell off the stack, so its write survives — '
            'MAX_OPERATIONS in the upstream script, and dropping the oldest '
            'rather than refusing is what it did',
      );
    });
  });

  group('what may be stored', () {
    test('the value cap is upstream MAX_VALUE_CHARS', () async {
      await memory.grantConsent(confirmed: true);

      await memory.apply(
        subjectId: 's1',
        field: 'notes',
        value: 'x' * MemoryLedger.maxValueChars,
      );
      await expectLater(
        memory.apply(
          subjectId: 's1',
          field: 'notes',
          value: 'x' * (MemoryLedger.maxValueChars + 1),
        ),
        throwsStateError,
        reason: '200 is MAX_VALUE_CHARS in goutoujunshi/scripts/memory_store.py, '
            'and the cap is what stops a transcript being written into `notes`',
      );
    });

    test('an empty value is refused, which is why 未填写 exists', () async {
      await memory.grantConsent(confirmed: true);

      await expectLater(
        memory.apply(subjectId: 's1', field: 'notes', value: '   '),
        throwsStateError,
        reason: 'the domain writes 未填写 for "unknown" before calling apply; an '
            'empty value here means a caller skipped that translation, and '
            'storing it would make "unset" and "set to nothing" the same row',
      );
    });

    test('a control character is refused', () async {
      await memory.grantConsent(confirmed: true);

      await expectLater(
        memory.apply(subjectId: 's1', field: 'notes', value: '正常\u0007文本'),
        throwsStateError,
        reason: 'a control character is what a terminal escape looks like when it '
            'comes back out in a prompt',
      );
    });

    test('a subject or a field name is required', () async {
      await memory.grantConsent(confirmed: true);

      await expectLater(
        memory.apply(subjectId: '   ', field: 'stage', value: '了解中'),
        throwsStateError,
      );
      await expectLater(
        memory.apply(subjectId: 's1', field: '', value: '了解中'),
        throwsStateError,
      );
    });

    test('the capacity bound is upstream MAX_ROWS and it refuses rather than '
        'forgetting', () async {
      await memory.grantConsent(confirmed: true);
      for (int i = 0; i < MemoryLedger.maxRows; i++) {
        await memory.apply(subjectId: 's$i', field: 'stage', value: '了解中');
      }

      final MemoryStatus status = await memory.status();
      expect(status.atCapacity, isTrue);
      expect(status.acceptsWrites, isFalse);
      await expectLater(
        memory.apply(subjectId: 'overflow', field: 'stage', value: '了解中'),
        throwsStateError,
        reason: 'upstream pruned the oldest event rows to make room; with the '
            'scope taxonomy gone there is nothing to prune preferentially, and an '
            'unrecoverable-by-surprise store is the better failure for a record '
            'of a person',
      );
    });

    test('updating a field the store already holds is not a new row', () async {
      await memory.grantConsent(confirmed: true);
      // Fill the store to exactly the bound.
      for (int i = 0; i < MemoryLedger.maxRows; i++) {
        await memory.apply(subjectId: 's$i', field: 'stage', value: '了解中');
      }

      // At capacity, and yet this is an update rather than an insert.
      await memory.apply(subjectId: 's0', field: 'stage', value: '约会中');

      expect(
        (await memory.show('s0')).single.value,
        '约会中',
        reason: 'an update does not grow the store, so it must not be refused by '
            'the capacity bound',
      );
    });
  });

  group('the document', () {
    test('records the policy version it was written by', () async {
      await memory.grantConsent(confirmed: true);

      final Map<String, Object?> document =
          jsonDecode(documents.raw('memory.json')!) as Map<String, Object?>;

      expect(
        document['policyVersion'],
        MemoryLedger.policyVersion,
        reason: 'POLICY_VERSION upstream; written rather than assumed so a later '
            'format change can be recognised instead of guessed at',
      );
    });

    test('holds no undo key, because the run boundary is the store\'s', () async {
      await memory.grantConsent(confirmed: true);
      await memory.apply(subjectId: 's1', field: 'stage', value: '了解中');

      final Map<String, Object?> document =
          jsonDecode(documents.raw('memory.json')!) as Map<String, Object?>;

      expect(
        document.containsKey('undo'),
        isFalse,
        reason: 'a persisted stack outlives the store and so rolls back a '
            'previous run; see the class comment and ADR-0009',
      );
    });

    test('a store survives the process, consent and all', () async {
      await memory.grantConsent(confirmed: true);
      await memory.apply(subjectId: 's1', field: 'display_label', value: '小王');
      await memory.apply(subjectId: 's1', field: 'stage', value: '了解中');

      final MemoryLedger reopened = MemoryLedger(documents);

      expect((await reopened.status()).consentEnabled, isTrue);
      expect(await reopened.show('s1'), hasLength(2));
    });

    test('clear empties the store and closes it again', () async {
      await memory.grantConsent(confirmed: true);
      await memory.apply(subjectId: 's1', field: 'stage', value: '了解中');

      await memory.clear();

      final MemoryStatus status = await memory.status();
      expect(status.consentEnabled, isFalse);
      expect(await memory.show('s1'), isEmpty);
    });

    test('a records entry missing a field refuses the document', () async {
      // The three ports disagreed and neither answer was good: Android kept the
      // well-formed rows and silently dropped the rest, the two desktop ports
      // kept any map and threw at the point a field was read as a String — far
      // from the cause. This is the answer the codebase already gives for a
      // damaged document: refuse it, name what is wrong, leave the file where a
      // reader can look at it.
      documents.put(
        'memory.json',
        jsonEncode(<String, Object?>{
          'consentEnabled': true,
          'records': <Object?>[
            <String, Object?>{'subjectId': 's1', 'field': 'stage'},
          ],
        }),
      );

      await expectLater(memory.show('s1'), throwsStateError);
    });

    test('records that are not a list, or not objects, are refused', () async {
      for (final Object? corrupt in <Object?>[
        <String, Object?>{'a': 1},
        <Object?>['just a string'],
      ]) {
        documents.put(
          'memory.json',
          jsonEncode(<String, Object?>{'consentEnabled': true, 'records': corrupt}),
        );

        await expectLater(memory.show('s1'), throwsStateError);
      }
    });

    test('status refuses a damaged document too, rather than miscounting it',
        () async {
      // A `status` that counted a malformed row as a row would report a capacity
      // the store cannot actually serve.
      documents.put(
        'memory.json',
        jsonEncode(<String, Object?>{
          'records': <Object?>[
            <String, Object?>{'subjectId': 's1'},
          ],
        }),
      );

      await expectLater(memory.status(), throwsStateError);
    });
  });

  test('the document is named memory.json', () {
    expect(MemoryLedger.fileName, 'memory.json');
  });

  test('the numbers and the retained promises match the policy fixture', () {
    // `goutoujunshi/scripts/memory_store.py` is the semantic reference, and this
    // fixture is the list of what of it this store kept. It came from the Android
    // package, which was the only port with a memory store of its own before this
    // module existed; the four numbers and the four promises are the same for all
    // three ports now, so the fixture lives beside the module that owns them.
    final Map<String, Object?> fixture =
        (jsonDecode(
                  File('test/fixtures/memory_policy.json').readAsStringSync(),
                )
                as Map<Object?, Object?>)
            .cast<String, Object?>();

    expect(MemoryLedger.maxValueChars, fixture['maxValueChars']);
    expect(MemoryLedger.maxRows, fixture['maxRows']);
    expect(MemoryLedger.maxOperations, fixture['maxOperations']);
    expect(MemoryLedger.policyVersion, fixture['policyVersion']);
    expect(
      fixture['retainedSafetySemantics'],
      <String>['consent', 'pause', 'capacity', 'undo-within-open-store'],
      reason: 'ADR-0010 decision 2 keeps exactly these four of upstream\'s safety '
          'promises, and drops the per-scope quota table, the five source types '
          'and the operation-id addressing',
    );
  });
}
