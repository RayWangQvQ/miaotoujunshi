import 'package:miaotou_capabilities_shared/miaotou_capabilities_shared.dart';

/// An in-process [TextDocuments], so a store can be exercised with no disk.
///
/// The seam is "the platform gives bytes", so a fake that holds a map of strings
/// is a *complete* implementation of it rather than a stand-in: everything the
/// stores do with a document — parsing, refusing, encoding, re-reading — happens
/// above this class and is therefore under test here. That is also why this
/// package needs no temporary directory and no `dart:io`.
///
/// It records the names it was asked for in order. `appendLog`'s "a no-op must not
/// touch the document" is the reason: a write count is a sharper statement of that
/// than a file's modification time, which two writes inside one clock tick can
/// hide.
final class FakeDocuments implements TextDocuments {
  final Map<String, String> files = <String, String>{};

  /// Names passed to [writeText], in order, one entry per write.
  final List<String> writes = <String>[];

  /// Names passed to [readText], in order, one entry per read.
  final List<String> reads = <String>[];

  /// Puts a document in place without going through a store, so a test can set
  /// up a hand-written file — a corrupt one, or one written by an older build.
  void put(String name, String contents) => files[name] = contents;

  /// The document's current text, or null when it has never been written.
  String? raw(String name) => files[name];

  /// How many times [name] has been written.
  int writeCount(String name) =>
      writes.where((String written) => written == name).length;

  @override
  Future<String?> readText(String name) async {
    reads.add(name);
    return files[name];
  }

  @override
  Future<void> writeText(String name, String contents) async {
    writes.add(name);
    files[name] = contents;
  }
}
