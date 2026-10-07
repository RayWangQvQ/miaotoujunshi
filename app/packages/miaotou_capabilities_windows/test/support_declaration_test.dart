import 'dart:io';

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
  final Directory storage = Directory.systemTemp.createTempSync(
    'miaotou-windows-contract-',
  );
  Directory(
    '${storage.path}/miaotoujunshi/references/data',
  ).createSync(recursive: true);
  File(
    '${storage.path}/miaotoujunshi/references/data/trend-rules.json',
  ).writeAsStringSync('{}');
  final CapabilitySet capabilities = windowsCapabilities(
    native: FakeWindowsNative(),
    panelNative: FakeWindowsPanelNative(),
    executableDirectory: storage,
    applicationDataDirectory: storage,
    credentialBackend: MemoryWindowsCredentialBackend(),
  );
  final MemoryLedger memory = capabilities.memoryStore as MemoryLedger;

  setUpAll(() => memory.grantConsent(confirmed: true));
  tearDownAll(() => storage.delete(recursive: true));

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

  test('the Android permissions are refused permanently, not for now', () async {
    for (final String member in const <String>[
      'permissions.read',
      'permissions.openSettings',
    ]) {
      final Object outcome =
          await runProbe(() => capabilityProbes[member]!(capabilities));
      expect(outcome, isA<UnsupportedError>());
      expect(
        outcome,
        isNot(isA<UnimplementedError>()),
        reason: 'this port owns its own windows and reads pixels rather than an '
            'accessibility tree, so it has neither a floating grant to request '
            'nor a service to bind (ADR-0021)',
      );
    }
  });

  test('the bundle is wired to this package and covers all eleven', () {
    final Map<String, String> report = capabilities.describe();
    expect(report, hasLength(11));

    // The three storage members are `miaotou_capabilities_shared`'s, so they carry
    // the same class names here as on the other two ports — that is the point of
    // the module. Everything else has to be this port's: a bundle that silently
    // wired another platform would still compile, and this is the only place that
    // is observable.
    expect(
      report.values.where((String type) => !type.startsWith('Windows')).toSet(),
      <String>{
        'PreferenceLedger',
        'KnowledgeLedger',
        'MemoryLedger',
        'PayloadReader',
      },
      reason: 'exactly the settings, knowledge and memory documents and the '
          'payload reader come from the shared module. A fifth non-Windows name '
          'would be a shared implementation this port did not have before, and a '
          'member missing from this set would be one that had stopped being '
          'Windows\'s',
    );
  });
}
