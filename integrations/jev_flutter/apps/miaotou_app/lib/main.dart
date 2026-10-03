import 'package:flutter/material.dart';

import 'src/app.dart';
import 'src/capability_registry.dart';

void main() {
  // The one line that knows what it is running on. Everything below `runApp`
  // receives the capability set rather than looking for one, which is what lets a
  // test drive the whole application with no device attached (ADR-0009).
  runApp(MiaotouApp(capabilities: capabilitiesForCurrentPlatform()));
}
