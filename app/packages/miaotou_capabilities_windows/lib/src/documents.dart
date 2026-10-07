import 'dart:convert';
import 'dart:io';

import 'package:miaotou_capabilities_shared/miaotou_capabilities_shared.dart';

/// Windows's half of the storage seam: one directory, and a file per name in it.
///
/// The directory is `%APPDATA%\miaotoujunshi` — the place Windows keeps a
/// user's own application data, and the only thing here that is Windows's
/// business. Everything about what a document *says* is [JsonDocument]'s, and the
/// argument for each of those decisions is in its class comment.
///
/// ## Why writes are atomic
///
/// Every write goes to a sibling `.tmp` and is then renamed over the target, which
/// is atomic on one volume. A crash, a full disk or a killed process between the
/// two steps leaves the previous file intact rather than a half-written one. The
/// port had this before the stores moved and keeps it, because atomicity is an
/// obligation of the seam rather than something the shared modules can arrange
/// from the other side of it.
///
/// ## Why the directory is a callback
///
/// [inApplicationData] has to read the environment, and it must not do that at
/// construction time: a test constructs a bundle to assert that *some* argument
/// was passed through, on a machine where the variable it needs may not exist. So
/// the environment is read on first use, not on the way in.
final class WindowsDocuments implements TextDocuments {
  WindowsDocuments(Directory directory) : _directory = (() => directory);

  factory WindowsDocuments.inApplicationData() =>
      WindowsDocuments._(_applicationDataDirectory);

  WindowsDocuments._(this._directory);

  final Directory Function() _directory;

  Directory get directory => _directory();

  /// The file a name maps to, which need not exist.
  File file(String name) =>
      File('${directory.path}${Platform.pathSeparator}$name');

  @override
  Future<String?> readText(String name) async {
    final File source = file(name);
    if (!source.existsSync()) {
      return null;
    }
    return source.readAsStringSync(encoding: utf8);
  }

  @override
  Future<void> writeText(String name, String contents) async {
    if (!directory.existsSync()) {
      directory.createSync(recursive: true);
    }
    final File target = file(name);
    final File scratch = File('${target.path}.tmp');
    scratch.writeAsStringSync(contents, encoding: utf8, flush: true);
    scratch.renameSync(target.path);
  }

  static Directory _applicationDataDirectory() {
    final String? appData =
        Platform.environment['APPDATA'] ?? Platform.environment['LOCALAPPDATA'];
    if (appData == null || appData.trim().isEmpty) {
      throw StateError(
        'Windows did not provide APPDATA or LOCALAPPDATA; persistent storage '
        'cannot be placed safely',
      );
    }
    return Directory('$appData${Platform.pathSeparator}miaotoujunshi');
  }
}
