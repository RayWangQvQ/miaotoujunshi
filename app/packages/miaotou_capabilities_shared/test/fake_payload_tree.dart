import 'dart:convert';
import 'dart:typed_data';

import 'package:miaotou_capabilities_shared/miaotou_capabilities_shared.dart';

/// An in-process [PayloadTree], so the reader can be exercised with no disk and
/// no bundle.
///
/// The tree is the one place the three ports differ, and its whole contract is
/// "bytes or null, names or null", so a map of strings is a *complete*
/// implementation of it rather than a stand-in. Everything the reader does —
/// validating the key, deciding what absence means, sorting the listing — happens
/// above this class and is therefore under test here.
final class FakePayloadTree implements PayloadTree {
  final Map<String, Uint8List> files = <String, Uint8List>{};

  /// Puts a file in the tree, the way a build phase would.
  void put(String key, String contents) =>
      files[key] = Uint8List.fromList(utf8.encode(contents));

  /// The raw text at [key], for a test that wants to look at what a tree holds.
  String? raw(String key) =>
      files[key] == null ? null : utf8.decode(files[key]!);

  @override
  Future<Uint8List?> readFile(String key) async {
    final Uint8List? bytes = files[key];
    // A copy, because a real tree reads the file on every call and a caller that
    // mutated the buffer it was handed would otherwise corrupt the fake.
    return bytes == null ? null : Uint8List.fromList(bytes);
  }

  @override
  Future<List<String>?> listFiles(String key) async {
    final String prefix = '$key/';
    // Derived from the files rather than from a directory map, so that "a file
    // added to the payload appears with no code change" is a property of the fake
    // too. The cost is that a *genuinely* empty directory reads as absent, which
    // is why no test here asserts one.
    final List<String> names = <String>[
      for (final String path in files.keys)
        if (path.startsWith(prefix) &&
            !path.substring(prefix.length).contains('/'))
          path.substring(prefix.length),
    ];
    return names.isEmpty ? null : names;
  }
}
