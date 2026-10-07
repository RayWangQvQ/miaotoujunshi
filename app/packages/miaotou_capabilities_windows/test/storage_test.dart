import 'dart:io';

import 'package:miaotou_capabilities/miaotou_capabilities.dart';
import 'package:miaotou_capabilities_windows/miaotou_capabilities_windows.dart';
import 'package:miaotou_capabilities_windows/testing.dart';
import 'package:test/test.dart';

/// What this port still owns of storage: the directory, and nothing else.
///
/// The three stores are the shared module's now, and their behaviour is asserted
/// once, in `miaotou_capabilities_shared`. What is left to check here is the seam
/// underneath them — that a name becomes a file in the directory this port chose,
/// and that the document written there is readable by whoever opens it next. The
/// round trips below go through a *reopened* documents object for exactly that
/// reason: a store that kept its contents in memory would pass a same-object
/// assertion and lose the user's data.
void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('miaotou-windows-'));
  tearDown(() => root.deleteSync(recursive: true));

  test('preferences survive a reopened store with exact types', () async {
    final PreferenceLedger first = PreferenceLedger(WindowsDocuments(root));
    await first.setString('route', 'deepseek');
    await first.setBool('autoAnalyse', true);
    await first.setInt('candidates', 3);
    await first.setStringList('whitelist', <String>['b', 'a', 'b']);

    final PreferenceLedger reopened = PreferenceLedger(WindowsDocuments(root));
    expect(await reopened.getString('route'), 'deepseek');
    expect(await reopened.getBool('autoAnalyse'), isTrue);
    expect(await reopened.getInt('candidates'), 3);
    expect(await reopened.getStringList('whitelist'), <String>['a', 'b']);
    expect(await reopened.getString('autoAnalyse'), isNull);
  });

  test('knowledge and memory survive a reopened store', () async {
    final KnowledgeLedger knowledge = KnowledgeLedger(WindowsDocuments(root));
    await knowledge.saveNote(
      KnowledgeNote(
        id: 'n1',
        title: '边界',
        content: '不要追问',
        updatedAt: DateTime.utc(2026, 10, 5),
      ),
    );

    final MemoryLedger memory = MemoryLedger(WindowsDocuments(root));
    await memory.grantConsent(confirmed: true);
    await memory.apply(subjectId: 'c1', field: 'stage', value: '熟悉');

    expect(
      (await KnowledgeLedger(WindowsDocuments(root)).notes()).single.content,
      '不要追问',
    );
    expect(
      (await MemoryLedger(WindowsDocuments(root)).show('c1')).single.value,
      '熟悉',
    );
  });

  test(
    'the document lands in the directory this port was given',
    () async {
      await PreferenceLedger(WindowsDocuments(root)).setString(
        'route',
        'deepseek',
      );

      expect(
        File('${root.path}${Platform.pathSeparator}preferences.json')
            .existsSync(),
        isTrue,
        reason:
            'the directory is the only storage decision left on this side of the '
            'seam, so it is the one thing this package still has to assert',
      );
      expect(
        root
            .listSync()
            .whereType<File>()
            .where((File file) => file.path.endsWith('.tmp')),
        isEmpty,
        reason:
            'an atomic write leaves no scratch file behind once it has renamed',
      );
    },
  );

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
