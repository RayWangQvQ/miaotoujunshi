import 'dart:convert';
import 'dart:typed_data';

import 'package:miaotou_capabilities/miaotou_capabilities.dart';
import 'package:miaotou_capabilities_android/miaotou_capabilities_android.dart';
import 'package:miaotou_capabilities_android/testing.dart';
import 'package:test/test.dart';

/// What this port still owns of storage: the document channel, and the secrets.
///
/// The three stores moved to `miaotou_capabilities_shared` and their behaviour is
/// asserted once, there, for all three ports. What is left here is the half that
/// is Android's: that a document is a named string on the channel and nothing
/// more, and that the secrets go to the Keystore rather than to a file.
///
/// The settings document used to be answered here by four Kotlin members over
/// `SharedPreferences`, which is what made this the one port whose settings were
/// shaped by a different language. It travels as a document now.
void main() {
  late MemoryAndroidStorageNative native;

  setUp(() => native = MemoryAndroidStorageNative());

  test('a document is a named string on the channel, and nothing else',
      () async {
    await PreferenceLedger(
      AndroidDocuments(native),
    ).setString('route', 'deepseek');

    expect(
      jsonDecode(native.documents['preferences.json']!) as Map<String, Object?>,
      <String, Object?>{
        'route': <String, Object?>{'type': 'string', 'value': 'deepseek'},
      },
      reason: 'the channel carries text, so this port has no say in what a '
          'settings document looks like — that is what lets it share one with the '
          'two desktop ports',
    );
  });

  test('a document that is not there yet reads back as nothing, not an error',
      () async {
    expect(await AndroidDocuments(native).readText('absent.json'), isNull);
  });

  test('the three stores arrive as three documents, not as one blob', () async {
    final AndroidDocuments documents = AndroidDocuments(native);
    await PreferenceLedger(documents).setString('route', 'deepseek');
    await KnowledgeLedger(documents).saveNote(
      KnowledgeNote(
        id: 'n1',
        title: '边界',
        content: '不要追问',
        updatedAt: DateTime.utc(2026, 10, 5),
      ),
    );
    await MemoryLedger(documents).clear();

    expect(
      native.documents.keys.toSet(),
      <String>{'preferences.json', 'knowledge.json', 'memory.json'},
      reason: 'one document per store, so a corrupt one cannot take the others '
          'with it and a reader can tell what is what',
    );
  });

  test('a document another store wrote is visible at once', () async {
    // The no-cache property, seen from the channel side: two adapters over one
    // device are the ordinary shape of this code, and a cached read would make
    // the second one answer from a value that was current when it was first asked.
    await PreferenceLedger(
      AndroidDocuments(native),
    ).setString('route', 'deepseek');

    expect(
      await PreferenceLedger(AndroidDocuments(native)).getString('route'),
      'deepseek',
    );
  });

  test('a document whose name leaves the directory is refused by the device',
      () async {
    // The name is validated behind the channel, in `AndroidStorageHost.kt`'s
    // `document(name)`, so nothing on the Dart side can write outside the
    // app-private directory. What the Dart side can do is fail loudly when the
    // channel refuses, which is what this asserts with a device that does.
    final _RefusingStorageNative refusing = _RefusingStorageNative();

    await expectLater(
      AndroidDocuments(refusing).readText('../escape.json'),
      throwsStateError,
    );
  });

  test('secrets use only the native secret operations', () async {
    final AndroidSecretStore secrets = AndroidSecretStore(native);
    await secrets.write('deepseek', 'secret-value');

    expect(await secrets.read('deepseek'), 'secret-value');
    expect(await secrets.keys(), <String>{'deepseek'});
    expect(
      native.documents,
      isEmpty,
      reason: 'an API key must never reach a document on any port; PRIVACY.md '
          'says the keys are in the system store',
    );

    await secrets.delete('deepseek');
    await secrets.delete('not-set');
    expect(await secrets.read('deepseek'), isNull);
  });
}

/// A device that refuses every document by name, standing in for the Kotlin
/// `require(DOCUMENT_NAME.matches(name))`.
final class _RefusingStorageNative implements AndroidStorageNative {
  final MemoryAndroidStorageNative _delegate = MemoryAndroidStorageNative();

  @override
  Future<Uint8List?> readPayload(String repoRelativePath) =>
      _delegate.readPayload(repoRelativePath);

  @override
  Future<List<String>?> listPayload(String repoRelativeDir) =>
      _delegate.listPayload(repoRelativeDir);

  @override
  Future<String?> readSecret(String key) => _delegate.readSecret(key);

  @override
  Future<void> writeSecret(String key, String value) =>
      _delegate.writeSecret(key, value);

  @override
  Future<void> deleteSecret(String key) => _delegate.deleteSecret(key);

  @override
  Future<Set<String>> secretKeys() => _delegate.secretKeys();

  @override
  Future<String?> readDocument(String name) async =>
      throw StateError('document name must be a single safe file name');

  @override
  Future<void> writeDocument(String name, String contents) async =>
      throw StateError('document name must be a single safe file name');
}
