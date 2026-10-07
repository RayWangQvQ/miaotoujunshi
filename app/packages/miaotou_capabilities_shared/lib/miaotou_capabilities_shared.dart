/// The platform-free bodies of the capability implementations.
///
/// ADR-0009 makes `miaotou_capabilities` the only boundary between the three
/// platform implementations and everything above them, and its decision 1 counts
/// **one interface package and three implementation packages**. This package sits
/// *behind* those three rather than beside them: it holds the modules that do not
/// differ by platform, so it is not a fourth port and it adds no cross-port seam.
/// The domain still sees the contract and nothing else.
///
/// ## Why it holds what it holds
///
/// The test for membership is **"do all three ports use this?"**, not "is this
/// platform-free?". `perception.dart` is platform-free and stays in
/// `miaotou_capabilities_macos`, because it is macOS's own calibration and no
/// other port shares it (ADR-0011 decision 6 declines a cross-port conformance
/// assertion for it). `EdgeSnap` and `PanelPositionMemory` are platform-free and
/// stay in the interface package, beside the value type they extend. A package
/// defined by "platform-free" would also have to explain why `miaotou_domain` is
/// not in it; a package defined by "all three use it" has no such question.
///
/// [CapturePacing] answers the test in a different shape and is worth naming: it
/// holds the capture schedule — a one-second floor, a doubling backoff, a
/// three-second watchdog — that Android measured in Kotlin first and still enforces
/// there, because the schedule sits inside the service that hides the panel and
/// takes the screenshot (ADR-0009 decision 3). All three ports obey those numbers;
/// the two Dart ports read them from here, where they used to be two copies of one
/// class under two names.
///
/// ## The seam, and why there is almost none of it
///
/// The modules that touch the platform reach it through one of two small
/// interfaces — [TextDocuments] for one named document's bytes, [PayloadTree] for
/// the packaged payload — and each port implements those in a handful of lines over
/// what it already had (`AndroidStorageNative`'s document pair, macOS's
/// `ContainerFile`, Windows's `WindowsJsonFile`). What used to be three copies of
/// the record shape, the validation, the refusal wording and the undo rule becomes
/// one.
///
/// Nothing here imports `dart:io`, `dart:ffi` or Flutter, and
/// `test/dependency_direction_test.dart` enforces it. That is not decoration: it
/// is what lets every module here be driven by `dart test` on any machine, with no
/// device, no temporary directory and no channel, and it is why a module that
/// needs a path is a module that does not belong here.
library;

export 'src/document.dart';
export 'src/knowledge.dart';
export 'src/memory.dart';
export 'src/pacing.dart';
export 'src/payload.dart';
export 'src/preferences.dart';
