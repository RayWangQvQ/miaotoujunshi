import 'dart:typed_data';

/// The material all three ports read at runtime.
///
/// **It does not travel through Flutter assets** (ADR-0008). A Flutter asset
/// directory entry includes only the files directly inside it, so a new payload
/// file would need a matching `pubspec.yaml` edit to ship at all — precisely the
/// failure ADR-0005 and ADR-0006 were written to remove. Instead each platform's
/// build copies the payload tree whole — Android through its existing Gradle
/// copy task, macOS into `Contents/Resources/`, Windows beside the executable —
/// and this interface is how Dart reads the result on all three.
///
/// Nothing in `pubspec.yaml` will tell a reader how the payload arrives. That is
/// the intended cost, recorded in ADR-0008.
abstract interface class SharedPayload {
  /// Reads one file.
  ///
  /// [repoRelativePath] is a path relative to the repository root, the same
  /// convention `miaotoujunshi/references/data/payload-map.json` already uses,
  /// so that the paths inside a built artifact mirror the paths in the
  /// repository and the payload map needs no rewrite (ADR-0008 decision 3).
  ///
  /// **A missing file is a hard error.** No implementation returns an empty
  /// buffer, a default, or an inlined copy: a caller that gets bytes back must
  /// be able to trust that they came from the payload.
  Future<Uint8List> read(String repoRelativePath);

  /// Lists the file names directly inside [repoRelativeDir].
  ///
  /// It exists so a caller can enumerate a payload directory without a
  /// hard-coded member list, which is what makes a zero-change addition
  /// observable at runtime rather than only in a build log (ADR-0008 decision 5).
  Future<List<String>> list(String repoRelativeDir);
}
