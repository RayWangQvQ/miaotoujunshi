import 'package:flutter/material.dart';
import 'package:miaotou_capabilities/miaotou_capabilities.dart';

import 'capability_report.dart';

/// The application shell.
///
/// Deliberately a placeholder: #11 replaces it with the cross-port design system
/// and the main-window routing shell, and ADR-0012 keeps that shell to one window
/// — only the ball and the panel get a window of their own.
///
/// What this file already carries is the seam. The application is handed a
/// [CapabilitySet] and never asks what it is running on, so the whole of it can be
/// driven from a test with the in-memory implementations, and so a capability
/// that refuses is a value the shell can render rather than a crash.
class MiaotouApp extends StatelessWidget {
  const MiaotouApp({super.key, required this.capabilities});

  final CapabilitySet capabilities;

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: '喵头军师',
        debugShowCheckedModeBanner: false,
        home: CapabilityReportPage(capabilities: capabilities),
      );
}
