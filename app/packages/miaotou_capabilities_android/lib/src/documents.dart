import 'package:miaotou_capabilities_shared/miaotou_capabilities_shared.dart';

import 'storage_native.dart';

/// Android's half of the storage seam: two channel calls, one per direction.
///
/// The channel already speaks in exactly this shape — `document.read` takes a name
/// and answers text or nothing, `document.write` takes a name and text — so this
/// class is a forward and nothing more. What it deliberately does **not** do is
/// parse: the JSON, the refusal of a document that is not an object and the record
/// shape are the shared modules' business, and `AndroidJsonDocument` used to carry
/// its own copy of the first two.
///
/// **Atomicity is the native side's, and it is already there.** `writeDocument` in
/// `AndroidStorageHost.kt` writes through `android.util.AtomicFile` with an
/// `fd.sync()` before `finishWrite`, which is the same guarantee macOS gets from
/// its `.tmp` sibling and `rename`. That is why [TextDocuments] can make atomicity
/// an obligation on the implementation without any port having to grow a
/// workaround.
///
/// Android keeps its documents under `filesDir/storage`, an app-private directory
/// the Dart side never names: the name and the path validation live behind the
/// channel, in `AndroidStorageHost.kt`'s `document(name)`.
final class AndroidDocuments implements TextDocuments {
  AndroidDocuments(this._native);

  final AndroidStorageNative _native;

  @override
  Future<String?> readText(String name) => _native.readDocument(name);

  @override
  Future<void> writeText(String name, String contents) =>
      _native.writeDocument(name, contents);
}
