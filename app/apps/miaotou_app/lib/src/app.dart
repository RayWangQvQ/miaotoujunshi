import 'package:flutter/material.dart';

import 'design/copy.dart';
import 'design/theme.dart';
import 'session.dart';
import 'shell/content.dart';
import 'shell/gallery_page.dart';
import 'shell/main_window.dart';

/// The application.
///
/// Everything it needs is handed to it, and nothing in it asks what it is
/// running on: the capability set comes from `main`, the window's state is a
/// controller a platform can drive from outside, and the copy is a value a test
/// can replace wholesale. That is what lets the whole application be driven from
/// a test with no device (ADR-0009), and it is also what lets the audit in
/// `test/copy_audit_test.dart` render every page with every string swapped for a
/// marker.
///
/// What this file does decide is the order of the three things a page needs
/// before it can draw: the copy, the theme, and the shell. A page below here
/// that reaches past all three for a literal is a page that audit catches.
class MiaotouApp extends StatelessWidget {
  const MiaotouApp({
    super.key,
    required this.session,
    required this.window,
    this.copy = AppCopy.zh,
    this.content,
  });

  /// The capabilities, and the lifetime that outlives the window.
  final Session session;

  /// Visibility and destination. Created by `main`, driven by the platform.
  final MainWindowController window;

  final AppCopy copy;

  /// What the pages show. Empty until a conversation has been read.
  final ShellContent? content;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: session,
    builder: (BuildContext context, Widget? child) => CopyScope(
      copy: copy,
      child: MaterialApp(
        title: copy.text(CopyKey.appTitle),
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        home: MainWindowShell(
          session: session,
          window: window,
          samples: GallerySamples.synthetic(copy),
          content: content ?? session.content,
        ),
      ),
    ),
  );
}
