import 'package:miaotou_capabilities/miaotou_capabilities.dart';

import 'capabilities.dart';
import 'native.dart';
import 'pacing.dart';

/// Every capability this port answers for, together.
///
/// Passing all ten to [CapabilitySet] is what makes "every port answers for every
/// member" a compile-time property: leaving one out does not produce a partial
/// set, it produces a file that does not build.
///
/// [native] exists so a test can put a scripted system underneath this port
/// instead of a Mac. The default is the real method channel, so the production
/// call site stays the bare one: choosing the seam must not be something a caller
/// can forget to do.
///
/// The panel and the capture are built together on purpose. The capture has to
/// take the panel out of its own shot, so the two cannot be independent objects,
/// and a bundle that let a caller pass one of each would be a way to wire a
/// capture that photographs the panel.
CapabilitySet macosCapabilities({
  MacosNative? native,
  CapturePacing? pacing,
}) {
  final MacosNative seam = native ?? MethodChannelMacosNative();
  final MacosFloatingPanel panel = MacosFloatingPanel(seam);
  return CapabilitySet(
    screenCapture: MacosScreenCapture(seam, panel, pacing: pacing),
    uiTreeReader: const MacosUiTreeReader(),
    ocr: MacosOcr(seam),
    textInject: MacosTextInject(seam),
    floatingPanel: panel,
    sharedPayload: const MacosSharedPayload(),
    preferences: const MacosPreferences(),
    secretStore: const MacosSecretStore(),
    knowledgeStore: const MacosKnowledgeStore(),
    memoryStore: const MacosMemoryStore(),
  );
}
