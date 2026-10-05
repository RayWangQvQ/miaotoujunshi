import 'package:miaotou_capabilities/miaotou_capabilities.dart';

import 'capabilities.dart';
import 'knowledge.dart';
import 'memory.dart';
import 'native.dart';
import 'pacing.dart';
import 'payload.dart';
import 'preferences.dart';
import 'secrets.dart';

/// Every capability this port answers for, together.
///
/// Passing all eleven to [CapabilitySet] is what makes "every port answers for every
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
///
/// The five storage members are all built over the one seam and share nothing but
/// its container directory. Each owns its own file in it — `preferences.json`,
/// `knowledge.json`, `memory.json` — and the Keychain, which owns nothing on disk
/// at all. They are separate objects rather than one "storage" object because the
/// contract has five capabilities and a bundle that merged them would be a place
/// where answering for one means being asked about all five.
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
    permissions: const MacosPermissions(),
    sharedPayload: MacosSharedPayload(seam),
    preferences: MacosPreferences.inContainer(seam),
    secretStore: MacosSecretStore(seam),
    knowledgeStore: MacosKnowledgeStore.inContainer(seam),
    memoryStore: MacosMemoryStore.inContainer(seam),
  );
}
