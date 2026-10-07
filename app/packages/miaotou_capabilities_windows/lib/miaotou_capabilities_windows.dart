/// The Windows answer to every member of the capability contract.
///
/// The package declares all eleven capabilities, and every member of each. Most of
/// them refuse for now — the work is in #17, #18 and #19 — and two refuse
/// permanently: a desktop port has no accessibility node tree to read, so
/// `UiTreeReader` throws `UnsupportedError` here and in the macOS package alike,
/// and the two system permissions in the contract are Android's, so `Permissions`
/// refuses here too (ADR-0009 decision 2, ADR-0021).
///
/// The point of declaring refusals rather than omitting the members is that the
/// compiler asks this package for all of them. A capability cannot be added to
/// the contract without this file ceasing to compile.
library;

export 'src/bundle.dart';
export 'src/capabilities.dart';
export 'src/documents.dart';
export 'src/native.dart';
export 'src/panel.dart';
export 'src/panel_exclusion.dart';
export 'src/panel_native.dart';
export 'src/payload.dart';
export 'src/secrets.dart';
export 'src/shared_memory.dart' show SharedFrameReader;

// What the three ports share is re-exported rather than hidden: this package's own
// signatures take a `CapturePacing`, and a type that appears in the public API has
// to be reachable from the same import that names it. The class it replaced here
// was `WindowsCapturePacing`, which was the same class under a platform name.
export 'package:miaotou_capabilities_shared/miaotou_capabilities_shared.dart';
