import 'package:miaotou_capabilities/miaotou_capabilities.dart';

import 'capabilities.dart';

/// Every capability this port answers for, together.
///
/// Passing all ten to [CapabilitySet] is what makes "every port answers for every
/// member" a compile-time property: leaving one out does not produce a partial
/// set, it produces a file that does not build.
CapabilitySet macosCapabilities() => const CapabilitySet(
      screenCapture: MacosScreenCapture(),
      uiTreeReader: MacosUiTreeReader(),
      ocr: MacosOcr(),
      textInject: MacosTextInject(),
      floatingPanel: MacosFloatingPanel(),
      sharedPayload: MacosSharedPayload(),
      preferences: MacosPreferences(),
      secretStore: MacosSecretStore(),
      knowledgeStore: MacosKnowledgeStore(),
      memoryStore: MacosMemoryStore(),
    );
