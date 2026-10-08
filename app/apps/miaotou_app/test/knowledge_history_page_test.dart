import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miaotou_app/src/design/copy.dart';
import 'package:miaotou_app/src/design/theme.dart';
import 'package:miaotou_app/src/shell/knowledge_page.dart';
import 'package:miaotou_capabilities/miaotou_capabilities.dart';
import 'package:miaotou_capabilities/testing.dart';

/// The conversation history page: one contact's log, oldest first, separated by
/// day, loaded in pages rather than flattened into the card it came from.
void main() {
  KnowledgeContact contact({String id = 'c1'}) => KnowledgeContact(
    id: id,
    name: '张三',
    updatedAt: DateTime.utc(2026),
    packageNames: <String>['com.ss.android.ugc.aweme'],
    packageAppNames: <String, String>{
      'com.ss.android.ugc.aweme': '抖音',
    },
  );

  Future<InMemoryKnowledgeStore> storeWithLog(
    List<KnowledgeLogEntry> entries, {
    String contactId = 'c1',
  }) async {
    final InMemoryKnowledgeStore store = InMemoryKnowledgeStore(
      contacts: <KnowledgeContact>[contact(id: contactId)],
    );
    await store.appendLog(contactId, entries);
    return store;
  }

  Widget wrap(KnowledgeStore store, KnowledgeContact target) => CopyScope(
    copy: AppCopy.zh,
    child: MaterialApp(
      theme: buildTheme(),
      home: KnowledgeHistoryPage(store: store, contact: target),
    ),
  );

  testWidgets('separates the log by day', (WidgetTester tester) async {
    final InMemoryKnowledgeStore store = await storeWithLog(<KnowledgeLogEntry>[
      KnowledgeLogEntry(
        speaker: Speaker.other,
        text: '早',
        timestamp: DateTime(2026, 10, 8, 9),
        packageName: 'com.ss.android.ugc.aweme',
      ),
      KnowledgeLogEntry(
        speaker: Speaker.me,
        text: '在吗',
        timestamp: DateTime(2026, 10, 8, 9, 5),
        packageName: 'com.ss.android.ugc.aweme',
      ),
      KnowledgeLogEntry(
        speaker: Speaker.other,
        text: '昨天的事',
        timestamp: DateTime(2026, 10, 7, 20),
        packageName: 'com.ss.android.ugc.aweme',
      ),
    ]);

    await tester.pumpWidget(wrap(store, contact()));
    await tester.pumpAndSettle();

    // Two distinct days, each headed once.
    expect(find.text('10月8日'), findsOneWidget);
    expect(find.text('10月7日'), findsOneWidget);
    expect(find.text('对方：早'), findsOneWidget);
    expect(find.text('我：在吗'), findsOneWidget);
  });

  testWidgets('opens from the contact card and shows a back title', (
    WidgetTester tester,
  ) async {
    final InMemoryKnowledgeStore store = await storeWithLog(<KnowledgeLogEntry>[
      KnowledgeLogEntry(
        speaker: Speaker.other,
        text: '在吗',
        timestamp: DateTime(2026, 10, 8, 9),
        packageName: 'com.ss.android.ugc.aweme',
      ),
    ]);

    await tester.pumpWidget(
      CopyScope(
        copy: AppCopy.zh,
        child: MaterialApp(
          theme: buildTheme(),
          home: Scaffold(
            body: KnowledgePage(store: store, payload: const _NoPayload()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Expand the contact, then enter the history page.
    await tester.tap(find.text('张三'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('查看历史'));
    await tester.pumpAndSettle();

    expect(find.text('聊天记录'), findsOneWidget);
    expect(find.text('对方：在吗'), findsOneWidget);
  });
}

/// A payload that answers with nothing; the history page does not read it.
class _NoPayload implements SharedPayload {
  const _NoPayload();

  @override
  Future<List<String>> list(String repoRelativeDir) async => const <String>[];

  @override
  Future<Uint8List> read(String repoRelativePath) async =>
      throw StateError('nothing');
}
