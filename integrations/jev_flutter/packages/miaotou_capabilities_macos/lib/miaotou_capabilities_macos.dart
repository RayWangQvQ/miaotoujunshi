/// The macOS answer to every member of the capability contract.
///
/// The package declares all ten capabilities, and every member of each. Six of
/// them are built (#14): capture, OCR, injection and the floating panel, with
/// their timing, their edge snapping and their perception pipeline. Four refuse
/// as work in flight (#15 — the storage quartet and the payload read), and one
/// refuses permanently: a desktop port has no accessibility node tree to read, so
/// `UiTreeReader` throws `UnsupportedError` here and in the Windows package alike
/// (ADR-0009 decision 2).
///
/// The point of declaring refusals rather than omitting the members is that the
/// compiler asks this package for all of them. A capability cannot be added to
/// the contract without this file ceasing to compile.
library;

export 'src/bundle.dart';
export 'src/capabilities.dart';
export 'src/native.dart';
export 'src/pacing.dart';
export 'src/perception.dart';
export 'src/placement.dart';
