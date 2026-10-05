import 'package:flutter/material.dart';
import 'package:miaotou_capabilities/miaotou_capabilities.dart';

import '../design/copy.dart';
import '../design/spacing.dart';
import '../runtime/model_settings.dart';
import 'destination.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.onOpen,
    required this.preferences,
    required this.secrets,
  });

  final void Function(ShellDestination destination) onOpen;
  final Preferences preferences;
  final SecretStore secrets;

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

  StrategyProvider _provider = ModelSettings.defaults.strategyProvider;
  bool _autoAnalyze = ModelSettings.defaults.autoAnalyze;
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
        _loading = false;
      });
    } on Object {
      if (mounted) {
        setState(() => _loading = false);
        _show(CopyKey.settingsLoadFailed);
      }
    }
  }

  Future<void> _save() async {
    final ModelSettings settings = ModelSettings.defaults.copyWith(
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
