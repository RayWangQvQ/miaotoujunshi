import 'dart:io';

import 'package:miaotou_capabilities/miaotou_capabilities.dart';

import 'capabilities.dart';
import 'json_file.dart';
import 'native.dart';
import 'knowledge.dart';
import 'memory.dart';
import 'panel.dart';
import 'panel_native.dart';
import 'payload.dart';
import 'preferences.dart';
import 'secrets.dart';

/// Every capability this port answers for, together.
///
/// Passing all ten to [CapabilitySet] is what makes "every port answers for every
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
  return CapabilitySet(
    screenCapture: WindowsScreenCapture(platform),
    uiTreeReader: const WindowsUiTreeReader(),
    ocr: WindowsOcr(platform),
    textInject: WindowsTextInject(platform),
    floatingPanel: panel,
    sharedPayload: WindowsSharedPayload(executableDirectory),
    preferences: applicationDataDirectory == null
        ? WindowsPreferences.inApplicationData()
        : WindowsPreferences(
            WindowsJsonFile(applicationDataDirectory, 'preferences.json'),
          ),
    secretStore: WindowsSecretStore(credentialBackend),
    knowledgeStore: applicationDataDirectory == null
        ? WindowsKnowledgeStore.inApplicationData()
        : WindowsKnowledgeStore(
            WindowsJsonFile(applicationDataDirectory, 'knowledge.json'),
          ),
    memoryStore: applicationDataDirectory == null
        ? WindowsMemoryStore.inApplicationData()
        : WindowsMemoryStore(
            WindowsJsonFile(applicationDataDirectory, 'memory.json'),
          ),
  );
}
