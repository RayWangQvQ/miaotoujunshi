import 'dart:io';
import 'dart:typed_data';

import 'package:miaotou_capabilities/miaotou_capabilities.dart';

final class WindowsSharedPayload implements SharedPayload {
  WindowsSharedPayload([Directory? executableDirectory])
    : _root = executableDirectory ?? File(Platform.resolvedExecutable).parent;

  final Directory _root;

  @override
  Future<Uint8List> read(String repoRelativePath) async {
    final File file = File(_absolute(repoRelativePath));
    if (!file.existsSync()) {
      throw FileSystemException(
        'the shared payload has no file at this key; the package is incomplete',
        file.path,
      );
    }
    return file.readAsBytes();
  }

  @override
  Future<List<String>> list(String repoRelativeDir) async {
    final Directory directory = Directory(_absolute(repoRelativeDir));
    if (!directory.existsSync()) {
      throw FileSystemException(
        'the shared payload has no directory at this key; the package is incomplete',
        directory.path,
      );
    }
    return <String>[
      for (final FileSystemEntity entity in directory.listSync(
        followLinks: false,
      ))
        if (entity is File) entity.uri.pathSegments.last,
    ]..sort();
  }

  String _absolute(String key) {
    final List<String> segments = key.split('/');
    if (key.isEmpty ||
        key.startsWith('/') ||
        key.startsWith(r'\') ||
        segments.contains('..') ||
        segments.any((String segment) => segment.contains(r'\'))) {
      throw ArgumentError.value(
        key,
        'repoRelativePath',
        'must remain inside the packaged payload tree',
      );
    }
    return <String>[_root.path, ...segments].join(Platform.pathSeparator);
  }
}
