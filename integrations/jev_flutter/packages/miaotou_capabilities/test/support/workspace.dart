import 'dart:io';

/// Finds the pub workspace root by walking up from the package being tested.
///
/// The workspace root is the only `pubspec.yaml` that carries a `workspace:`
/// key. Walking up rather than hard-coding a relative path keeps these tests
/// working from an IDE, from `dart test` in the package, and from the workspace
/// root alike.
Directory findWorkspaceRoot() {
  Directory directory = Directory.current.absolute;
  while (true) {
    final File pubspec = File('${directory.path}/pubspec.yaml');
    if (pubspec.existsSync() && _declaresWorkspace(pubspec.readAsStringSync())) {
      return directory;
    }
    final Directory parent = directory.parent;
    if (parent.path == directory.path) {
      throw StateError(
        'no pub workspace root above ${Directory.current.absolute.path}',
      );
    }
    directory = parent;
  }
}

/// Finds the repository root by walking up until a directory holds both payload
/// directories.
///
/// This is what makes the shared-payload tests meaningful: they read the real
/// payload, through the real repository-relative keys, rather than a copy.
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

/// Every `pubspec.yaml` in the workspace, the root included.
List<File> workspacePubspecs(Directory workspace) {
  final List<File> pubspecs = <File>[];
  for (final FileSystemEntity entity
      in workspace.listSync(recursive: true, followLinks: false)) {
    if (entity is! File || !entity.path.endsWith('pubspec.yaml')) {
      continue;
    }
    if (entity.path.contains('/.dart_tool/') || entity.path.contains('/build/')) {
      continue;
    }
    pubspecs.add(entity);
  }
  pubspecs.sort((File a, File b) => a.path.compareTo(b.path));
  return pubspecs;
}

bool _declaresWorkspace(String pubspec) =>
    pubspec.split('\n').any((String line) => line.trimRight() == 'workspace:');
