import 'dart:io';
import 'dart:typed_data';

import 'package:miaotou_capabilities/miaotou_capabilities.dart';

/// A [SharedPayload] over a real directory tree, for tests only.
///
/// It is deliberately **not** in the shipping library and **not** offered to the
/// platform packages as a default: ADR-0008 decision 2 says each port keeps the
/// mechanism it already has — Android its `AssetManager`, macOS
/// `Contents/Resources/`, Windows the files beside the executable — and a
/// convenient fourth implementation in Dart is exactly the kind of thing that
/// would quietly replace all three.
///
/// What it is for is asserting the *shape* of the contract against the real
/// repository: that the keys really are repository-root-relative, that `list()`
/// really enumerates a directory rather than a hard-coded member list, and that a
/// file added to the payload is visible with no code change at all.
final class DirectorySharedPayload implements SharedPayload {
  DirectorySharedPayload(this.root);

  /// Absolute path the keys are resolved against.
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
    final List<String> names = <String>[
      for (final FileSystemEntity entity in directory.listSync(followLinks: false))
        if (entity is File) entity.uri.pathSegments.last,
    ]..sort();
    return names;
  }
}
