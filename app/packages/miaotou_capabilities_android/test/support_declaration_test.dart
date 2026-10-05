import 'dart:async';
import 'dart:typed_data';

import 'package:miaotou_capabilities/miaotou_capabilities.dart';
import 'package:miaotou_capabilities/testing.dart';
import 'package:miaotou_capabilities_android/miaotou_capabilities_android.dart';
import 'package:miaotou_capabilities_android/testing.dart';
import 'package:test/test.dart';

/// What the Android implementation package promises.
///
/// ADR-0009 decision 2 requires every port to answer for every member of the
/// contract. Android is the one port where the answer for all ten can eventually
/// be "yes" — it is the only one with an accessibility service behind it — so its
/// refusals are all of one kind, and the test below says so. The compiler
/// enforces that no member is missing; these tests are what make the *kind* of
/// answer observable.
void main() {
  final CapabilitySet capabilities = androidCapabilities(
    panelNative: _ProbePanelNative(),
    ingestNative: _ProbeIngestNative(),
    storageNative: _probeStorage(),
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

  test('no member is refused permanently: this is the port that can reach all ten', () async {
    final List<String> permanent = <String>[];

    for (final MapEntry<String, Future<Object?> Function(CapabilitySet)> entry
        in capabilityProbes.entries) {
      final Object outcome = await runProbe(() => entry.value(capabilities));
      if (outcome is UnsupportedError && outcome is! UnimplementedError) {
        // Both types are UnsupportedError: a not-yet refuses through the wider
        // interface, so the narrower test is the one that means "for ever".
        permanent.add('${entry.key}: ${outcome.message}');
      }
    }

    expect(
      permanent,
      isEmpty,
      reason:
          'the desktop ports throw UnsupportedError for UiTreeReader '
          'because no accessibility node tree exists there. Android has one, so '
          'a permanent refusal here would mean the port lost a capability the '
          'union baseline (ADR-0007 decision 4) says it keeps',
    );
  });

  test('the bundle is wired to this package and covers all ten', () {
    final Map<String, String> report = capabilities.describe();
    expect(report, hasLength(10));
    expect(
      report.values,
      everyElement(startsWith('Android')),
      reason:
          'an implementation package that silently wires another platform '
          'would still compile',
    );
  });
}

MemoryAndroidStorageNative _probeStorage() {
  final MemoryAndroidStorageNative storage = MemoryAndroidStorageNative(
    payload: <String, Uint8List>{
      'miaotoujunshi/references/data/trend-rules.json': Uint8List(0),
    },
  );
  storage.documents['memory.json'] = '{"consentEnabled":true}';
  return storage;
}

final class _ProbeIngestNative implements AndroidIngestNative {
  @override
  Stream<AndroidIngestEvent> get events =>
      const Stream<AndroidIngestEvent>.empty();

  @override
  Future<void> bindConversation(ConversationRef conversation) async {}

  @override
  Future<CaptureOutcome> capture({String? targetWindowId}) async =>
      const CaptureFailed(code: -1, message: 'test');

  @override
  Future<String?> findTargetWindow() async => null;

  @override
  Future<void> hideForCapture() async {}

  @override
  Future<InjectResult> inject(
    String text, {
    required InjectTarget target,
  }) async => const InjectResult.unverified('test');

  @override
  Future<ChatUiSnapshot?> readActiveChat() async => null;

  @override
  Future<List<OcrLine>> recognize(
    CaptureFrame frame, {
    required List<String> languages,
  }) async => const <OcrLine>[];

  @override
  Future<void> restoreAfterCapture() async {}

  @override
  Future<void> setOverlayFlag(AndroidOverlayFlag flag, bool value) async {}
}

final class _ProbePanelNative implements AndroidPanelNative {
  @override
  Future<void> showPanel(PanelPlacement placement) async {}

  @override
  Future<bool> hidePanel() async => false;

  @override
  Future<void> restorePanel() async {}

  @override
  Future<void> setPanelFocusable(bool value) async {}

  @override
  Stream<AndroidPanelEvent> get panelEvents =>
      const Stream<AndroidPanelEvent>.empty();
}
