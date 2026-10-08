import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miaotou_app/src/design/copy.dart';
import 'package:miaotou_app/src/design/theme.dart';
import 'package:miaotou_app/src/shell/knowledge_page.dart';
import 'package:miaotou_capabilities/miaotou_capabilities.dart';
import 'package:miaotou_capabilities/testing.dart';
import 'package:miaotou_domain/miaotou_domain.dart';

/// The knowledge base page: contacts grouped by the app name a person reads,
/// and an edit entry that fills a contact's fields in — with the stage/goal
/// enum offered as a dropdown from the shared payload, and a helper line under
/// every field.
void main() {
  final Directory root = _repositoryRoot();
  final InMemoryCapabilities capabilities = InMemoryCapabilities(
    contacts: <KnowledgeContact>[
      KnowledgeContact(
        id: 'c1',
        name: '张三',
        updatedAt: DateTime.utc(2026),
        packageNames: <String>['com.ss.android.ugc.aweme'],
        packageAppNames: <String, String>{
          'com.ss.android.ugc.aweme': '抖音',
        },
      ),
    ],
    files: _payloadFiles(root),
  );

  Widget wrap(CapabilitySet set) => CopyScope(
    copy: AppCopy.zh,
    child: MaterialApp(
      theme: buildTheme(),
      home: Scaffold(
        body: KnowledgePage(store: set.knowledgeStore, payload: set.sharedPayload),
      ),
    ),
  );

  testWidgets('groups by the app display name, not the package id', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(wrap(capabilities.toSet()));
    await tester.pumpAndSettle();

    expect(find.text('抖音'), findsOneWidget);
    expect(find.text('com.ss.android.ugc.aweme'), findsNothing);
  });

  testWidgets('a known package with no recorded name shows the built-in name', (
    WidgetTester tester,
  ) async {
    final InMemoryCapabilities bare = InMemoryCapabilities(
      contacts: <KnowledgeContact>[
        KnowledgeContact(
          id: 'c2',
          name: '李四',
          updatedAt: DateTime.utc(2026),
          packageNames: <String>['com.ss.android.ugc.aweme'],
        ),
      ],
      files: _payloadFiles(root),
    );
    await tester.pumpWidget(wrap(bare.toSet()));
    await tester.pumpAndSettle();

    // No packageAppNames recorded, but the built-in table names Douyin.
    expect(find.text('抖音'), findsOneWidget);
    expect(find.text('com.ss.android.ugc.aweme'), findsNothing);
  });

  testWidgets('an unknown package falls back to the id itself', (
    WidgetTester tester,
  ) async {
    final InMemoryCapabilities unknown = InMemoryCapabilities(
      contacts: <KnowledgeContact>[
        KnowledgeContact(
          id: 'c3',
          name: '王五',
          updatedAt: DateTime.utc(2026),
          packageNames: <String>['com.example.strange'],
        ),
      ],
      files: _payloadFiles(root),
    );
    await tester.pumpWidget(wrap(unknown.toSet()));
    await tester.pumpAndSettle();

    expect(find.text('com.example.strange'), findsOneWidget);
  });

  testWidgets('stage is a dropdown and edits write the field back', (
    WidgetTester tester,
  ) async {
    final CapabilitySet set = capabilities.toSet();
    await tester.pumpWidget(wrap(set));
    await tester.pumpAndSettle();

    await tester.tap(find.text('张三'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('编辑'));
    await tester.pumpAndSettle();

    // The stage field is a dropdown, not a text field.
    expect(find.byType(DropdownButtonFormField<String>), findsNWidgets(2));

    // Pick a stage from the dropdown.
    await tester.tap(find.byType(DropdownButtonFormField<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('暧昧').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    final List<KnowledgeContact> saved = await set.knowledgeStore.contacts();
    expect(saved.single.stage, '暧昧');
  });

  testWidgets('every edit field carries a helper line', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(wrap(capabilities.toSet()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('张三'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('编辑'));
    await tester.pumpAndSettle();

    expect(find.text('你们现在的关系到了哪一步。'), findsOneWidget);
    expect(find.text('这一轮你最想推进什么。'), findsOneWidget);
    expect(find.text('对方的背景，比如怎么认识、在做什么。'), findsOneWidget);
    expect(find.text('其他想记住的点，比如对方的偏好、雷区。'), findsOneWidget);
  });
}

/// The five data files `SharedMaterial.load` reads, taken from the real
/// repository tree so the enum in the test is the enum the app ships.
Map<String, List<int>> _payloadFiles(Directory root) => <String, List<int>>{
  payloadMapPath: File('${root.path}/$payloadMapPath').readAsBytesSync(),
  strategyCriteriaPath: File(
    '${root.path}/$strategyCriteriaPath',
  ).readAsBytesSync(),
  judgeQuestionsPath: File('${root.path}/$judgeQuestionsPath').readAsBytesSync(),
  replyPreferencesPath: File(
    '${root.path}/$replyPreferencesPath',
  ).readAsBytesSync(),
  relationshipEnumsPath: File(
    '${root.path}/$relationshipEnumsPath',
  ).readAsBytesSync(),
};

Directory _repositoryRoot() {
  Directory directory = Directory.current.absolute;
  while (true) {
    if (Directory('${directory.path}/miaotoujunshi').existsSync()) {
      return directory;
    }
    final Directory parent = directory.parent;
    if (parent.path == directory.path) {
      throw StateError('no repository root above ${Directory.current.absolute}');
    }
    directory = parent;
  }
}
