import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miaotou_app/src/app.dart';
import 'package:miaotou_capabilities/miaotou_capabilities.dart';
import 'package:miaotou_capabilities/testing.dart';
import 'package:miaotou_capabilities_macos/miaotou_capabilities_macos.dart';

/// The point of ADR-0009 is that nothing above the contract can tell which port
/// it is on. These tests are what makes that true rather than intended: they run
/// **the whole application** — the same `MiaotouApp` that `main.dart` starts —
/// against three different capability sets, with no device, no window server and
/// no chat application anywhere.
void main() {
  Future<void> pumpApplication(
    WidgetTester tester,
    CapabilitySet capabilities,
  ) async {
    // A tall surface so every row of the report is laid out; a `ListView` only
    // builds what it can show.
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MiaotouApp(capabilities: capabilities));
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

    await pumpApplication(tester, capabilities.toSet());

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
    await pumpApplication(tester, macosCapabilities());

    expect(find.textContaining('已应答 0'), findsOneWidget);
    expect(find.textContaining('永久不支持 2'), findsOneWidget);
    expect(find.textContaining('尚未实现 9'), findsOneWidget);
    expect(find.text('尚未实现'), findsNWidgets(9));

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

    await pumpApplication(
      tester,
      CapabilitySet(
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
