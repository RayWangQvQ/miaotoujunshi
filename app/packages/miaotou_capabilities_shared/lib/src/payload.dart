import 'dart:typed_data';

import 'package:miaotou_capabilities/miaotou_capabilities.dart';

/// The platform's copy of the packaged payload, addressed by repository-relative
/// keys.
///
/// This is the whole seam [PayloadReader] sits on, and it is deliberately two
/// calls: the platform knows where its own payload ended up — `Contents/Resources`
/// in a macOS bundle, the directory beside a Windows executable, `assets/` behind
/// an Android channel — and nothing above it does.
///
/// **Absence is a null, not an exception.** A tree that threw here would be
/// choosing the diagnosis, and the diagnosis is the one thing the three ports had
/// written three times, three ways. Returning null lets [PayloadReader] be the
/// single place that decides what a missing key means.
///
/// **The key has already been validated** by the time either method is called; a
/// tree may rely on that and does not have to repeat the check. Android's Kotlin
/// half keeps its own `validatePayloadPath` all the same, as the device-side
/// boundary it is.
abstract interface class PayloadTree {
  /// The bytes at [key], or null when there is no file there.
  Future<Uint8List?> readFile(String key);

  /// The names of the files **directly inside** [key], or null when there is no
  /// directory there.
  ///
  /// Not recursive: the contract asks for the names in one directory, and a walk
  /// would answer a different question than the one asked.
  Future<List<String>?> listFiles(String key);
}

/// The shared payload, in the one form all three ports use.
///
/// AC3 of #15 says the packaged application reads the payload **as real files,
/// with no copy inlined into the port**. That claim is about the packaging, and
/// the packaging is described in ADR-0008; what this class answers for is the half
/// of it that is the same on all three platforms.
///
/// ## Why there is no fallback
///
/// A missing file refuses. The three shapes a fallback takes — an empty buffer, a
/// default document, a copy compiled into the port — are indistinguishable from a
/// real answer at the call site, and the caller is a prompt: a silently empty
/// strategy guide produces a confident reply to a question nobody asked (ADR-0005,
/// ADR-0008 decision 4).
///
/// The refusal is a [StateError] with the diagnosis in its message, which is what
/// the other modules here use for "this cannot be answered". macOS threw a
/// `FileSystemException` and Windows threw one with a different message; neither
/// is available to this package, which has no `dart:io` — and Android was already
/// throwing a `StateError` from behind its channel, so this is the one port whose
/// behaviour does not change. The contract itself promises only "a hard error"
/// ([SharedPayload.read]), never a type, and nothing in `lib/` catches either.
///
/// ## Why the key is checked here and the join is not
///
/// The three ports disagreed about what a legal key is: macOS rejected an empty
/// key, a leading `/` and a `..` segment, Windows those three plus a leading `\`
/// and any segment containing one, and Android all five plus an empty segment. The
/// strictest of the three wins, because the two shapes the other two accepted are
/// not keys the payload has: `a//b` names a path the filesystem would silently
/// collapse, and `a\b` is a single file name on macOS rather than a nesting, so
/// accepting it means a caller's typo resolves somewhere plausible-looking.
///
/// What is *not* here is the join, and that is the point of the split: the key is
/// the same on all three platforms, and the string it resolves to is not.
final class PayloadReader implements SharedPayload {
  const PayloadReader(this._tree);

  final PayloadTree _tree;

  @override
  Future<Uint8List> read(String repoRelativePath) async {
    final String key = _key(repoRelativePath, 'repoRelativePath');
    final Uint8List? bytes = await _tree.readFile(key);
    if (bytes == null) {
      throw StateError(
        'the shared payload has no file at $key; this is a packaging fault, not '
        'a missing document',
      );
    }
    return bytes;
  }

  @override
  Future<List<String>> list(String repoRelativeDir) async {
    final String key = _key(repoRelativeDir, 'repoRelativeDir');
    final List<String>? names = await _tree.listFiles(key);
    if (names == null) {
      throw StateError(
        'the shared payload has no directory at $key; this is a packaging '
        'fault, not an empty payload',
      );
    }
    // Sorted, so a caller that renders or compares the listing twice gets the
    // same answer. `listSync` order is the filesystem's, which differs between
    // the three platforms and between two runs on one of them.
    return names..sort();
  }

  /// Rejects a key that is not a repository-relative path inside the payload.
  ///
  /// The one guard, and it is not about tidiness: a key that walked out of the
  /// payload tree would read a file the application does not ship, and resolving
  /// keys against the payload is precisely so that the payload is the whole world.
  static String _key(String key, String argument) {
    final List<String> segments = key.split('/');
    final bool escapes = key.isEmpty ||
        key.startsWith('/') ||
        key.startsWith(r'\') ||
        segments.any(
          (String segment) =>
              segment.isEmpty || segment == '..' || segment.contains(r'\'),
        );
    if (escapes) {
      throw ArgumentError.value(
        key,
        argument,
        'a payload key is a repository-root-relative path inside the payload '
            'tree, and this one leaves it',
      );
    }
    return key;
  }
}
