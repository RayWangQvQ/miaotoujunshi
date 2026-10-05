import 'dart:io';
import 'dart:typed_data';

import 'package:miaotou_capabilities/miaotou_capabilities.dart';
import 'package:miaotou_domain/miaotou_domain.dart';

/// The repository root, found by walking up until both payload directories are
/// present.
///
/// Walking rather than hard-coding keeps these tests working from an IDE, from
/// `dart test` in the package, and from the workspace root alike.
Directory findRepositoryRoot() {
  Directory directory = Directory.current.absolute;
  while (true) {
    if (Directory('${directory.path}/goutoujunshi').existsSync() &&
        Directory('${directory.path}/miaotoujunshi').existsSync()) {
      return directory;
    }
    final Directory parent = directory.parent;
    if (parent.path == directory.path) {
      throw StateError(
        'no repository root above ${Directory.current.absolute.path}',
      );
    }
    directory = parent;
  }
}

/// A [SharedPayload] over the real repository tree, for tests only.
///
/// The tests read the **real** payload through the **real**
/// repository-relative keys. That is the point: the existing suite's expectation
/// for prompt assembly is that the strategy guide really contains the seven
/// strategies and really has had its examples cut, and a hand-written fixture
/// would assert the fixture instead of the payload.
final class RepoSharedPayload implements SharedPayload {
  RepoSharedPayload(this.root);

  final String root;

  @override
  Future<Uint8List> read(String repoRelativePath) async {
    final File file = File('$root/$repoRelativePath');
    if (!file.existsSync()) {
      throw FileSystemException('no payload file', file.path);
    }
    return file.readAsBytes();
  }

  @override
  Future<List<String>> list(String repoRelativeDir) async {
    final Directory directory = Directory('$root/$repoRelativeDir');
    if (!directory.existsSync()) {
      throw FileSystemException('no payload directory', directory.path);
    }
    return <String>[
      for (final FileSystemEntity entity
          in directory.listSync(followLinks: false))
        if (entity is File) entity.uri.pathSegments.last,
    ]..sort();
  }
}

/// The real payload, loaded once per test file.
Future<SharedMaterial> loadRealMaterial() =>
    SharedMaterial.load(RepoSharedPayload(findRepositoryRoot().path));
