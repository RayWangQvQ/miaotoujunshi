import 'dart:convert';
import 'dart:io';

import 'package:miaotou_capabilities_shared/miaotou_capabilities_shared.dart';

import 'native.dart';

/// macOS's half of the storage seam: one directory, and a file per name in it.
///
/// **The seam's only job here is the directory.** Under the sandbox, the home
/// directory is not writable, and `NSApplicationSupportDirectory` is what the
/// system hands a sandboxed app for exactly this — so the path has to come from
/// the platform. What a document *says*, how it is encoded, when it is rewritten
/// and what a corrupt one means are decisions the shared modules make, and the
/// reasoning behind each of them is in [JsonDocument].
///
/// ## Why writes are atomic
///
/// Every write goes to a sibling `.tmp` and is then renamed over the target. A
/// crash, a full disk or a killed process between the two steps leaves the
/// previous file intact instead of a half-written one — and a half-written
/// preferences file is worse than a missing one, because it is unreadable *and*
/// it has already destroyed what was there. `rename` within one directory is
/// atomic on macOS, which is the only platform this file ships to.
///
/// ## Why the directory is memoised and the contents are not
///
/// They are different claims. The directory comes from the platform channel, it
/// costs a round trip, and it cannot change within a process — so it is asked for
/// once and kept. The contents *can* change within a process, because two stores
/// over one file is the ordinary shape of this code, so they are read from disk
/// every time; [JsonDocument]'s class comment has that argument in full.
///
/// One object per port, not one per document, is what makes the memoisation worth
/// having: [ContainerDocuments] hands out every name a port keeps, so the three
/// stores in a bundle share the one answer.
final class ContainerDocuments implements TextDocuments {
  ContainerDocuments(this._native);

  final MacosNative _native;

  Future<Directory>? _directory;

  /// The container, created on first use.
  ///
  /// Creating it here rather than in the native layer is deliberate: "make the
  /// directory this app writes into" is a thing a test asserts against a
  /// temporary directory, and a native call would make it the one branch of these
  /// stores that no test can reach.
  Future<Directory> directory() => _directory ??= _openDirectory();

  Future<Directory> _openDirectory() async {
    final String root = await _native.containerDirectory();
    if (root.isEmpty) {
      throw StateError(
        'the native layer returned no container directory; without a writable '
        'location there is nowhere to keep the app\'s own documents',
      );
    }
    final Directory created = Directory(root);
    if (!created.existsSync()) {
      created.createSync(recursive: true);
    }
    return created;
  }

  /// The file itself, which need not exist.
  Future<File> file(String name) async =>
      File('${(await directory()).path}${Platform.pathSeparator}$name');

  @override
  Future<String?> readText(String name) async {
    final File source = await file(name);
    if (!source.existsSync()) {
      return null;
    }
    return source.readAsStringSync(encoding: utf8);
  }

  @override
  Future<void> writeText(String name, String contents) async {
    final File target = await file(name);
    final File scratch = File('${target.path}.tmp');
    scratch.writeAsStringSync(contents, encoding: utf8, flush: true);
    scratch.renameSync(target.path);
  }
}
