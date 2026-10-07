import 'package:flutter/material.dart';
import 'package:miaotou_capabilities/miaotou_capabilities.dart';
import 'package:miaotou_domain/miaotou_domain.dart';

import '../design/copy.dart';
import '../design/spacing.dart';
import '../panel/protocol.dart';
import '../panel/session.dart';
import '../runtime/panel_settings.dart';
import 'destination.dart';
import 'permission_section.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.onOpen,
    required this.preferences,
    required this.secrets,
    required this.panel,
    required this.permissions,
  });

  final void Function(ShellDestination destination) onOpen;
  final Preferences preferences;
  final SecretStore secrets;

  /// Where the panel's own settings are published.
  ///
  /// The panel is a second window painted by a second engine, so "preview" means
  /// pushing the value at it, not rebuilding a widget here. The session is the
  /// main engine's holder of what the panel should look like, and the panel
  /// protocol carries it from there (ADR-0020).
  final PanelSession panel;

  /// The two system permissions, read and jumped by [PermissionSection].
  ///
  /// A capability rather than a callback pair: the section is the only surface
  /// that both states the state and owns the remedy, and handing it the object
  /// that answers both is what keeps «which page does this button open» out of
  /// the UI (ADR-0021).
  final Permissions permissions;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final TextEditingController _replyBase = TextEditingController();
  final TextEditingController _replyModel = TextEditingController();
  final TextEditingController _replyKey = TextEditingController();
  final TextEditingController _strategyBase = TextEditingController();
  final TextEditingController _strategyModel = TextEditingController();
  final TextEditingController _strategyKey = TextEditingController();
  final TextEditingController _background = TextEditingController();

  StrategyProvider _provider = ModelSettings.defaults().strategyProvider;
  bool _autoAnalyze = ModelSettings.defaults().autoAnalyze;
  int _opacity = PanelAppearance.defaultOpacity;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final ModelSettings settings = await ModelSettings.load(
        widget.preferences,
        widget.secrets,
      );
      final PanelSettings panel = await PanelSettings.load(
        widget.preferences,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _replyBase.text = settings.replyBaseUrl;
        _replyModel.text = settings.replyModel;
        _replyKey.text = settings.replyKey;
        _strategyBase.text = settings.strategyBaseUrl;
        _strategyModel.text = settings.strategyModel;
        _strategyKey.text = settings.strategyKey;
        _background.text = settings.relationshipBackground;
        _provider = settings.strategyProvider;
        _autoAnalyze = settings.autoAnalyze;
        _opacity = panel.appearance.opacity;
        _loading = false;
      });
    } on Object {
      if (mounted) {
        setState(() => _loading = false);
        _show(CopyKey.settingsLoadFailed);
      }
    }
  }

  /// The page's save button: everything the panel does not own.
  ///
  /// Rebuilt from `defaults` rather than loaded and amended, which is why the
  /// goal default has to be handed in: `defaults` lives in the domain now and
  /// holds no sentence a screen shows, so the caller that is about to *store*
  /// these settings is the one that supplies it.
  Future<void> _save() async {
    final AppCopy copy = CopyScope.of(context);
    final ModelSettings settings = ModelSettings.defaults(
      goal: copy.text(CopyKey.settingsGoalDefault),
    ).copyWith(
      replyBaseUrl: _replyBase.text,
      replyModel: _replyModel.text,
      replyKey: _replyKey.text,
      strategyProvider: _provider,
      strategyBaseUrl: _strategyBase.text,
      strategyModel: _strategyModel.text,
      strategyKey: _strategyKey.text,
      autoAnalyze: _autoAnalyze,
      relationshipBackground: _background.text,
    );
    try {
      await settings.save(widget.preferences, widget.secrets);
      if (mounted) {
        _show(CopyKey.settingsSaved);
      }
    } on Object {
      if (mounted) {
        _show(CopyKey.settingsSaveFailed);
      }
    }
  }

  void _show(CopyKey key) {
    final AppCopy copy = CopyScope.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(copy.text(key))),
    );
  }

  /// Every frame of the drag goes to the panel.
  ///
  /// The panel is a second window painted by a second engine, so there is no
  /// widget here to rebuild: "preview" means pushing the value down the panel
  /// protocol, and the panel that is sitting on top of the chat repaints from it.
  void _previewOpacity(double value) {
    final int percent = value.round();
    setState(() => _opacity = percent);
    widget.panel.publishAppearance(PanelAppearance.percent(percent));
  }

  /// Letting go writes it.
  ///
  /// Deliberately its own write rather than a trip through [_save]. That path
  /// rebuilds a [ModelSettings] from `defaults`, so a slider that went through it
  /// would put `goal` back to the copy default and blank `tone`, `length` and
  /// `candidateCount` on the way past; the panel's settings are a separate type
  /// under a separate prefix for exactly that reason (ADR-0020 decision 4).
  Future<void> _commitOpacity(double value) async {
    try {
      await PanelSettings.saveAppearance(
        widget.preferences,
        PanelAppearance.percent(value.round()),
      );
    } on Object {
      if (mounted) {
        _show(CopyKey.settingsSaveFailed);
      }
    }
  }

  @override
  void dispose() {
    _replyBase.dispose();
    _replyModel.dispose();
    _replyKey.dispose();
    _strategyBase.dispose();
    _strategyModel.dispose();
    _strategyKey.dispose();
    _background.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppCopy copy = CopyScope.of(context);
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final bool strategyEnabled = _provider != StrategyProvider.none;
    return ListView(
      padding: AppSpacing.page,
      children: <Widget>[
        // First, and above the storage line, because it is not a preference
        // (ADR-0021 decision 7): with neither permission granted the
        // application cannot read a conversation or draw a card, so it is a
        // precondition for everything the rest of this page configures.
        PermissionSection(permissions: widget.permissions),
        Text(
          copy.text(CopyKey.settingsStorage),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        AppSpacing.gapL,
        Text(
          copy.text(CopyKey.settingsReplySection),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        AppSpacing.gapS,
        _field(copy, _replyBase, CopyKey.settingsReplyBaseUrl),
        _field(copy, _replyModel, CopyKey.settingsReplyModel),
        _field(
          copy,
          _replyKey,
          CopyKey.settingsReplyKey,
          secret: true,
        ),
        AppSpacing.gapL,
        Text(
          copy.text(CopyKey.settingsStrategySection),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        AppSpacing.gapS,
        DropdownButtonFormField<StrategyProvider>(
          key: const Key('settings-strategy-provider'),
          initialValue: _provider,
          decoration: InputDecoration(
            labelText: copy.text(CopyKey.settingsStrategyProvider),
          ),
          items: <DropdownMenuItem<StrategyProvider>>[
            for (final StrategyProvider provider in StrategyProvider.values)
              DropdownMenuItem<StrategyProvider>(
                value: provider,
                child: Text(copy.text(_providerLabel(provider))),
              ),
          ],
          onChanged: (StrategyProvider? value) {
            if (value != null) {
              setState(() => _provider = value);
            }
          },
        ),
        if (strategyEnabled) ...<Widget>[
          _field(copy, _strategyBase, CopyKey.settingsStrategyBaseUrl),
          _field(copy, _strategyModel, CopyKey.settingsStrategyModel),
          _field(
            copy,
            _strategyKey,
            CopyKey.settingsStrategyKey,
            secret: true,
          ),
        ],
        AppSpacing.gapL,
        _field(
          copy,
          _background,
          CopyKey.settingsRelationshipBackground,
          lines: 3,
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(copy.text(CopyKey.settingsAutoAnalyze)),
          value: _autoAnalyze,
          onChanged: (bool value) => setState(() => _autoAnalyze = value),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton(
            key: const Key('settings-save'),
            onPressed: _save,
            child: Text(copy.text(CopyKey.settingsSave)),
          ),
        ),
        AppSpacing.gapL,
        Text(
          copy.text(CopyKey.settingsPanelSection),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                copy.text(CopyKey.settingsPanelOpacity),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
            Text(
              copy
                  .text(CopyKey.settingsPanelOpacityValue)
                  .replaceAll('{value}', '$_opacity'),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
        Slider(
          key: const Key('settings-panel-opacity'),
          value: _opacity.toDouble(),
          min: PanelAppearance.minOpacity.toDouble(),
          max: PanelAppearance.maxOpacity.toDouble(),
          divisions: PanelAppearance.maxOpacity - PanelAppearance.minOpacity,
          label: copy
              .text(CopyKey.settingsPanelOpacityValue)
              .replaceAll('{value}', '$_opacity'),
          onChanged: _previewOpacity,
          onChangeEnd: _commitOpacity,
        ),
        Text(
          copy.text(CopyKey.settingsPanelOpacityHint),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        AppSpacing.gapL,
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(ShellDestination.gallery.icon),
          title: Text(copy.text(CopyKey.settingsGallery)),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => widget.onOpen(ShellDestination.gallery),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(ShellDestination.diagnostics.icon),
          title: Text(copy.text(CopyKey.settingsDiagnostics)),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => widget.onOpen(ShellDestination.diagnostics),
        ),
      ],
    );
  }

  Widget _field(
    AppCopy copy,
    TextEditingController controller,
    CopyKey label, {
    bool secret = false,
    int lines = 1,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.s),
    child: TextField(
      controller: controller,
      obscureText: secret,
      maxLines: lines,
      decoration: InputDecoration(labelText: copy.text(label)),
    ),
  );

  static CopyKey _providerLabel(StrategyProvider provider) => switch (provider) {
    StrategyProvider.none => CopyKey.settingsStrategyNone,
    StrategyProvider.jev => CopyKey.settingsStrategyJev,
    StrategyProvider.deepseek => CopyKey.settingsStrategyDeepSeek,
  };
}
