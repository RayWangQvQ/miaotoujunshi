import 'package:miaotou_capabilities/miaotou_capabilities.dart';

import 'capabilities.dart';
import 'panel_native.dart';

/// Every capability this port answers for, together.
///
/// Passing all ten to [CapabilitySet] is what makes "every port answers for every
/// member" a compile-time property: leaving one out does not produce a partial
/// set, it produces a file that does not build.
CapabilitySet androidCapabilities({AndroidPanelNative? panelNative}) =>
    CapabilitySet(
      screenCapture: AndroidScreenCapture(),
      uiTreeReader: AndroidUiTreeReader(),
      ocr: AndroidOcr(),
      textInject: AndroidTextInject(),
      floatingPanel: AndroidFloatingPanel(native: panelNative),
      sharedPayload: AndroidSharedPayload(),
      preferences: AndroidPreferences(),
      secretStore: AndroidSecretStore(),
      knowledgeStore: AndroidKnowledgeStore(),
      memoryStore: AndroidMemoryStore(),
    );
