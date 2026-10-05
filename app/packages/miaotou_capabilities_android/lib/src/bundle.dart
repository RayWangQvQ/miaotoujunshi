import 'package:miaotou_capabilities/miaotou_capabilities.dart';

import 'capabilities.dart';
import 'ingest_native.dart';
import 'knowledge.dart';
import 'memory.dart';
import 'panel_native.dart';
import 'payload.dart';
import 'preferences.dart';
import 'secrets.dart';
import 'storage_native.dart';

/// Every capability this port answers for, together.
///
/// Passing all ten to [CapabilitySet] is what makes "every port answers for every
/// member" a compile-time property: leaving one out does not produce a partial
/// set, it produces a file that does not build.
CapabilitySet androidCapabilities({
  AndroidPanelNative? panelNative,
  AndroidIngestNative? ingestNative,
  AndroidStorageNative? storageNative,
}) {
  final AndroidIngestNative ingest =
      ingestNative ?? MethodChannelAndroidIngestNative();
  final AndroidStorageNative storage =
      storageNative ?? MethodChannelAndroidStorageNative();
  return CapabilitySet(
    screenCapture: AndroidScreenCapture(ingest),
    uiTreeReader: AndroidUiTreeReader(ingest),
    ocr: AndroidOcr(ingest),
    textInject: AndroidTextInject(ingest),
    floatingPanel: AndroidFloatingPanel(native: panelNative),
    sharedPayload: AndroidSharedPayload(storage),
    preferences: AndroidPreferences(storage),
    secretStore: AndroidSecretStore(storage),
    knowledgeStore: AndroidKnowledgeStore(storage),
    memoryStore: AndroidMemoryStore(storage),
  );
}
