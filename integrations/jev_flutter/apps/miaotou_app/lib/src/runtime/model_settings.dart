import 'package:miaotou_capabilities/miaotou_capabilities.dart';

import '../design/copy.dart';

enum StrategyProvider { none, jev, deepseek }

final class ModelSettings {
  const ModelSettings({
    required this.replyBaseUrl,
    required this.replyModel,
    required this.replyKey,
    required this.strategyProvider,
    required this.strategyBaseUrl,
    required this.strategyModel,
    required this.strategyKey,
    required this.autoAnalyze,
    required this.relationshipBackground,
    required this.goal,
    required this.tone,
    required this.length,
    required this.candidateCount,
  });

  static const String replySecretKey = 'model.reply.key';
  static const String strategySecretKey = 'model.strategy.key';

  static final ModelSettings defaults = ModelSettings(
    replyBaseUrl: 'https://openrouter.ai/api/v1',
    replyModel: 'deepseek/deepseek-chat-v3.1',
    replyKey: '',
    strategyProvider: StrategyProvider.none,
    strategyBaseUrl: 'https://api.typesafe.ai',
    strategyModel: 'jev-latest',
    strategyKey: '',
    autoAnalyze: false,
    relationshipBackground: '',
    goal: AppCopy.zh.text(CopyKey.settingsGoalDefault),
    tone: null,
    length: null,
    candidateCount: null,
  );

  final String replyBaseUrl;
  final String replyModel;
  final String replyKey;
  final StrategyProvider strategyProvider;
  final String strategyBaseUrl;
  final String strategyModel;
  final String strategyKey;
  final bool autoAnalyze;
  final String relationshipBackground;
  final String goal;
  final String? tone;
  final String? length;
  final int? candidateCount;

  bool get isReady =>
      replyBaseUrl.trim().isNotEmpty &&
      replyModel.trim().isNotEmpty &&
      replyKey.trim().isNotEmpty &&
      (strategyProvider == StrategyProvider.none ||
          (strategyBaseUrl.trim().isNotEmpty &&
              strategyModel.trim().isNotEmpty &&
              strategyKey.trim().isNotEmpty));

  Uri get replyEndpoint => _endpoint(replyBaseUrl, 'chat/completions');
  Uri get strategyChatEndpoint =>
      _endpoint(strategyBaseUrl, 'chat/completions');
  Uri get systemoneEndpoint => _endpoint(strategyBaseUrl, 'v1/systemone');

  static Future<ModelSettings> load(
    Preferences preferences,
    SecretStore secrets,
  ) async {
    final String? provider = await preferences.getString(_strategyProvider);
    return ModelSettings(
      replyBaseUrl:
          await preferences.getString(_replyBaseUrl) ?? defaults.replyBaseUrl,
      replyModel:
          await preferences.getString(_replyModel) ?? defaults.replyModel,
      replyKey: await secrets.read(replySecretKey) ?? '',
      strategyProvider: StrategyProvider.values.firstWhere(
        (StrategyProvider value) => value.name == provider,
        orElse: () => defaults.strategyProvider,
      ),
      strategyBaseUrl:
          await preferences.getString(_strategyBaseUrl) ??
          defaults.strategyBaseUrl,
      strategyModel:
          await preferences.getString(_strategyModel) ?? defaults.strategyModel,
      strategyKey: await secrets.read(strategySecretKey) ?? '',
      autoAnalyze:
          await preferences.getBool(_autoAnalyze) ?? defaults.autoAnalyze,
      relationshipBackground:
          await preferences.getString(_relationshipBackground) ??
          defaults.relationshipBackground,
      goal: await preferences.getString(_goal) ?? defaults.goal,
      tone: await preferences.getString(_tone),
      length: await preferences.getString(_length),
      candidateCount: await preferences.getInt(_candidateCount),
    );
  }

  Future<void> save(Preferences preferences, SecretStore secrets) async {
    await preferences.setString(_replyBaseUrl, replyBaseUrl.trim());
    await preferences.setString(_replyModel, replyModel.trim());
    await preferences.setString(_strategyProvider, strategyProvider.name);
    await preferences.setString(_strategyBaseUrl, strategyBaseUrl.trim());
    await preferences.setString(_strategyModel, strategyModel.trim());
    await preferences.setBool(_autoAnalyze, autoAnalyze);
    await preferences.setString(
      _relationshipBackground,
      relationshipBackground.trim(),
    );
    await preferences.setString(_goal, goal);
    await _writeOptional(preferences, _tone, tone);
    await _writeOptional(preferences, _length, length);
    if (candidateCount == null) {
      await preferences.remove(_candidateCount);
    } else {
      await preferences.setInt(_candidateCount, candidateCount!);
    }
    await _writeSecret(secrets, replySecretKey, replyKey);
    await _writeSecret(secrets, strategySecretKey, strategyKey);
  }

  ModelSettings copyWith({
    String? replyBaseUrl,
    String? replyModel,
    String? replyKey,
    StrategyProvider? strategyProvider,
    String? strategyBaseUrl,
    String? strategyModel,
    String? strategyKey,
    bool? autoAnalyze,
    String? relationshipBackground,
    String? goal,
    String? tone,
    String? length,
    int? candidateCount,
  }) => ModelSettings(
    replyBaseUrl: replyBaseUrl ?? this.replyBaseUrl,
    replyModel: replyModel ?? this.replyModel,
    replyKey: replyKey ?? this.replyKey,
    strategyProvider: strategyProvider ?? this.strategyProvider,
    strategyBaseUrl: strategyBaseUrl ?? this.strategyBaseUrl,
    strategyModel: strategyModel ?? this.strategyModel,
    strategyKey: strategyKey ?? this.strategyKey,
    autoAnalyze: autoAnalyze ?? this.autoAnalyze,
    relationshipBackground:
        relationshipBackground ?? this.relationshipBackground,
    goal: goal ?? this.goal,
    tone: tone ?? this.tone,
    length: length ?? this.length,
    candidateCount: candidateCount ?? this.candidateCount,
  );

  @override
  bool operator ==(Object other) =>
      other is ModelSettings &&
      other.replyBaseUrl == replyBaseUrl &&
      other.replyModel == replyModel &&
      other.replyKey == replyKey &&
      other.strategyProvider == strategyProvider &&
      other.strategyBaseUrl == strategyBaseUrl &&
      other.strategyModel == strategyModel &&
      other.strategyKey == strategyKey &&
      other.autoAnalyze == autoAnalyze &&
      other.relationshipBackground == relationshipBackground &&
      other.goal == goal &&
      other.tone == tone &&
      other.length == length &&
      other.candidateCount == candidateCount;

  @override
  int get hashCode => Object.hash(
    replyBaseUrl,
    replyModel,
    replyKey,
    strategyProvider,
    strategyBaseUrl,
    strategyModel,
    strategyKey,
    autoAnalyze,
    relationshipBackground,
    goal,
    tone,
    length,
    candidateCount,
  );

  static const String _replyBaseUrl = 'model.reply.base_url';
  static const String _replyModel = 'model.reply.model';
  static const String _strategyProvider = 'model.strategy.provider';
  static const String _strategyBaseUrl = 'model.strategy.base_url';
  static const String _strategyModel = 'model.strategy.model';
  static const String _autoAnalyze = 'runtime.auto_analyze';
  static const String _relationshipBackground = 'analysis.relationship';
  static const String _goal = 'analysis.goal';
  static const String _tone = 'analysis.tone';
  static const String _length = 'analysis.length';
  static const String _candidateCount = 'analysis.candidate_count';
}

Uri _endpoint(String rawBase, String suffix) {
  final Uri base = Uri.parse(rawBase.trim());
  final List<String> baseSegments = base.pathSegments
      .where((String segment) => segment.isNotEmpty)
      .toList();
  final List<String> suffixSegments = suffix.split('/');
  if (suffixSegments.length >= 2 &&
      baseSegments.isNotEmpty &&
      baseSegments.last == suffixSegments.first) {
    suffixSegments.removeAt(0);
  }
  return base.replace(
    pathSegments: <String>[...baseSegments, ...suffixSegments],
    query: null,
    fragment: null,
  );
}

Future<void> _writeOptional(
  Preferences preferences,
  String key,
  String? value,
) =>
    value == null ? preferences.remove(key) : preferences.setString(key, value);

Future<void> _writeSecret(SecretStore secrets, String key, String value) =>
    value.trim().isEmpty
    ? secrets.delete(key)
    : secrets.write(key, value.trim());
