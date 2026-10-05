import 'dart:io';

import 'package:miaotou_capabilities/miaotou_capabilities.dart';
import 'package:miaotou_capabilities_windows/miaotou_capabilities_windows.dart';
import 'package:miaotou_capabilities_windows/testing.dart';
import 'package:test/test.dart';

void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('miaotou-windows-'));
  tearDown(() => root.deleteSync(recursive: true));

  test('preferences survive a reopened store with exact types', () async {
    final WindowsPreferences first = WindowsPreferences.inDirectory(root);
    await first.setString('route', 'deepseek');
    await first.setBool('autoAnalyse', true);
    await first.setInt('candidates', 3);
    await first.setStringList('whitelist', <String>['b', 'a', 'b']);

    final WindowsPreferences reopened = WindowsPreferences.inDirectory(root);
    expect(await reopened.getString('route'), 'deepseek');
    expect(await reopened.getBool('autoAnalyse'), isTrue);
    expect(await reopened.getInt('candidates'), 3);
    expect(await reopened.getStringList('whitelist'), <String>['a', 'b']);
    expect(await reopened.getString('autoAnalyse'), isNull);
  });

  test('knowledge and memory survive a reopened store', () async {
    final WindowsKnowledgeStore knowledge = WindowsKnowledgeStore.inDirectory(
      root,
    );
    await knowledge.saveNote(
      KnowledgeNote(
        id: 'n1',
        title: '边界',
        content: '不要追问',
        updatedAt: DateTime.utc(2026, 10, 5),
      ),
    );

    final WindowsMemoryStore memory = WindowsMemoryStore.inDirectory(root);
    await memory.grantConsent(confirmed: true);
    await memory.apply(subjectId: 'c1', field: 'stage', value: '熟悉');

    expect(
      (await WindowsKnowledgeStore.inDirectory(root).notes()).single.content,
      '不要追问',
    );
    expect(
      (await WindowsMemoryStore.inDirectory(root).show('c1')).single.value,
      '熟悉',
    );
  });

  test(
    'credentials use the credential backend and never the data directory',
    () async {
      final MemoryWindowsCredentialBackend backend =
          MemoryWindowsCredentialBackend();
      final WindowsSecretStore secrets = WindowsSecretStore(backend);
      await secrets.write('deepseek', 'secret-value');

      expect(await secrets.read('deepseek'), 'secret-value');
      expect(await secrets.keys(), <String>{'deepseek'});
      expect(
        root.listSync(recursive: true),
        isEmpty,
        reason:
            'credentials belong to Windows Credential Manager, never a file',
      );
    },
  );
}
