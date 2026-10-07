import 'dart:io';
import 'dart:typed_data';

import 'package:miaotou_capabilities_shared/miaotou_capabilities_shared.dart';

import 'native.dart';

/// macOS's half of the payload seam: one resource root, and a path per key.
///
/// **The payload is read as real files out of `.app/Contents/Resources/`,** which
/// is what keeps ADR-0008 decision 2 literally true: a packaged port reads the same
/// bytes from the same tree the repository holds, and there is no second copy
/// anywhere — not in `pubspec.yaml`, not inlined in Dart, not baked into the
/// binary.
///
/// ## What is native and what is not
///
/// The seam supplies one string, the resource root, because a packaged app has no
/// idea where its own bundle is. Everything else is `dart:io`, and that split is
/// what the tests exploit: they hand this class a temporary directory and exercise
/// the join, the read and the listing with no Mac and no `.app` anywhere. What a
/// *key* is, and what a missing one means, are [PayloadReader]'s — one answer for
/// all three ports rather than this one's.
final class MacosPayloadTree implements PayloadTree {
  MacosPayloadTree(this._native);

  final MacosNative _native;

  Future<String>? _root;

  /// The bundle's resource directory, asked for at most once per tree.
  ///
  /// Memoised because it cannot change within a process and a scene load reads a
  /// dozen files: asking the channel each time would put a platform round trip in
  /// the middle of every document read for a value that is a constant. The
  /// memoising is of *this* value only — the files under it are read fresh every
  /// time, which is the same split [ContainerDocuments] makes for the container.
  ///
  /// The empty answer is refused here as well as in the channel implementation,
  /// because [MacosNative] is an interface: this class cannot assume the only
  /// implementation of it is the one that throws. Joining onto an empty root yields
  /// `/…`, an absolute path out of the filesystem root, and the resulting "no such
  /// file" would name a path this application never meant to read.
  Future<String> resourceRoot() async {
    final String root = await (_root ??= _native.resourceRoot());
    if (root.isEmpty) {
      throw StateError(
        'the resource root is empty, so a payload key would resolve against the '
            'filesystem root rather than the bundle; refusing rather than '
            'guessing a directory',
      );
    }
    return root;
  }

  @override
  Future<Uint8List?> readFile(String key) async {
    final File file = File(await _path(key));
    return file.existsSync() ? file.readAsBytes() : null;
  }

  @override
  Future<List<String>?> listFiles(String key) async {
    final Directory directory = Directory(await _path(key));
    if (!directory.existsSync()) {
      return null;
    }
    // Only files, and only the ones directly inside: the contract asks for the
    // names in one directory, and a recursive walk here would answer a different
    // question than the one asked.
    return <String>[
      for (final FileSystemEntity entity in directory.listSync(
        followLinks: false,
      ))
        if (entity is File) entity.uri.pathSegments.last,
    ];
  }

  /// A repository-root-relative key resolved against the bundle's resources.
  ///
  /// The key is used as given, because it is the convention `payload-map.json`
  /// already uses and the paths inside a built artifact have to mirror the paths in
  /// the repository (ADR-0008 decision 3). The `/` separator is the key's, not the
  /// platform's: a payload key is a repository path, and macOS's separator happens
  /// to be the same one.
  Future<String> _path(String key) async => '${await resourceRoot()}/$key';
}
