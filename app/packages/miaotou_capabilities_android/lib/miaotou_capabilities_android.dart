/// The Android answer to every member of the capability contract.
///
/// The package declares all eleven capabilities and every member of each. Ingest,
/// panel, permission and device storage operations cross into the retained Kotlin
/// layer; payload validation, persisted formats and policy stay in Dart.
library;

export 'src/bundle.dart';
export 'src/capabilities.dart';
export 'src/ingest_native.dart';
export 'src/knowledge.dart';
export 'src/memory.dart';
export 'src/panel_native.dart';
export 'src/permission_native.dart';
export 'src/payload.dart';
export 'src/preferences.dart';
export 'src/secrets.dart';
export 'src/storage_native.dart';
