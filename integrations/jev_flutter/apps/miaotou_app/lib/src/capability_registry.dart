import 'dart:io';

import 'package:miaotou_capabilities/miaotou_capabilities.dart';
import 'package:miaotou_capabilities_android/miaotou_capabilities_android.dart';
import 'package:miaotou_capabilities_macos/miaotou_capabilities_macos.dart';
import 'package:miaotou_capabilities_windows/miaotou_capabilities_windows.dart';

/// The one place in the application that asks what it is running on.
///
/// ADR-0009 makes the contract the only boundary the three ports may differ
/// across, which means the *decision* about which port this is has to be made
/// exactly once and as early as possible. This is that place. Everything else
/// takes a [CapabilitySet] as a parameter, and nothing else in `lib/` imports a
/// platform package or `dart:io`.
///
/// There is no per-target selection in `pubspec.yaml` to do this for us: the
/// interface package is pure Dart by decision, so there is no federated plugin
/// and no `default_package` for the tool to read.
CapabilitySet capabilitiesForCurrentPlatform() {
  if (Platform.isAndroid) {
    return androidCapabilities();
  }
  if (Platform.isMacOS) {
    return macosCapabilities();
  }
  if (Platform.isWindows) {
    return windowsCapabilities();
  }
  throw UnsupportedError(
    'this application is built for Android, Windows and macOS; it is running on '
    '${Platform.operatingSystem}',
  );
}
