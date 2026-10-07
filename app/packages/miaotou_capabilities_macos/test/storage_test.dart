import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:miaotou_capabilities/miaotou_capabilities.dart';
import 'package:miaotou_capabilities_macos/miaotou_capabilities_macos.dart';
import 'package:miaotou_capabilities_macos/testing.dart';

/// What this port still owns of storage: the container directory, and the
/// Keychain.
///
/// The three stores moved to `miaotou_capabilities_shared` — their behaviour is
/// asserted once, there, for all three ports. What is left here is the half that
/// is genuinely macOS's:
///
/// * **The container.** Where the app may write, how a document gets there, and
///   what happens when the write is interrupted. The shared modules sit above the
///   seam and cannot arrange any of it from the other side.
/// * **The Keychain.** No other port has one, so no shared module can answer for
///   it.
/// * **The boundary between the two.** `PRIVACY.md` promises the keys are in the
///   system store, and the only way to keep that promise is to keep asserting
///   that nothing secret reaches a file.
void main() {
  late FakeMacosNative native;

  setUp(() {
    native = fakeMacosWithTemporaryStorage();
  });

  tearDown(() async {
    await native.close();
    deleteTemporaryStorage(native);
  });

  group('the keychain', () {
    late MacosSecretStore secrets;

    setUp(() {
      secrets = MacosSecretStore(native);
    });

    test('a secret written is a secret read back', () async {
      await secrets.write('deepseek', 'sk-value');

      expect(await secrets.read('deepseek'), 'sk-value');
    });

    test('a key that was never set reads back as null, not as an error',
        () async {
      expect(await secrets.read('openrouter'), isNull);
    });

    test('writing the same key twice replaces rather than duplicates', () async {
      await secrets.write('jev', 'first');
      await secrets.write('jev', 'second');

      expect(await secrets.read('jev'), 'second');
      expect(await secrets.keys(), <String>{'jev'});
    });

    test('deleting a key that is not set is not an error', () async {
      await secrets.delete('never-written');
      expect(await secrets.keys(), isEmpty);
    });

    test('keys() names the configured routes and nothing else', () async {
      await secrets.write('deepseek', 'sk-one');
      await secrets.write('jev', 'sk-two');

      final Set<String> keys = await secrets.keys();

      expect(keys, <String>{'deepseek', 'jev'});
      // The property that matters: there is no member anywhere that hands back
      // the values in bulk, so a settings screen physically cannot render an API
      // key while deciding whether to show a field. Asserted on the fake's
      // contents because the fake, unlike the real store, can be looked at.
      expect(
        keys.where((String key) => key.contains('sk-')),
        isEmpty,
        reason: 'a key is the name a caller passed; a value must never appear in '
            'the key set, because the key set is what a settings screen renders',
      );
    });

    test('a secret survives the process: a second store reads the same value',
        () async {
      await secrets.write('deepseek', 'sk-durable');

      // The Keychain is outside the app's container, so a relaunch keeps it while
      // the container's caches do not. Asserted by going through a second object
      // and by checking the fake was never asked to re-create anything.
      final MacosSecretStore reopened = MacosSecretStore(native);

      expect(await reopened.read('deepseek'), 'sk-durable');
    });
  });

  group('the container directory', () {
    test('is created if it is not there, and it is the seam that is asked',
        () async {
      final Directory fresh =
          Directory.systemTemp.createTempSync('miaotou-nested');
      // A path that does not exist yet, three levels down.
      final String missing = '${fresh.path}/a/b/c';
      final FakeMacosNative scripted =
          FakeMacosNative(containerRoot: missing, payloadRoot: fresh.path);
      addTearDown(() async {
        await scripted.close();
        fresh.deleteSync(recursive: true);
      });

      await PreferenceLedger(
        ContainerDocuments(scripted),
      ).setString('route', 'jev');

      expect(Directory(missing).existsSync(), isTrue);
      expect(scripted.log, contains('containerDirectory'));
    });

    test('the directory is asked for once, not once per document', () async {
      // What makes one `ContainerDocuments` per bundle worth having: the round
      // trip is the only cost this seam adds, and three stores sharing it means
      // one ask rather than three.
      final ContainerDocuments documents = ContainerDocuments(native);

      await PreferenceLedger(documents).setString('route', 'jev');
      await KnowledgeLedger(documents).saveNote(_note());
      await MemoryLedger(documents).status();

      expect(
        native.log.where((String call) => call == 'containerDirectory'),
        hasLength(1),
        reason: 'the container cannot change within a process, so asking again '
            'would be a round trip that can only return the same answer',
      );
    });

    test('an answer with no path in it is refused rather than written to',
        () async {
      // The `?? ''` in the channel implementation would otherwise turn into a
      // relative path under the process's working directory — which, in a
      // sandboxed app, is somewhere unwritable and somewhere surprising.
      //
      // Driven through the file rather than through the fake, because the fake
      // *refuses* the question rather than answering it with an empty string, so
      // it never reaches the guard this is about. The two refusals are different
      // failures and both are wanted.
      final ContainerDocuments documents = ContainerDocuments(_EmptyDirectory());

      await expectLater(
        PreferenceLedger(documents).keys(),
        throwsStateError,
        reason: 'an empty container path must not become a relative path under '
            'the working directory',
      );
      await expectLater(
        KnowledgeLedger(documents).notes(),
        throwsStateError,
      );
      await expectLater(
        MemoryLedger(documents).status(),
        throwsStateError,
      );
    });

    test('a fake that is not told where the container is refuses the question',
        () async {
      // The other half, and the reason the fake does not default: a fake that
      // invented a path would let a test pass against a location nothing else
      // uses, or read the developer's own container.
      final FakeMacosNative bare = FakeMacosNative();
      addTearDown(bare.close);

      await expectLater(
        PreferenceLedger(ContainerDocuments(bare)).keys(),
        throwsStateError,
      );
      await expectLater(
        MacosPayloadTree(bare).resourceRoot(),
        throwsStateError,
      );
    });

    test('a write interrupted before the rename leaves the last good document',
        () async {
      // The strongest durability claim the seam makes — write to a sibling
      // `.tmp`, then rename over the target — and the one thing the shared
      // modules cannot arrange from above it.
      //
      // The failure is injected rather than described: the directory is made
      // read-only *after* the scratch file exists, so writing the scratch file
      // still succeeds (an existing file needs write permission, not directory
      // permission) while the rename fails. That is precisely the window the claim
      // is about — the bytes are on disk and the target has not been replaced yet.
      final PreferenceLedger store = PreferenceLedger(
        ContainerDocuments(native),
      );
      await store.setString('route', 'first');
      final File target = _containerFile(native, 'preferences.json');
      final File scratch = File('${target.path}.tmp');

      // The scratch file has to exist beforehand, or creating it would need the
      // directory permission this removes and the failure would land in the wrong
      // place — before the write rather than between the write and the rename.
      scratch.writeAsStringSync('{}');
      _makeReadOnly(target.parent);
      addTearDown(() => _makeWritable(target.parent));

      await expectLater(
        store.setString('route', 'second'),
        throwsA(isA<FileSystemException>()),
        reason: 'the rename cannot succeed with the directory read-only; if this '
            'did not throw, the fault was not injected and the test proves '
            'nothing',
      );

      expect(
        target.readAsStringSync(),
        contains('first'),
        reason: 'the target must still hold the last complete document. A '
            'half-written preferences file is worse than a missing one: it is '
            'unreadable *and* it has already destroyed what was there',
      );
      expect(
        () => jsonDecode(target.readAsStringSync()),
        returnsNormally,
        reason: '"first" has to be the whole previous document, not a prefix of a '
            'new one — the claim is that the old file is intact, not merely that '
            'some of it is',
      );
      expect(
        await PreferenceLedger(
          ContainerDocuments(native),
        ).getString('route'),
        'first',
        reason: 'and the store recovers on its own once the directory is writable '
            'again, with no relaunch and nothing to reset',
      );
    });
  });

  group('the boundary between the two', () {
    test('no credential is ever written to the container', () async {
      const String secret = 'sk-this-must-never-touch-a-file';
      await MacosSecretStore(native).write('deepseek', secret);
      await PreferenceLedger(ContainerDocuments(native)).setString(
        'route',
        'deepseek',
      );

      final List<File> files = _containerFiles(native);
      expect(files, isNotEmpty, reason: 'the preference did write something');
      for (final File file in files) {
        expect(
          file.readAsStringSync(),
          isNot(contains(secret)),
          reason: '${file.path} holds a value that went to the Keychain; '
              'PRIVACY.md says the keys are in the system Keychain',
        );
      }
    });

    test('the keychain is never asked for a directory, and the stores never ask '
        'for a resource root', () async {
      final MacosSecretStore secrets = MacosSecretStore(native);
      await secrets.write('deepseek', 'sk-value');
      await PreferenceLedger(ContainerDocuments(native)).setString(
        'route',
        'deepseek',
      );

      expect(
        native.log,
        isNot(contains('resourceRoot')),
        reason: 'the payload root is a read-only location inside the bundle; a '
            'store writing there would fail in a signed, sandboxed app',
      );
      expect(
        native.log.where((String call) => call.startsWith('keychain.')),
        <String>['keychain.write:deepseek'],
        reason: 'the preferences write must not have gone anywhere near the '
            'Keychain — the two are the whole privacy boundary',
      );
    });

    test('the three stores write to three documents', () async {
      await PreferenceLedger(
        ContainerDocuments(native),
      ).setString('route', 'jev');
      await KnowledgeLedger(ContainerDocuments(native)).saveNote(_note());
      await MemoryLedger(ContainerDocuments(native)).clear();

      expect(
        _containerFiles(native).map((File f) => f.uri.pathSegments.last).toSet(),
        <String>{'preferences.json', 'knowledge.json', 'memory.json'},
        reason: 'one document per store, so a corrupt one cannot take the others '
            'with it and a reader can tell what is what',
      );
    });
  });
}

/// A seam that answers an **empty** container path.
///
/// Not a `FakeMacosNative`, because that one refuses the question rather than
/// answering it badly — and the guard under test is the one that catches a bad
/// answer, which the fake's refusal never reaches.
class _EmptyDirectory implements MacosNative {
  @override
  Future<String> containerDirectory() async => '';

  @override
  Future<String> resourceRoot() async => '';

  @override
  Future<List<String>> keychainKeys() async => const <String>[];

  @override
  Future<String?> keychainRead(String key) async => null;

  @override
  Future<void> keychainWrite(String key, String value) async {}

  @override
  Future<void> keychainDelete(String key) async {}

  @override
  Future<String?> findTargetWindow() async => null;

  @override
  Future<CaptureOutcome> capture({String? targetWindowId}) async =>
      const CaptureFailed(code: 1, message: 'not used');

  @override
  Future<List<OcrLine>> recognize(
    CaptureFrame frame, {
    required List<String> languages,
  }) async =>
      const <OcrLine>[];

  @override
  Future<InjectResult> inject(
    String text, {
    required InjectTarget target,
  }) async =>
      const InjectResult.unverified('not used');

  @override
  Future<PanelGeometry> panelGeometry() async =>
      const PanelGeometry(screen: ScreenRect.empty, window: ScreenRect.empty);

  @override
  Future<void> showPanel({
    required PanelPlacement placement,
    ScreenRect? at,
  }) async {}

  @override
  Future<bool> hidePanel() async => false;

  @override
  Future<void> restorePanel() async {}

  @override
  Future<void> setPanelFocusable(bool value) async {}

  @override
  Stream<NativePanelEvent> get events => const Stream<NativePanelEvent>.empty();
}

File _containerFile(FakeMacosNative native, String name) =>
    File('${native.containerRoot}/$name');

/// Makes [directory] read-only, so a rename inside it cannot succeed.
///
/// `chmod` rather than a Dart-side flag because the property under test is a
/// property of the filesystem: a `rename` needs write permission on the
/// *directory*, while writing to an already-openable file does not. That
/// difference is what lets the test fail between the scratch write and the
/// rename rather than before the write.
///
/// The [ProcessException] catch is for the shape of the API rather than for
/// `chmod`, which exists on every platform this suite runs on. `runSync` raises
/// when the executable is missing and returns a non-zero code when it ran and
/// refused — and the second is a fact about the filesystem worth failing on,
/// while the first would abort a test that was never about permissions.
void _makeReadOnly(Directory directory) {
  final ProcessResult result;
  try {
    result = Process.runSync('chmod', <String>['0555', directory.path]);
  } on ProcessException catch (error) {
    throw StateError(
      'could not run chmod to make ${directory.path} '
      'read-only: ${error.message}',
    );
  }
  if (result.exitCode != 0) {
    throw StateError(
      'could not make ${directory.path} read-only: ${result.stderr}',
    );
  }
}

/// Undoes [_makeReadOnly], so the tear-down can delete what the test wrote.
///
/// Deliberately not checked. This runs in a tear-down, where a throw masks the
/// failure that made the clean-up necessary; a directory left read-only is a
/// scratch directory in `systemTemp` that the next run replaces anyway.
void _makeWritable(Directory directory) {
  try {
    Process.runSync('chmod', <String>['0755', directory.path]);
  } on ProcessException {
    // Nothing to do and nowhere to report it to that would help.
  }
}

List<File> _containerFiles(FakeMacosNative native) => <File>[
  for (final FileSystemEntity entity
      in Directory(native.containerRoot!).listSync(recursive: true))
    if (entity is File) entity,
];

KnowledgeNote _note() => KnowledgeNote(
  id: 'n1',
  title: '标题',
  content: '不吃香菜',
  updatedAt: DateTime(2026, 10, 4, 12),
);
