import 'dart:typed_data';

import 'package:miaotou_capabilities_shared/miaotou_capabilities_shared.dart';

import 'storage_native.dart';

/// Android's half of the payload seam: two channel calls, one per direction.
///
/// The payload is inside the APK — `context.assets`, reached through
/// `AndroidStorageHost.kt` — so "there is no file at this key" and "this package is
/// incomplete" are the same fact on this port, and the native half reports both the
/// same way: null. What a *key* is, and what a null means, are [PayloadReader]'s,
/// so the four refusals this port used to word itself are now the same words as
/// macOS's and Windows's.
///
/// **The path validation is deliberately here as well as above.** Kotlin keeps
/// `validatePayloadPath`, and the shared reader refuses the same keys. Two checks,
/// because the Kotlin one is the device-side boundary: an `assets` lookup is an
/// `assets` lookup whatever the Dart above it did, and a port that reached the
/// channel by some other route must not be able to name a path outside the tree.
final class AndroidPayloadTree implements PayloadTree {
  AndroidPayloadTree(this._native);

  final AndroidStorageNative _native;

  @override
  Future<Uint8List?> readFile(String key) => _native.readPayload(key);

  @override
  Future<List<String>?> listFiles(String key) => _native.listPayload(key);
}
