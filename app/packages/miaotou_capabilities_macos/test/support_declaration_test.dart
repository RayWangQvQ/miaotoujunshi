import 'package:flutter_test/flutter_test.dart';
import 'package:miaotou_capabilities/miaotou_capabilities.dart';
import 'package:miaotou_capabilities/testing.dart';
import 'package:miaotou_capabilities_macos/miaotou_capabilities_macos.dart';
import 'package:miaotou_capabilities_macos/testing.dart';



/// What the macOS implementation package promises.
///
/// ADR-0009 decision 2 requires every port to answer for every member of the
/// contract, and it draws a line inside the word "refuse": a member the platform
/// can never implement throws `UnsupportedError`, a member this milestone has not
/// built yet throws `UnimplementedError` naming the ticket that removes it, and
/// neither is a silent null. The compiler enforces the first half — the package
/// does not build while a member is missing — and these tests are what make the
/// second half observable.
void main() {
  // The scripted Mac, not a real one: this file is about what the port *answers*,
  // and a member that reached a method channel here would fail for want of a
  // plugin rather than for want of an implementation. `native_channel_test.dart`
  // is where the channel itself is exercised.
  //
  // The storage half gets real temporary directories (#15). A bare
  // `FakeMacosNative()` refuses to say where the payload or the container is —
  // deliberately, so a test cannot read the developer's own machine — which means
  // the five storage members would all throw a `StateError` here and be reported
  // as defects. They answer, into a directory that is deleted afterwards.
  final FakeMacosNative native =
      fakeMacosWithTemporaryStorage(withPayload: true);
  final CapabilitySet capabilities = macosCapabilities(native: native);

  // `memoryStore.apply` refuses without consent, and it must: ADR-0010 decision 2
  // keeps the consent gate as one of this product's own promises, and a store that
  // writes a row about a person before anybody agreed is the failure the gate
  // exists to prevent. The manifest probes `apply` on a fresh store, so the gate
  // is opened here first — otherwise this file would report a correct refusal as
  // a defect, and the cheapest way to make that go away would be to delete the
  // gate.
  //
  // The cast is the honest shape of the thing: `MemoryStore` has no member for
  // "the user agreed", so the switch is only reachable on the concrete type. That
  // gap is noted in `memory.dart` and belongs to a ticket above this one.
  final MacosMemoryStore memory = capabilities.memoryStore as MacosMemoryStore;

  setUpAll(() async {
    await memory.grantConsent(confirmed: true);
  });

  tearDownAll(() async {
    await native.close();
    deleteTemporaryStorage(native);
  });

  test('the memory store refuses to write before the user has agreed', () async {
    // Asserted here rather than left implicit, because the gate is the one member
    // of the contract whose correct answer *is* a refusal, and a reader of this
    // file should not have to know that to understand why the cast above exists.
    final MacosMemoryStore virgin =
        MacosMemoryStore.inContainer(fakeMacosWithTemporaryStorage());

    expect((await virgin.status()).acceptsWrites, isFalse);
    await expectLater(
      virgin.apply(subjectId: 'probe', field: 'stage', value: '了解中'),
      throwsStateError,
    );
    expect(await virgin.show('probe'), isEmpty);
  });

  test('every member of the contract answers for itself', () async {
    final List<String> defects = <String>[];

    for (final MapEntry<String, Future<Object?> Function(CapabilitySet)> entry
        in capabilityProbes.entries) {
      final Object outcome = await runProbe(() => entry.value(capabilities));
      if (outcome == probeReturned ||
          outcome is UnsupportedError ||
          outcome is UnimplementedError) {
        continue;
      }
      defects.add('${entry.key} threw ${outcome.runtimeType}: $outcome');
    }

    expect(
      defects,
      isEmpty,
      reason: 'a member must either do the work or refuse it as one of the two '
          'refusals. Returning null, an empty collection or a default would pass '
          'the compiler and reach the user as a blank panel (ADR-0009)',
    );
  });

  test('a not-yet refusal names the ticket that removes it', () async {
    final List<String> silent = <String>[];

    for (final MapEntry<String, Future<Object?> Function(CapabilitySet)> entry
        in capabilityProbes.entries) {
      final Object outcome = await runProbe(() => entry.value(capabilities));
      if (outcome is UnimplementedError && !'${outcome.message}'.contains('#')) {
        silent.add('${entry.key}: ${outcome.message}');
      }
    }

    expect(
      silent,
      isEmpty,
      reason: 'a refusal that does not say who owns the work leaves the next '
          'reader unable to tell a permanent statement from an open to-do',
    );
  });

  test('the accessibility tree is refused permanently, not for now', () async {
    for (final String member in const <String>[
      'uiTreeReader.readActiveChat',
      'uiTreeReader.snapshots',
    ]) {
      final Object outcome =
          await runProbe(() => capabilityProbes[member]!(capabilities));
      expect(outcome, isA<UnsupportedError>());
      expect(
        outcome,
        isNot(isA<UnimplementedError>()),
        reason: 'macOS reads pixels, not accessibility nodes. This port will '
            'never implement UiTreeReader: the refusal is the design. A not-yet '
            'is also an UnsupportedError, so the narrower assertion is the one '
            'that says which refusal this is',
      );
    }
  });

  test('the bundle is wired to this package and covers all ten', () {
    final Map<String, String> report = capabilities.describe();
    expect(report, hasLength(10));
    expect(
      report.values,
      everyElement(startsWith('Macos')),
      reason: 'an implementation package that silently wires another platform '
          'would still compile',
    );
  });
}
