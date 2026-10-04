import 'package:miaotou_capabilities/miaotou_capabilities.dart';

import 'capabilities.dart';
import 'native.dart';

/// Every capability this port answers for, together.
///
/// Passing all ten to [CapabilitySet] is what makes "every port answers for every
/// member" a compile-time property: leaving one out does not produce a partial
/// set, it produces a file that does not build.
CapabilitySet windowsCapabilities({WindowsNative? native}) {
  final WindowsNative platform = native ?? ProcessWindowsNative();
  return CapabilitySet(
    screenCapture: WindowsScreenCapture(platform),
    uiTreeReader: const WindowsUiTreeReader(),
    ocr: WindowsOcr(platform),
    textInject: WindowsTextInject(platform),
    floatingPanel: const WindowsFloatingPanel(),
    sharedPayload: const WindowsSharedPayload(),
    preferences: const WindowsPreferences(),
    secretStore: const WindowsSecretStore(),
    knowledgeStore: const WindowsKnowledgeStore(),
    memoryStore: const WindowsMemoryStore(),
  );
}
