/// The Windows answer to every member of the capability contract.
///
/// The package declares all ten capabilities, and every member of each. Most of
/// them refuse for now — the work is in #17, #18 and #19 — and one of them
/// refuses permanently: a desktop port has no accessibility node tree to read, so
/// `UiTreeReader` throws `UnsupportedError` here and in the macOS package alike
/// (ADR-0009 decision 2).
///
/// The point of declaring refusals rather than omitting the members is that the
/// compiler asks this package for all of them. A capability cannot be added to
/// the contract without this file ceasing to compile.
library;

export 'src/bundle.dart';
export 'src/capabilities.dart';
