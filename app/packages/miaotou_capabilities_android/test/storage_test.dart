import 'dart:convert';
import 'dart:io';

import 'package:miaotou_capabilities/miaotou_capabilities.dart';
import 'package:miaotou_capabilities_android/miaotou_capabilities_android.dart';
import 'package:miaotou_capabilities_android/testing.dart';
import 'package:test/test.dart';

void main() {
  late MemoryAndroidStorageNative native;

  setUp(() => native = MemoryAndroidStorageNative());

  test('preferences preserve exact types and set semantics', () async {
    final AndroidPreferences preferences = AndroidPreferences(native);
    await preferences.setString('route', 'deepseek');
    await preferences.setBool('autoAnalyse', true);
    await preferences.setInt('candidates', 3);
    await preferences.setStringList('whitelist', <String>['b', 'a', 'b']);

    expect(await preferences.getString('route'), 'deepseek');
    expect(await preferences.getBool('autoAnalyse'), isTrue);
    expect(await preferences.getInt('candidates'), 3);
    expect(await preferences.getStringList('whitelist'), <String>['a', 'b']);
    expect(await preferences.getString('autoAnalyse'), isNull);
    expect(await preferences.keys(), <String>{
      'route',
      'autoAnalyse',
      'candidates',
      'whitelist',
    });

    await preferences.remove('route');
    await preferences.remove('not-set');
    expect(await preferences.getString('route'), isNull);
  });

  test(
    'knowledge survives a reopened store and matches both identity halves',
    () async {
      final AndroidKnowledgeStore first = AndroidKnowledgeStore(native);
      await first.saveNote(
        KnowledgeNote(
          id: 'n1',
          title: '边界',
          content: '不要追问',
          updatedAt: DateTime.utc(2026, 10, 5),
        ),
      );
      await first.saveContact(
        KnowledgeContact(
          id: 'c1',
          name: '小岚',
          aliases: const <String>[' Lan '],
          packageNames: const <String>['com.tencent.mm'],
          updatedAt: DateTime.utc(2026, 10, 5),
        ),
      );

      final AndroidKnowledgeStore reopened = AndroidKnowledgeStore(native);
      expect((await reopened.notes()).single.content, '不要追问');
      expect(
        (await reopened.findContact(
          title: 'lan',
          packageName: 'COM.TENCENT.MM',
        ))?.id,
        'c1',
      );
      expect(
        await reopened.findContact(title: 'lan', packageName: 'another.app'),
        isNull,
      );
    },
  );

  test(
    'knowledge log is bounded by the requested window and clears with contact',
    () async {
      final AndroidKnowledgeStore store = AndroidKnowledgeStore(native);
      await store.appendLog('c1', <KnowledgeLogEntry>[
        KnowledgeLogEntry(
          speaker: Speaker.me,
          text: 'one',
          timestamp: DateTime.utc(2026, 10, 5, 1),
          packageName: 'chat.app',
        ),
        KnowledgeLogEntry(
          speaker: Speaker.other,
          text: 'two',
          timestamp: DateTime.utc(2026, 10, 5, 2),
          packageName: 'chat.app',
        ),
      ]);

      expect(
        (await store.recentLog('c1', limit: 1)).map((entry) => entry.text),
        <String>['two'],
      );
      await store.deleteContact('c1');
      expect(await store.recentLog('c1', limit: 10), isEmpty);
    },
  );

  test(
    'memory persists records but undo stays within one open store',
    () async {
      final AndroidMemoryStore first = AndroidMemoryStore(native);
      expect((await first.status()).consentEnabled, isFalse);
      await expectLater(
        first.apply(subjectId: 'c1', field: 'stage', value: '熟悉'),
        throwsStateError,
      );

      await first.grantConsent(confirmed: true);
      await first.apply(subjectId: 'c1', field: 'stage', value: '熟悉');
      await first.apply(subjectId: 'c1', field: 'stage', value: '升温');

      final AndroidMemoryStore reopened = AndroidMemoryStore(native);
      expect((await reopened.show('c1')).single.value, '升温');
      expect(await reopened.undo(), 0);
      expect(await first.undo(), 2);
      expect(await reopened.show('c1'), isEmpty);
    },
  );

  test('memory fixture pins consent, pause and capacity safety', () async {
    final Map<String, Object?> fixture = (jsonDecode(
      File('test/fixtures/memory_policy.json').readAsStringSync(),
    ) as Map).cast<String, Object?>();
    expect(AndroidMemoryStore.maxValueChars, fixture['maxValueChars']);
    expect(AndroidMemoryStore.maxRows, fixture['maxRows']);
    expect(AndroidMemoryStore.maxOperations, fixture['maxOperations']);

    native.documents['memory.json'] = jsonEncode(<String, Object?>{
      'consentEnabled': true,
      'paused': true,
    });
    final AndroidMemoryStore paused = AndroidMemoryStore(native);
    await expectLater(
      paused.apply(subjectId: 'c1', field: 'stage', value: '熟悉'),
      throwsStateError,
    );

    native.documents['memory.json'] = jsonEncode(<String, Object?>{
      'consentEnabled': true,
      'records': <Map<String, String>>[
        for (int index = 0; index < AndroidMemoryStore.maxRows; index++)
          <String, String>{
            'subjectId': 'c$index',
            'field': 'stage',
            'value': '熟悉',
          },
      ],
    });
    final AndroidMemoryStore full = AndroidMemoryStore(native);
    expect((await full.status()).atCapacity, isTrue);
    await expectLater(
      full.apply(subjectId: 'new', field: 'stage', value: '熟悉'),
      throwsStateError,
    );
    await full.apply(subjectId: 'c0', field: 'stage', value: '升温');
    expect((await full.show('c0')).single.value, '升温');
  });

  test('secrets use only the native secret operations', () async {
    final AndroidSecretStore secrets = AndroidSecretStore(native);
    await secrets.write('deepseek', 'secret-value');

    expect(await secrets.read('deepseek'), 'secret-value');
    expect(await secrets.keys(), <String>{'deepseek'});
    expect(native.preferences, isEmpty);
    expect(native.documents, isEmpty);

    await secrets.delete('deepseek');
    await secrets.delete('not-set');
    expect(await secrets.read('deepseek'), isNull);
  });
}
