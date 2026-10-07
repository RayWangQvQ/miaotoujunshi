import 'dart:io';

import 'package:miaotou_capabilities/miaotou_capabilities.dart';
import 'package:miaotou_capabilities_shared/miaotou_capabilities_shared.dart';

import 'capabilities.dart';
import 'documents.dart';
import 'native.dart';
import 'panel.dart';
import 'panel_native.dart';
import 'payload.dart';
import 'secrets.dart';

/// Every capability this port answers for, together.
///
/// Passing all eleven to [CapabilitySet] is what makes "every port answers for every
/// member" a compile-time property: leaving one out does not produce a partial
/// set, it produces a file that does not build.
CapabilitySet windowsCapabilities({
  WindowsNative? native,
  WindowsPanelNative? panelNative,
  Directory? executableDirectory,
  Directory? applicationDataDirectory,
  WindowsCredentialBackend? credentialBackend,
}) {
  final WindowsNative platform = native ?? ProcessWindowsNative();
  final WindowsFloatingPanel panel = WindowsFloatingPanel(
    panelNative ?? DesktopMultiWindowPanelNative(),
  );
  // One seam object for all three stores, so the directory is resolved once and
  // the environment is read at most once per bundle.
  final WindowsDocuments documents = applicationDataDirectory == null
      ? WindowsDocuments.inApplicationData()
      : WindowsDocuments(applicationDataDirectory);
  return CapabilitySet(
    screenCapture: WindowsScreenCapture(platform),
    uiTreeReader: const WindowsUiTreeReader(),
    ocr: WindowsOcr(platform),
    textInject: WindowsTextInject(platform),
    floatingPanel: panel,
    permissions: const WindowsPermissions(),
    sharedPayload: PayloadReader(WindowsPayloadTree(executableDirectory)),
    preferences: PreferenceLedger(documents),
    secretStore: WindowsSecretStore(credentialBackend),
    knowledgeStore: KnowledgeLedger(documents),
    memoryStore: MemoryLedger(documents),
  );
}
