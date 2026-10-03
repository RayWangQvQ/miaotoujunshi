import 'package:miaotou_capabilities/miaotou_capabilities.dart';

import 'capabilities.dart';

/// Every capability this port answers for, together.
///
/// Passing all ten to [CapabilitySet] is what makes "every port answers for every
/// member" a compile-time property: leaving one out does not produce a partial
/// set, it produces a file that does not build.
CapabilitySet windowsCapabilities() => const CapabilitySet(
      screenCapture: WindowsScreenCapture(),
      uiTreeReader: WindowsUiTreeReader(),
      ocr: WindowsOcr(),
      textInject: WindowsTextInject(),
      floatingPanel: WindowsFloatingPanel(),
      sharedPayload: WindowsSharedPayload(),
      preferences: WindowsPreferences(),
      secretStore: WindowsSecretStore(),
      knowledgeStore: WindowsKnowledgeStore(),
      memoryStore: WindowsMemoryStore(),
    );
