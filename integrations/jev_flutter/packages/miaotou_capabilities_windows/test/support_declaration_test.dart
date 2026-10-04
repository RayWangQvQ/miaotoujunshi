import 'package:miaotou_capabilities/miaotou_capabilities.dart';
import 'package:miaotou_capabilities/testing.dart';
import 'package:miaotou_capabilities_windows/miaotou_capabilities_windows.dart';
import 'package:miaotou_capabilities_windows/testing.dart';
import 'package:test/test.dart';

/// What the Windows implementation package promises.
///
/// ADR-0009 decision 2 requires every port to answer for every member of the
/// contract, and it draws a line inside the word "refuse": a member the platform
/// can never implement throws `UnsupportedError`, a member this milestone has not
/// built yet throws `UnimplementedError` naming the ticket that removes it, and
/// neither is a silent null. The compiler enforces the first half — the package
/// does not build while a member is missing — and these tests are what make the
/// second half observable.
void main() {
  final CapabilitySet capabilities = windowsCapabilities(
    native: FakeWindowsNative(),
  );

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
      reason:
          'a member must either do the work or refuse it as one of the two '
          'refusals. Returning null, an empty collection or a default would pass '
          'the compiler and reach the user as a blank panel (ADR-0009)',
    );
  });

  test('a not-yet refusal names the ticket that removes it', () async {
    final List<String> silent = <String>[];

    for (final MapEntry<String, Future<Object?> Function(CapabilitySet)> entry
        in capabilityProbes.entries) {
      final Object outcome = await runProbe(() => entry.value(capabilities));
      if (outcome is UnimplementedError &&
          !'${outcome.message}'.contains('#')) {
        silent.add('${entry.key}: ${outcome.message}');
      }
    }

    expect(
      silent,
      isEmpty,
      reason:
          'a refusal that does not say who owns the work leaves the next '
          'reader unable to tell a permanent statement from an open to-do',
    );
  });

  test('the accessibility tree is refused permanently, not for now', () async {
    for (final String member in const <String>[
      'uiTreeReader.readActiveChat',
      'uiTreeReader.snapshots',
    ]) {
      final Object outcome = await runProbe(
        () => capabilityProbes[member]!(capabilities),
      );
      expect(outcome, isA<UnsupportedError>());
      expect(
        outcome,
        isNot(isA<UnimplementedError>()),
        reason:
            'Windows reads pixels, not accessibility nodes. This port will '
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
      everyElement(startsWith('Windows')),
      reason:
          'an implementation package that silently wires another platform '
          'would still compile',
    );
  });
}
