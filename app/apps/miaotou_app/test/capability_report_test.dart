import 'package:flutter_test/flutter_test.dart';
import 'package:miaotou_capabilities/miaotou_capabilities.dart';
import 'package:miaotou_capabilities/testing.dart';
import 'package:miaotou_capabilities_macos/miaotou_capabilities_macos.dart';
import 'package:miaotou_capabilities_macos/testing.dart';

import 'support/harness.dart';

/// The point of ADR-0009 is that nothing above the contract can tell which port
/// it is on. These tests are what makes that true rather than intended: they run
/// **the whole application** — the same `MiaotouApp` that `main.dart` starts —
/// against three different capability sets, with no device, no window server and
/// no chat application anywhere.
///
/// They reach the report by navigating to it, which is also the first half of
/// #11's routing criterion: settings is a destination in the main window and the
/// report is a route pushed onto the same navigator, never a window of its own
/// (ADR-0012).
void main() {
  Future<void> openDiagnostics(WidgetTester tester) async {
    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('能力自检'));
    await tester.pumpAndSettle();
  }

  testWidgets('the application runs on an in-memory capability set', (
    WidgetTester tester,
  ) async {
    final InMemoryCapabilities capabilities = InMemoryCapabilities(
      files: <String, List<int>>{
        'miaotoujunshi/references/data/trend-rules.json': <int>[1, 2, 3],
      },
    );
    addTearDown(capabilities.dispose);

    final AppHarness harness = AppHarness(capabilities: capabilities.toSet());
    await pumpApplication(tester, harness);
    await openDiagnostics(tester);

    expect(find.textContaining('已应答 11'), findsOneWidget);
    expect(find.textContaining('异常 0'), findsOneWidget);
    expect(find.text('已应答'), findsNWidgets(11));

    // The screen names the implementations it was handed, which is only possible
    // if it never went looking for its own.
    expect(find.textContaining('InMemoryScreenCapture'), findsOneWidget);

    // The one member no start-up may ask is reported as such rather than omitted.
    expect(find.text('textInject.inject'), findsOneWidget);
    expect(find.textContaining('未询问'), findsWidgets);
  });

  testWidgets('a real platform package reports its refusals through the same shell', (
    WidgetTester tester,
  ) async {
    // Over the scripted Mac rather than a live channel: this file is about the
    // report, and a member that reached a method channel here would be answering
    // "no plugin registered" instead of saying anything about the port.
    // The storage half needs real temporary directories, and the payload half
    // needs a payload to read: the fake refuses to invent either, so that a test
    // cannot quietly read the developer's own container. #15 is why this is no
    // longer a bare `FakeMacosNative()`.
    final FakeMacosNative native =
        fakeMacosWithTemporaryStorage(withPayload: true);
    addTearDown(() async {
      await native.close();
      deleteTemporaryStorage(native);
    });

    final AppHarness harness = AppHarness(
      capabilities: macosCapabilities(native: native),
    );
    await pumpApplication(tester, harness);
    await openDiagnostics(tester);

    // What start-up is allowed to ask, on this port, after #15 — which is to say
    // every member except the one that writes into somebody else's window:
    //   answered     — the target window, the recogniser, the panel's event
    //                  stream, and all six storage probes: the payload listing,
    //                  the preferences and secret key sets, the knowledge notes
    //                  and contacts, and the memory store's status
    //   unsupported  — the accessibility tree, permanently (ADR-0009 decision 2)
    //   not yet built— nothing; #15 was the last ticket to own a refusal here
    //   unasked      — `textInject.inject`: start-up never writes into somebody
    //                  else's window, so asking would be the defect
    //
    // The 3/2/6/1 of #14 became 9/2/0/1. The six that used to be "not yet built"
    // now answer, which is the whole of this ticket.
    expect(find.textContaining('已应答 9'), findsOneWidget);
    expect(find.textContaining('永久不支持 2'), findsOneWidget);
    expect(find.textContaining('尚未实现 0'), findsOneWidget);
    expect(find.textContaining('异常 0'), findsOneWidget);
    expect(find.text('已应答'), findsNWidgets(9));
    expect(find.text('textInject.inject'), findsOneWidget);
    expect(find.textContaining('未询问 1'), findsOneWidget);

    // The two permanent refusals are the accessibility tree, exactly as ADR-0009
    // decision 2 describes it.
    expect(find.text('uiTreeReader.readActiveChat'), findsOneWidget);
    expect(find.text('uiTreeReader.snapshots'), findsOneWidget);
  });

  testWidgets('a defect is reported rather than swallowed', (
    WidgetTester tester,
  ) async {
    final InMemoryCapabilities capabilities = InMemoryCapabilities();
    addTearDown(capabilities.dispose);
    final CapabilitySet healthy = capabilities.toSet();

    final AppHarness harness = AppHarness(
      capabilities: CapabilitySet(
        screenCapture: healthy.screenCapture,
        uiTreeReader: healthy.uiTreeReader,
        ocr: healthy.ocr,
        textInject: healthy.textInject,
        floatingPanel: healthy.floatingPanel,
        sharedPayload: healthy.sharedPayload,
        preferences: healthy.preferences,
        secretStore: healthy.secretStore,
        knowledgeStore: healthy.knowledgeStore,
        memoryStore: const _BrokenMemoryStore(),
      ),
    );
    await pumpApplication(tester, harness);
    await openDiagnostics(tester);

    expect(find.textContaining('异常 1'), findsOneWidget);
    expect(find.textContaining('已应答 10'), findsOneWidget);
    expect(find.text('异常'), findsOneWidget);
  });
}

/// A store whose one probed member throws something that is neither of the two
/// refusals — the shape a real defect takes.
final class _BrokenMemoryStore implements MemoryStore {
  const _BrokenMemoryStore();

  @override
  Future<MemoryStatus> status() async => throw StateError('the store fell over');

  @override
  Future<List<MemoryRecord>> show(String subjectId) async =>
      const <MemoryRecord>[];

  @override
  Future<void> apply({
    required String subjectId,
    required String field,
    required String value,
  }) async {}

  @override
  Future<int> undo() async => 0;
}
