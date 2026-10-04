import 'dart:convert';
import 'dart:io';

import 'native.dart';

/// One JSON file under the application container, read and written as a map.
///
/// **The seam's only job here is the directory.** Under the sandbox, the home
/// directory is not writable, and `NSApplicationSupportDirectory` is what the
/// system hands a sandboxed app for exactly this — so the path has to come from
/// the platform. What the file *says*, how it is encoded, when it is rewritten
/// and what a corrupt one means are all decisions a test can make, and all of
/// them live here in pure Dart.
///
/// ## Why JSON and not a property list or a database
///
/// ADR-0010 decision 3 leaves the format to the implementation, and the three
/// candidates were a plist, sqlite and JSON. JSON because there is no sqlite in a
/// sandboxed Flutter app's Dart side and no reason to add one for a few hundred
/// rows; a plist because `PropertyListSerialization` has no Dart implementation
/// in this package and hand-rolling one would be a second encoder to keep
/// correct. The cost is that a store is human-readable, which for a file holding
/// the user's own settings and notes is a feature rather than a leak.
///
/// ## Why writes are atomic
///
/// Every write goes to a sibling `.tmp` and is then renamed over the target. A
/// crash, a full disk or a killed process between the two steps leaves the
/// previous file intact instead of a half-written one — and a half-written
/// preferences file is worse than a missing one, because it is unreadable *and*
/// it has already destroyed what was there. `rename` within one directory is
/// atomic on macOS, which is the only platform this file ships to.
/// ## Why there is no cache of the contents
///
/// An earlier version memoised a successful read for the life of the process, on
/// the claim that "every write replaces the cache". That is true of the object
/// that wrote and false of every *other* object over the same path — and another
/// object over the same path is not a hypothetical: `macosCapabilities()` builds
/// a fresh set of stores on every call, and the application resolves them
/// through `capabilitiesForCurrentPlatform()`, which memoises nothing. Two stores
/// over one container file is the ordinary shape of this code, so a reader could
/// sit on a value from before a writer's save and never see it.
///
/// These stores are read-modify-write, which is what makes that a lost update
/// rather than a stale display: `saveNote` reads the whole document, changes one
/// row and writes the whole document back. A stale read there does not show a
/// wrong answer, it writes the other store's changes back over the top of this
/// one's.
///
/// So the contents are read from disk on every call, and the cost is a `stat` and
/// a read of a few kilobytes — beside which the save that follows it rewrites the
/// whole file anyway, and beside the platform channel round trip and the Vision
/// framework calls that surround a capture. A cache here would buy nothing
/// measurable and cost a correctness property that is hard to notice and
/// impossible to argue about later.
///
/// **The directory is still memoised**, and that is a different claim: it comes
/// from the platform channel, it costs a round trip, and it cannot change within
/// a process. See [directory].
final class ContainerFile {
  ContainerFile(this._native, this.fileName);

  final MacosNative _native;

  /// The file's name inside the container directory, e.g. `knowledge.json`.
  final String fileName;

  Future<Directory>? _directory;

  /// The container, created on first use.
  ///
  /// Creating it here rather than in the native layer is deliberate: "make the
  /// directory this app writes into" is a thing a test asserts against a
  /// temporary directory, and a native call would make it the one branch of these
  /// three stores that no test can reach.
  Future<Directory> directory() => _directory ??= _openDirectory();

  Future<Directory> _openDirectory() async {
    final String root = await _native.containerDirectory();
    if (root.isEmpty) {
      throw StateError(
        'the native layer returned no container directory; without a writable '
            'location there is nowhere to keep $fileName',
      );
    }
    final Directory created = Directory(root);
    if (!created.existsSync()) {
      created.createSync(recursive: true);
    }
    return created;
  }

  /// The file itself, which need not exist.
  Future<File> file() async => File('${(await directory()).path}${Platform.pathSeparator}$fileName');

  /// The current contents, or an empty map when the file does not exist yet.
  ///
  /// **A corrupt file is an error, not an empty store.** A store that silently
  /// resets because its JSON did not parse would let a truncated write destroy a
  /// user's knowledge base and then present an empty one as the truth; refusing
  /// to open is the only answer that lets them recover the old file.
  ///
  /// **Nothing is remembered between calls**, neither a success nor a failure —
  /// see the class header for why. A read that failed for a reason which then
  /// went away (a file mid-rewrite, a volume not yet mounted) is recovered from
  /// by asking again, with no relaunch and nothing to reset.
  Future<Map<String, Object?>> read() => _readThrough();

  Future<Map<String, Object?>> _readThrough() async {
    final File source = await file();
    if (!source.existsSync()) {
      return <String, Object?>{};
    }
    final String text = source.readAsStringSync(encoding: utf8);
    if (text.trim().isEmpty) {
      return <String, Object?>{};
    }
    final Object? decoded = jsonDecode(text);
    if (decoded is! Map) {
      throw FormatException(
        '$fileName does not hold a JSON object; refusing to treat it as an '
        'empty store, because that would hide the loss',
        source.path,
      );
    }
    return decoded.cast<String, Object?>();
  }

  /// Replaces the contents.
  ///
  /// No cache to refresh, because there is no cache — see the class header. The
  /// next read comes from the file this method just wrote, because that is where
  /// the data now is.
  Future<void> write(Map<String, Object?> contents) async {
    final File target = await file();
    final File scratch = File('${target.path}.tmp');
    scratch.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(contents),
      encoding: utf8,
      flush: true,
    );
    scratch.renameSync(target.path);
  }
}
