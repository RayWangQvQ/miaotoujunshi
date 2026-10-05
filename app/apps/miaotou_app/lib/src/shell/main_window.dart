import 'package:flutter/material.dart';

import '../capability_report.dart';
import '../design/copy.dart';
import '../design/spacing.dart';
import '../session.dart';
import 'content.dart';
import 'destination.dart';
import 'detail_page.dart';
import 'gallery_page.dart';
import 'knowledge_page.dart';
import 'settings_page.dart';
import 'trend_page.dart';

/// The main window: one scaffold, four routes, and a navigation that follows the
/// width it was given.
///
/// ADR-0012 makes this the only window that holds the capabilities, and it has
/// two consequences that are easy to get wrong and are both checked:
///
/// * **Every surface is a route in here.** Settings, detail, the trend view and
///   the knowledge base are destinations; the gallery and the capability report
///   are pushed onto the same navigator from settings. Nothing opens a window.
/// * **The window can go away without the session noticing.** [MainWindowShell]
///   reads [MainWindowController.visible] and renders nothing when it is false —
///   a hidden window, which is what "closed" means on every desktop port once
///   the ball is still on screen. The [Session] it was handed is not a widget,
///   not a `State`, and not reachable from here except to read capabilities.
///
/// The navigation asks [MediaQuery] how wide it is and nothing else. There is no
/// `Platform.isMacOS` anywhere in this file or in any page, because three ports
/// do not need three layouts when one layout can follow the window.
class MainWindowShell extends StatefulWidget {
  const MainWindowShell({
    super.key,
    required this.session,
    required this.window,
    required this.samples,
    this.content = ShellContent.empty,
  });

  /// The half that outlives this widget.
  final Session session;

  /// Visibility and the current destination, driven from outside the tree.
  final MainWindowController window;

  /// What the gallery renders. It is a parameter rather than a constant so that
  /// the gallery's samples come from the copy file like every other string.
  final GallerySamples samples;

  final ShellContent content;

  @override
  State<MainWindowShell> createState() => _MainWindowShellState();
}

class _MainWindowShellState extends State<MainWindowShell> {
  @override
  void initState() {
    super.initState();
    widget.window.addListener(_listen);
  }

  @override
  void didUpdateWidget(MainWindowShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.window != widget.window) {
      oldWidget.window.removeListener(_listen);
      widget.window.addListener(_listen);
    }
  }

  @override
  void dispose() {
    widget.window.removeListener(_listen);
    super.dispose();
  }

  void _listen() {
    if (mounted) {
      setState(() {});
    }
  }

  /// Pushes a surface that is not one of the four navigable ones.
  ///
  /// It deliberately does *not* move [MainWindowController.destination]: the
  /// page underneath is settings, and a pushed route that also changed the
  /// destination would put the same page in the navigator twice.
  void _open(ShellDestination destination) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => _page(destination),
      ),
    );
  }

  Widget _page(ShellDestination destination) {
    switch (destination) {
      case ShellDestination.detail:
        return DetailPage(content: widget.content);
      case ShellDestination.trend:
        return TrendPage(content: widget.content);
      case ShellDestination.knowledge:
        return KnowledgePage(content: widget.content);
      case ShellDestination.settings:
        return SettingsPage(
          onOpen: _open,
          preferences: widget.session.capabilities.preferences,
          secrets: widget.session.capabilities.secretStore,
        );
      case ShellDestination.gallery:
        return GalleryPage(samples: widget.samples);
      case ShellDestination.diagnostics:
        return CapabilityReportPage(capabilities: widget.session.capabilities);
    }
  }

  @override
  Widget build(BuildContext context) {
    final MainWindowController window = widget.window;
    if (!window.visible) {
      // A hidden window, not a closed application: no scaffold, no page, and
      // above all no teardown. The session is still running behind this.
      return const SizedBox.shrink();
    }

    final AppCopy copy = CopyScope.of(context);
    final ShellDestination destination = window.destination;
    final double width = MediaQuery.sizeOf(context).width;
    final bool rail = width >= AppBreakpoint.rail;
    final bool extended = width >= AppBreakpoint.extendedRail;
    // A pushed surface (gallery, diagnostics) is not in the navigable list, and
    // `indexOf` says so with -1; the rail keeps the selection it had rather than
    // highlighting nothing.
    final int selected = ShellDestination.navigable
        .indexOf(destination)
        .clamp(0, ShellDestination.navigable.length - 1);

    return Scaffold(
      appBar: AppBar(title: Text(copy.text(destination.labelKey))),
      body: Row(
        children: <Widget>[
          if (rail)
            NavigationRail(
              extended: extended,
              selectedIndex: selected,
              onDestinationSelected: (int index) =>
                  window.navigate(ShellDestination.navigable[index]),
              destinations: <NavigationRailDestination>[
                for (final ShellDestination item
                    in ShellDestination.navigable)
                  NavigationRailDestination(
                    icon: Icon(item.icon),
                    label: Text(copy.text(item.labelKey)),
                  ),
              ],
            ),
          const VerticalDivider(width: 1),
          Expanded(child: _page(destination)),
        ],
      ),
      bottomNavigationBar: rail
          ? null
          : NavigationBar(
              selectedIndex: selected,
              onDestinationSelected: (int index) =>
                  window.navigate(ShellDestination.navigable[index]),
              destinations: <Widget>[
                for (final ShellDestination item
                    in ShellDestination.navigable)
                  NavigationDestination(
                    icon: Icon(item.icon),
                    label: copy.text(item.labelKey),
                  ),
              ],
            ),
    );
  }
}
