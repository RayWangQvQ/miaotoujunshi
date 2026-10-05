/// The Android answer to every member of the capability contract.
///
/// The package declares all ten capabilities, and every member of each. Every one
/// The ingest and control members are backed by the retained Kotlin layer; the
/// remaining storage members name their owning ticket in every refusal.
/// is a "not yet" rather than a "never": Android is the one port that can reach
/// all ten, because it is the one with an accessibility service behind it.
///
/// The point of declaring refusals rather than omitting the members is that the
/// compiler asks this package for all of them. A capability cannot be added to
/// the contract without the three implementation packages ceasing to compile.
library;

export 'src/bundle.dart';
export 'src/capabilities.dart';
export 'src/ingest_native.dart';
export 'src/panel_native.dart';
