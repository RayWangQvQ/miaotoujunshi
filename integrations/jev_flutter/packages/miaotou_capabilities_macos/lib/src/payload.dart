import 'dart:io';
import 'dart:typed_data';

import 'package:miaotou_capabilities/miaotou_capabilities.dart';

import 'native.dart';

/// macOS's answer for the shared payload.
///
/// Owned by #15. **The payload is read as real files out of
/// `.app/Contents/Resources/`,** which is what keeps ADR-0008 decision 2 literally
/// true: a packaged port reads the same bytes from the same tree the repository
/// holds, and there is no second copy anywhere — not in `pubspec.yaml`, not
/// inlined in Dart, not baked into the binary.
///
/// ## What is native and what is not
///
/// The seam supplies one string, the resource root, because a packaged app has
/// no idea where its own bundle is. Everything else here is `dart:io`, and that
/// split is what the tests below exploit: they hand this class a temporary
/// directory and exercise the join, the read, the listing and the refusal of a
/// missing key with no Mac and no `.app` anywhere.
///
/// ## Why there is no fallback
///
/// A missing file throws. The three shapes a fallback takes — an empty buffer, a
/// default document, a copy compiled into the port — are indistinguishable from
/// a real answer at the call site, and the caller is a prompt: a silently empty
/// strategy guide produces a confident reply to a question nobody asked
/// (ADR-0005, ADR-0008 decision 4).
final class MacosSharedPayload implements SharedPayload {
  MacosSharedPayload(this._native);

  final MacosNative _native;
  Future<String>? _root;

  /// The bundle's resource directory, asked for at most once per store.
  ///
  /// Memoised because it cannot change within a process and a scene load reads a
  /// dozen files: asking the channel each time would put a platform round trip in
  /// the middle of every document read for a value that is a constant. The
  /// memoising is of *this* value only — the files under it are read fresh every
  /// time, which is the same split `ContainerFile` makes for the container.
  ///
  /// The empty answer is refused here as well as in the channel implementation,
  /// because [MacosNative] is an interface: this class cannot assume the only
  /// implementation of it is the one that throws. Joining onto an empty root
  /// yields `/…`, an absolute path out of the filesystem root, and the resulting
  /// "no such file" would name a path this application never meant to read.
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
  Future<Uint8List> read(String repoRelativePath) async {
    final File file = File(_absolute(await resourceRoot(), repoRelativePath));
    if (!file.existsSync()) {
      // A FileSystemException rather than a bespoke error, so the shape matches
      // the one `dart:io` itself raises for a missing read and a caller cannot
      // mistake an absent payload file for a different kind of failure by
      // catching a narrower type.
      throw FileSystemException(
        'the shared payload has no file at this key; this is a packaging fault, '
        'not a missing document',
        file.path,
      );
    }
    return file.readAsBytes();
  }

  @override
  Future<List<String>> list(String repoRelativeDir) async {
    final Directory directory =
        Directory(_absolute(await resourceRoot(), repoRelativeDir));
    if (!directory.existsSync()) {
      throw FileSystemException(
        'the shared payload has no directory at this key; this is a packaging '
        'fault, not an empty payload',
        directory.path,
      );
    }
    // Only files, and only the ones directly inside: the contract asks for the
    // names in one directory, and a recursive walk here would answer a different
    // question than the one asked.
    final List<String> names = <String>[
      for (final FileSystemEntity entity in directory.listSync(followLinks: false))
        if (entity is File) entity.uri.pathSegments.last,
    ]..sort();
    return names;
  }

  /// A repository-root-relative key resolved against the bundle's resources.
  ///
  /// The key is used as given, because it is the convention `payload-map.json`
  /// already uses and the paths inside a built artifact have to mirror the paths
  /// in the repository (ADR-0008 decision 3). The one guard added is not about
  /// tidiness: a key that walked out of the resource root would read a file the
  /// bundle does not ship, and the whole point of resolving keys against the
  /// bundle is that the bundle is the whole world.
  static String _absolute(String resourceRoot, String repoRelativeKey) {
    if (repoRelativeKey.isEmpty ||
        repoRelativeKey.startsWith('/') ||
        repoRelativeKey.split('/').contains('..')) {
      throw ArgumentError.value(
        repoRelativeKey,
        'repoRelativeKey',
        'a payload key is a repository-root-relative path inside the payload '
            'tree, and this one leaves it',
      );
    }
    return '$resourceRoot/$repoRelativeKey';
  }
}
