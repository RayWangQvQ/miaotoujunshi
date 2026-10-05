import 'dart:typed_data';

import 'package:miaotou_capabilities/miaotou_capabilities.dart';
import 'package:miaotou_capabilities/testing.dart';
import 'package:test/test.dart';

void main() {
  group('the contract', () {
    test('the in-memory implementation answers every member', () async {
      final InMemoryCapabilities capabilities = InMemoryCapabilities(
        targetWindow: 'wx-1',
        files: <String, List<int>>{
          'miaotoujunshi/references/data/trend-rules.json': <int>[1, 2, 3],
        },
      );
      addTearDown(capabilities.dispose);

      final Map<String, SupportAnswer> answers = <String, SupportAnswer>{};
      for (final MapEntry<String, Future<Object?> Function(CapabilitySet)> entry
          in capabilityProbes.entries) {
        answers[entry.key] = await askCapability(() => entry.value(capabilities.toSet()));
      }

      expect(answers, hasLength(44));
      expect(
        answers.entries.where((MapEntry<String, SupportAnswer> e) =>
            e.value != SupportAnswer.answered),
        isEmpty,
        reason: 'a reference implementation that refuses is a defect in the '
            'double, not a statement about a platform',
      );
    });

    test('the two refusals are told apart by the classifier, not by the type alone', () async {
      Future<Object?> never() async =>
          unsupportedOnThisPlatform(platform: 'probe', member: 'M', reason: 'reason');
      Future<Object?> notYet() async =>
          notYetBuilt(platform: 'probe', member: 'M', ticket: '#0');

      expect(await askCapability(never), SupportAnswer.unsupported);
      expect(await askCapability(notYet), SupportAnswer.notYetBuilt);
      expect(await askCapability(() async => throw UnsupportedError('bare')),
          SupportAnswer.unsupported);
      expect(await askCapability(() async => throw StateError('defect')),
          SupportAnswer.failed);
      expect(await askCapability(() async => null), SupportAnswer.answered);

      // The trap this whole helper exists to survive: a not-yet *is* an
      // UnsupportedError, so the wider clause has to come second. If the SDK ever
      // separates the two types this canary is what says the order stopped
      // mattering — until then, swapping the clauses silently reports every
      // pending member as a permanent refusal.
      expect(
        UnimplementedError('x'),
        isA<UnsupportedError>(),
        reason: 'contract_test depends on this being true',
      );
    });

    test('a capability set names all eleven capabilities', () {
      final InMemoryCapabilities capabilities = InMemoryCapabilities();
      addTearDown(capabilities.dispose);
      expect(capabilities.toSet().describe().keys, hasLength(11));
    });
  });

  group('the values the contract carries', () {
    test('a speaker has three values, and unknown is one of them', () {
      expect(Speaker.values, hasLength(3));
      expect(Speaker.values, contains(Speaker.unknown));
    });

    test('a captured window maps back to the screen', () {
      final CaptureFrame frame = CaptureFrame(
        pixels: Uint8List.fromList(List<int>.filled(4 * 2 * 2, 0)),
        width: 200,
        height: 200,
        scaleX: 2,
        scaleY: 2,
        originX: 10,
        originY: 20,
      );

      expect(frame.region, const ScreenRect(left: 10, top: 20, right: 110, bottom: 120));
      expect(
        frame.mapToScreen(const ScreenRect(left: 0, top: 0, right: 50, bottom: 50)),
        const ScreenRect(left: 10, top: 20, right: 35, bottom: 45),
      );
    });

    test('a conversation needs both halves before it is identified', () {
      expect(const ConversationRef(packageName: 'com.tencent.mm').isIdentified, isFalse);
      expect(
        const ConversationRef(packageName: 'com.tencent.mm', title: '  ').isIdentified,
        isFalse,
      );
      expect(
        const ConversationRef(packageName: 'com.tencent.mm', title: '张三').isIdentified,
        isTrue,
      );
      expect(ConversationRef.none.isNone, isTrue);
    });

    test('a snapshot signature covers the last six lines', () {
      final ChatUiSnapshot snapshot = ChatUiSnapshot(
        conversation: ConversationRef.none,
        lines: List<ChatLine>.generate(
          8,
          (int i) => ChatLine(speaker: Speaker.other, text: 'line $i'),
        ),
        capturedAt: DateTime(2026),
      );
      final String signature = snapshot.signature();
      expect(signature, isNot(contains('line 0')));
      expect(signature, isNot(contains('line 1')));
      expect(signature, contains('line 7'));
    });

    test('a memory store refuses writes unless all three gates are open', () {
      const MemoryStatus open = MemoryStatus(
        consentEnabled: true,
        paused: false,
        atCapacity: false,
      );
      expect(open.acceptsWrites, isTrue);
      expect(
        const MemoryStatus(consentEnabled: false, paused: false, atCapacity: false)
            .acceptsWrites,
        isFalse,
      );
      expect(
        const MemoryStatus(consentEnabled: true, paused: true, atCapacity: false)
            .acceptsWrites,
        isFalse,
      );
      expect(
        const MemoryStatus(consentEnabled: true, paused: false, atCapacity: true)
            .acceptsWrites,
        isFalse,
      );
    });

    test('a permission report answers for both kinds, and inactive is one of them', () {
      const PermissionReport report = PermissionReport(
        accessibility: PermissionState.inactive,
        overlay: PermissionState.ready,
      );

      expect(report.stateOf(PermissionKind.accessibility), PermissionState.inactive);
      expect(report.stateOf(PermissionKind.overlay), PermissionState.ready);
      expect(
        PermissionState.values,
        contains(PermissionState.inactive),
        reason:
            'the whole point of three values: 勾了但没绑定 is a state a user can '
            'be looking at, and a boolean would report it as off (ADR-0021)',
      );
    });

    test('an injection result cannot claim success without reading the text back', () {
      const InjectResult verified = InjectResult.verified('你好');
      expect(verified.verifiedLanding, isTrue);
      expect(verified.observedText, '你好');
      expect(verified.reason, isNull);

      const InjectResult unverified = InjectResult.unverified('the field did not take it');
      expect(unverified.verifiedLanding, isFalse);
      expect(unverified.observedText, isEmpty);
      expect(unverified.reason, isNotNull);
    });
  });

  group('the in-memory implementations', () {
    test('a preference remembers what was written and forgets what was removed', () async {
      final InMemoryPreferences preferences = InMemoryPreferences();
      expect(await preferences.getString('a'), isNull);
      await preferences.setString('a', 'value');
      expect(await preferences.getString('a'), 'value');
      expect(await preferences.keys(), <String>{'a'});
      await preferences.remove('a');
      expect(await preferences.getString('a'), isNull);
    });

    test('a preference refuses to answer a key of the wrong type', () async {
      final InMemoryPreferences preferences =
          InMemoryPreferences(values: <String, Object>{'a': 1});
      await expectLater(preferences.getString('a'), throwsStateError);
    });

    test('listing a payload directory does not need a member list', () async {
      final InMemorySharedPayload payload = InMemorySharedPayload(
        files: <String, List<int>>{
          'miaotoujunshi/references/data/trend-rules.json': <int>[1],
          'miaotoujunshi/references/data/payload-map.json': <int>[2],
          'miaotoujunshi/references/knowledge/tone.md': <int>[3],
        },
      );
      expect(
        await payload.list('miaotoujunshi/references/data'),
        <String>['payload-map.json', 'trend-rules.json'],
      );
    });

    test('a missing payload file throws rather than returning nothing', () async {
      final InMemorySharedPayload payload = InMemorySharedPayload();
      await expectLater(payload.read('missing/file.md'), throwsStateError);
    });

    test('the memory store undoes exactly what this run wrote', () async {
      final InMemoryMemoryStore store = InMemoryMemoryStore();
      await store.apply(subjectId: 's', field: 'stage', value: 'first');
      await store.apply(subjectId: 's', field: 'goal', value: 'second');
      expect(await store.undo(), 2);
      expect(await store.show('s'), isEmpty);
    });

    test('the memory store refuses a write it was never allowed to make', () async {
      final InMemoryMemoryStore store = InMemoryMemoryStore(
        memoryStatus: const MemoryStatus(
          consentEnabled: false,
          paused: false,
          atCapacity: false,
        ),
      );
      await expectLater(
        store.apply(subjectId: 's', field: 'stage', value: 'x'),
        throwsStateError,
      );
    });

    test('a panel records the pairing around a capture', () async {
      final InMemoryFloatingPanel panel = InMemoryFloatingPanel();
      addTearDown(panel.dispose);
      await panel.show(placement: const PanelPlacement(anchor: PanelAnchor.topRight));
      await panel.hideForCapture();
      await panel.restoreAfterCapture();
      await panel.hide();
      expect(
        panel.calls,
        <String>['show', 'hideForCapture', 'restoreAfterCapture', 'hide'],
      );
    });

    test('a permission double records the pages it was asked to open', () async {
      final InMemoryPermissions permissions = InMemoryPermissions();
      expect((await permissions.read()).overlay, PermissionState.ready);

      permissions.report = const PermissionReport(
        accessibility: PermissionState.off,
        overlay: PermissionState.off,
      );
      await permissions.openSettings(PermissionKind.accessibility);

      expect((await permissions.read()).accessibility, PermissionState.off);
      expect(
        permissions.opened,
        <PermissionKind>[PermissionKind.accessibility],
        reason: 'opening a page is the only observable effect the contract has',
      );
    });
  });
}
