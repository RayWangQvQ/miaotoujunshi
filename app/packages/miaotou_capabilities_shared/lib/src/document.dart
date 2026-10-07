import 'dart:convert';

/// The platform's raw text store, one named document at a time.
///
/// This is the whole seam the stores sit on. A port implements it in a handful of
/// lines over what it already had — Android's `document.read` / `document.write`
/// channel pair, macOS's `ContainerFile`, Windows's `WindowsJsonFile` — and
/// everything above it, the parsing and the refusal and the record shape, is one
/// implementation rather than three.
///
/// **Two obligations belong to the implementation, and neither is checked here.**
///
/// * **A write is atomic.** It goes to a sibling temporary and is renamed over the
///   target, so a crash, a full disk or a killed process between the two steps
///   leaves the previous document intact instead of a half-written one. A
///   half-written preferences file is worse than a missing one: it is unreadable
///   *and* it has already destroyed what was there.
/// * **Neither reads nor writes are cached.** A cache is the one optimisation that
///   turns this design into lost updates; see [JsonDocument].
abstract interface class TextDocuments {
  /// The document's current text, or null when there is no such document yet.
  ///
  /// An empty or whitespace-only document may be reported either as null or as
  /// the empty string; [JsonDocument] treats both as "nothing stored".
  Future<String?> readText(String name);

  /// Replaces the document's text. See the class comment for the atomicity
  /// obligation.
  Future<void> writeText(String name, String contents);
}

/// One named document, read and written as a flat JSON object.
///
/// ## Why JSON and not a property list or a database
///
/// ADR-0010 decision 3 leaves the format to the implementation, and the three
/// candidates were a plist, sqlite and JSON. JSON because there is no sqlite in a
/// sandboxed Flutter app's Dart side and no reason to add one for a few hundred
/// rows, and because a plist has no Dart implementation in this tree — hand-rolling
/// one would be a second encoder to keep correct. The cost is that a store is
/// human-readable, which for a file holding the user's own settings and notes is a
/// feature rather than a leak.
///
/// ## A corrupt document is an error, not an empty store
///
/// A store that silently resets because its JSON did not parse would let a
/// truncated write destroy a user's knowledge base and then present an empty one
/// as the truth. Refusing to open is the only answer that lets them recover the
/// old file, so a document that does not hold an object throws [FormatException]
/// and stays unopened until someone looks at it.
///
/// ## Why nothing is remembered between calls
///
/// An earlier version memoised a successful read for the life of the process, on
/// the claim that "every write replaces the cache". That is true of the object
/// that wrote and false of every *other* object over the same document — and
/// another object over the same document is not a hypothetical: each port builds a
/// fresh set of stores whenever its bundle factory is called, and the application
/// resolves them through `capabilitiesForCurrentPlatform()`, which memoises
/// nothing.
///
/// These stores are read-modify-write, which is what makes that a lost update
/// rather than a stale display: `saveNote` reads the whole document, changes one
/// row and writes the whole document back. A stale read there does not show a
/// wrong answer, it writes the other store's changes back over the top of this
/// one's.
///
/// So the contents are read through [TextDocuments] on every call, and the cost is
/// a `stat` and a read of a few kilobytes — beside which the save that follows it
/// rewrites the whole document anyway, and beside the channel round trip and the
/// framework calls that surround a capture.
final class JsonDocument {
  const JsonDocument(this._documents, this.name);

  final TextDocuments _documents;

  /// The file name inside whatever directory the platform keeps documents in,
  /// e.g. `knowledge.json`. Used in the refusal message, so a reader is told which
  /// file to go and look at.
  final String name;

  /// The current contents, or an empty map when there is no document yet.
  Future<Map<String, Object?>> read() async {
    final String? text = await _documents.readText(name);
    if (text == null || text.trim().isEmpty) {
      return <String, Object?>{};
    }
    final Object? decoded = jsonDecode(text);
    if (decoded is! Map) {
      throw FormatException(
        '$name does not hold a JSON object; refusing to treat it as an empty '
        'store, because that would hide the loss',
        name,
      );
    }
    return decoded.cast<String, Object?>();
  }

  /// Replaces the contents.
  ///
  /// No cache to refresh, because there is none — see the class comment. The next
  /// read comes from the document this method just wrote, because that is where
  /// the data now is.
  Future<void> write(Map<String, Object?> contents) => _documents.writeText(
    name,
    const JsonEncoder.withIndent('  ').convert(contents),
  );
}
