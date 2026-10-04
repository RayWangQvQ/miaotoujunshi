import 'package:flutter/material.dart';

import '../design/copy.dart';

/// The pages the main window holds.
///
/// ADR-0012's decision list: settings, detail, the trend view and the knowledge
/// base are routes, and only the ball and the panel are windows. These are those
/// four, plus two surfaces that are not product pages — the component gallery
/// and the capability report — which is why [navigable] is a subset rather than
/// the whole enum: the four appear in the navigation, the other two are reached
/// from settings and are not destinations a user visits.
///
/// The icon and the label live with the enum because a destination added
/// without them cannot appear in the navigation, and the compiler says so
/// rather than a reviewer.
enum ShellDestination {
  detail(CopyKey.navDetail, Icons.forum_outlined),
  trend(CopyKey.navTrend, Icons.candlestick_chart_outlined),
  knowledge(CopyKey.navKnowledge, Icons.people_alt_outlined),
  settings(CopyKey.navSettings, Icons.tune_outlined),
  gallery(CopyKey.galleryTitle, Icons.widgets_outlined),
  diagnostics(CopyKey.diagnosticsTitle, Icons.monitor_heart_outlined);

  const ShellDestination(this.labelKey, this.icon);

  /// The copy key for the label, so no page writes its own name.
  final CopyKey labelKey;

  final IconData icon;

  /// The four that are routes a user picks from the navigation.
  static const List<ShellDestination> navigable = <ShellDestination>[
    detail,
    trend,
    knowledge,
    settings,
  ];
}
