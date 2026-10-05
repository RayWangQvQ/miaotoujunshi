import 'dart:io';

import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

import 'support/directory_shared_payload.dart';
import 'support/workspace.dart';

/// The invariant ADR-0008 rests on: **the shared payload does not travel through
/// Flutter assets.**
///
/// A Flutter asset directory entry includes only the files directly inside it,
/// so `assets: - miaotoujunshi/` would not ship
/// `miaotoujunshi/references/data/*.json` — and adding a payload file would then
/// need a matching `pubspec.yaml` edit, which is the failure ADR-0005 and
/// ADR-0006 were written to remove. Each platform's build copies the payload tree
/// whole instead.
///
/// These tests are what makes that more than a paragraph. The first one fails if
/// anyone declares the payload as an asset; the rest pin the properties that
/// made the declaration attractive in the first place.
void main() {
  late Directory workspace;
  late Directory repository;

  setUpAll(() {
    workspace = findWorkspaceRoot();
    repository = findRepositoryRoot();
  });

  test('no pubspec in the workspace declares the payload as a Flutter asset', () {
    final List<String> offenders = <String>[];

    for (final File pubspec in workspacePubspecs(workspace)) {
      for (final String asset in _declaredAssets(pubspec)) {
        if (asset.startsWith('goutoujunshi') || asset.startsWith('miaotoujunshi')) {
          offenders.add('${pubspec.path} declares `$asset`');
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'the payload reaches a built artifact by being copied whole '
          '(ADR-0008); declaring it as a Flutter asset leaks it only partially, '
          'because an asset directory entry is not recursive',
    );
  });

  test('a payload key is a repository-root-relative path', () async {
    final DirectorySharedPayload payload = DirectorySharedPayload(repository.path);
    final bytes =
        await payload.read('miaotoujunshi/references/data/trend-rules.json');
    expect(bytes, isNotEmpty);
  });

  test('listing a payload directory needs no member list', () async {
    final DirectorySharedPayload payload = DirectorySharedPayload(repository.path);
    final List<String> names =
        await payload.list('miaotoujunshi/references/data');

    // Named as literals on purpose: this asserts the *repository* still holds the
    // files the payload map points at, not merely that the directory is readable.
    expect(names, contains('trend-rules.json'));
    expect(names, contains('payload-map.json'));
  });

  test('a file added to the payload becomes visible with no code change', () async {
    // The property the whole decision exists for. A temporary copy stands in for
    // a rebuilt artifact: nothing in this package knows the file's name.
    final Directory temp =
        Directory.systemTemp.createTempSync('miaotou-payload-invariant');
    addTearDown(() => temp.deleteSync(recursive: true));

    _copyTree(
      Directory('${repository.path}/miaotoujunshi/references/data'),
      Directory('${temp.path}/miaotoujunshi/references/data'),
    );

    final DirectorySharedPayload payload = DirectorySharedPayload(temp.path);
    final List<String> before = await payload.list('miaotoujunshi/references/data');

    File('${temp.path}/miaotoujunshi/references/data/added-later.json')
        .writeAsStringSync('{"added": true}');

    final List<String> after = await payload.list('miaotoujunshi/references/data');

    expect(after.length, before.length + 1);
    expect(after, contains('added-later.json'));
    expect(await payload.read('miaotoujunshi/references/data/added-later.json'),
        isNotEmpty);
  });

  test('a missing payload file is a hard error, not an empty buffer', () async {
    final DirectorySharedPayload payload = DirectorySharedPayload(repository.path);
    await expectLater(
      payload.read('miaotoujunshi/references/data/does-not-exist.json'),
      throwsA(isA<FileSystemException>()),
    );
    await expectLater(
      payload.list('miaotoujunshi/references/data/does-not-exist'),
      throwsA(isA<FileSystemException>()),
    );
  });
}

/// The `flutter: assets:` entries a pubspec declares, as written.
List<String> _declaredAssets(File pubspec) {
  final Object? document = loadYaml(pubspec.readAsStringSync());
  if (document is! Map) {
    return const <String>[];
  }
  final Object? flutter = document['flutter'];
  if (flutter is! Map) {
    return const <String>[];
  }
  final Object? assets = flutter['assets'];
  if (assets is! List) {
    return const <String>[];
  }
  return <String>[
    for (final Object? entry in assets)
      if (entry is String) entry,
  ];
}

void _copyTree(Directory from, Directory to) {
  for (final FileSystemEntity entity in from.listSync(recursive: true)) {
    final String relative = entity.path.substring(from.path.length + 1);
    final String target = '${to.path}/$relative';
    if (entity is Directory) {
      Directory(target).createSync(recursive: true);
    } else if (entity is File) {
      Directory(File(target).parent.path).createSync(recursive: true);
      entity.copySync(target);
    }
  }
}
