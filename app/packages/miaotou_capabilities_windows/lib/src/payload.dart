import 'dart:io';
import 'dart:typed_data';

import 'package:miaotou_capabilities_shared/miaotou_capabilities_shared.dart';

/// Windows's half of the payload seam: one directory, and a path per key.
///
/// The directory is where the build copied the payload — beside the executable by
/// default, or wherever a test points it. What a *key* is, and what a missing one
/// means, are [PayloadReader]'s rather than this class's; the three ports used to
/// answer those separately and disagreed.
final class WindowsPayloadTree implements PayloadTree {
  WindowsPayloadTree([Directory? executableDirectory])
    : _root = executableDirectory ?? File(Platform.resolvedExecutable).parent;

  final Directory _root;

  @override
  Future<Uint8List?> readFile(String key) async {
    final File file = _path(key);
    return file.existsSync() ? file.readAsBytes() : null;
  }

  @override
  Future<List<String>?> listFiles(String key) async {
    final Directory directory = Directory(_path(key).path);
    if (!directory.existsSync()) {
      return null;
    }
    return <String>[
      for (final FileSystemEntity entity in directory.listSync(
        followLinks: false,
      ))
        if (entity is File) entity.uri.pathSegments.last,
    ];
  }

  /// A key's `/`-separated segments joined onto the root with the platform's own
  /// separator, which is not the one the key uses.
  File _path(String key) => File(<String>[
    _root.path,
    ...key.split('/'),
  ].join(Platform.pathSeparator));
}
