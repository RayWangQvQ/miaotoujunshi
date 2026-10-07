/// The Android answer to every member of the capability contract.
///
/// The package declares all eleven capabilities and every member of each. Ingest,
/// panel, permission and the device's storage operations cross into the retained
/// Kotlin layer; payload validation, the document formats and policy stay in Dart.
///
/// The storage members share one document seam with the two desktop ports, so what
/// a settings, knowledge or memory document *says* is defined once — see
/// `miaotou_capabilities_shared`. What is left in Kotlin behind this port is assets,
/// the Keystore and app-private files.
library;

export 'src/bundle.dart';
export 'src/capabilities.dart';
export 'src/documents.dart';
export 'src/ingest_native.dart';
export 'src/panel_native.dart';
export 'src/permission_native.dart';
export 'src/payload.dart';
export 'src/secrets.dart';
export 'src/storage_native.dart';

// What the three ports share is re-exported rather than hidden: [AndroidDocuments]
// implements `TextDocuments`, and a type that appears in the public API has to be
// reachable from the same import that names it. The same comment is in the macOS
// and Windows barrels, which is the point — the three now have one storage story.
export 'package:miaotou_capabilities_shared/miaotou_capabilities_shared.dart';
