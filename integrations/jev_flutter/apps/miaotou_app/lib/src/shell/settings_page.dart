import 'package:flutter/material.dart';

import '../design/copy.dart';
import '../design/spacing.dart';
import '../widgets/labeled_block.dart';
import 'destination.dart';

/// Preferences, and the two surfaces that are not product pages.
///
/// The preferences themselves are not here yet: they are read and written
/// through the `Preferences` and `SecretStore` capabilities, and until a port
/// implements them (#15/#19/#23) the honest screen is one that says so rather
/// than one with switches that save nothing. What this page does own is the way
/// into the gallery and the capability report, both of which are routes in this
/// window like everything else.
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.onOpen});

  /// Opens another surface. The shell decides how; this page only asks.
  final void Function(ShellDestination destination) onOpen;

  @override
  Widget build(BuildContext context) {
    final AppCopy copy = CopyScope.of(context);

    return ListView(
      padding: AppSpacing.page,
      children: <Widget>[
        LabeledBlock(
          label: copy.text(CopyKey.settingsTitle),
          value: copy.text(CopyKey.settingsStorage),
        ),
        AppSpacing.gapL,
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(ShellDestination.gallery.icon),
          title: Text(copy.text(CopyKey.settingsGallery)),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => onOpen(ShellDestination.gallery),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(ShellDestination.diagnostics.icon),
          title: Text(copy.text(CopyKey.settingsDiagnostics)),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => onOpen(ShellDestination.diagnostics),
        ),
      ],
    );
  }
}
