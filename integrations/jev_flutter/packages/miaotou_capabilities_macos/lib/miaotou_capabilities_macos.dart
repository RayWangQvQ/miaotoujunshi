/// The macOS answer to every member of the capability contract.
///
/// The package declares all ten capabilities, and every member of each. Nine of
/// them are built: capture, OCR, injection and the floating panel (#14), and the
/// shared payload, preferences, the Keychain, the knowledge base and the memory
/// store (#15). One refuses permanently: a desktop port has no accessibility node
/// tree to read, so `UiTreeReader` throws `UnsupportedError` here and in the
/// Windows package alike (ADR-0009 decision 2).
///
/// The point of declaring refusals rather than omitting the members is that the
/// compiler asks this package for all of them. A capability cannot be added to
/// the contract without this file ceasing to compile.
library;

export 'src/bundle.dart';
export 'src/capabilities.dart';
export 'src/container_file.dart';
export 'src/knowledge.dart';
export 'src/memory.dart';
export 'src/native.dart';
export 'src/pacing.dart';
export 'src/payload.dart';
export 'src/perception.dart';
export 'src/placement.dart';
export 'src/preferences.dart';
export 'src/secrets.dart';
