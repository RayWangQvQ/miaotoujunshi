import 'dart:convert';
import 'dart:math' as math;

import 'errors.dart';
import 'model_gateway.dart';

/// Which independent strategy step produced a decision.
///
/// The three ports expose these as the same two switches, and the distinction
/// matters downstream: a Jev decision carries the seven judge answers as
/// evidence, a DeepSeek one carries an evidence pass it ran itself, and only the
/// DeepSeek route can ever publish token weights.
enum StrategyEngine {
  /// TypeSafe's judging endpoint.
  jev,

  /// The DeepSeek route: an evidence pass, then rotated choice requests.
  deepseek,
}

/// How a decision was arrived at. It travels into the decision the UI shows, so
/// a reader can tell a published distribution from a single self-report.
enum StrategyMethod {
  /// The TypeSafe endpoint answered the judge questions.
  jev('jev'),

  /// DeepSeek answered in JSON, without usable token data.
  deepseekSelfReport('deepseek_self_report'),

  /// DeepSeek's three rotated choice requests agreed, and a distribution was
  /// averaged from their first tokens.
  deepseekLogprobs('deepseek_logprobs');

  const StrategyMethod(this.wireName);

  /// The spelling that appears in JSON and in the UI. Kept separate from the
  /// Dart name so a rename here cannot change what a user sees.
  final String wireName;
}

/// Which engine and which model the independent strategy step should use.
///
/// One value, not two arguments: the ports let the strategy decision point at a
/// provider of its own with its own credential, and a caller that passed an
/// engine without a model — or two of either — could only mean a mistake. Passing
/// `null` instead of this is how "no independent step, use the single-model path"
/// is said, and it cannot be said at the same time as "use one".
final class StrategyRoute {
  const StrategyRoute({required this.engine, required this.model});

  final StrategyEngine engine;

  /// The model string. For the Jev route it is what the request carries and what
  /// the answer's own model field is checked against; for DeepSeek it is the
  /// model the decision is recorded as coming from.
  final String model;

  @override
  String toString() => 'StrategyRoute(${engine.name}, $model)';
}

/// The outcome of one independent strategy step.
///
/// [confidence] and [probabilities] are the two things the ports refuse to
/// fabricate. Confidence is null whenever the method could not produce a
/// trustworthy number, and [probabilities] is empty unless three rotated label
/// maps agreed — an unstable distribution is reported as *absent*, never as a
/// flat or made-up one.
final class StrategyDecision {
  const StrategyDecision({
    required this.strategy,
    required this.confidence,
    required this.probabilities,
    required this.model,
    required this.method,
    this.evidence = const <String, Object?>{},
  });

  final String strategy;

  /// Null when the step could not produce one. Null is not "0.0" and must not be
  /// rendered as one.
  final double? confidence;

  /// Strategy name → weight, summing to 1. Empty unless
  /// [StrategyMethod.deepseekLogprobs].
  final Map<String, double> probabilities;

  final String model;
  final StrategyMethod method;
  final Map<String, Object?> evidence;

  /// The judge's seven structured answers, when this came from Jev. Null
  /// otherwise — and the distinction is load-bearing, because the prompt must
  /// not describe evidence the decision does not carry.
  Map<String, Object?>? get judgeEvidence {
    final Object? judge = evidence['judge'];
    return judge is Map ? judge.cast<String, Object?>() : null;
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'strategy': strategy,
        'confidence': confidence,
        'probabilities': probabilities,
        'model': model,
        'method': method.wireName,
        'evidence': evidence,
      };

  @override
  String toString() => 'StrategyDecision($strategy, $model, ${method.wireName}, '
      'confidence=$confidence)';
}

/// Turns the judge's answers into the evidence the reply prompt is given.
///
/// **Unusable answers are dropped, never repaired.** A missing answer, a value of
/// the wrong shape, a non-finite number — each leaves the key out. That is
/// deliberate: these answers inform the draft, they do not decide it, so a
/// partial set must never cost the user the whole result by turning a missing
/// field into a refusal. The names come from the payload's own list, in its own
/// order, so a question added later cannot silently change what the draft is
/// told.
Map<String, Object?> judgeEvidence(
  Map<String, Object?> answers, {
  required Iterable<String> questionNames,
}) {
  final Map<String, Object?> evidence = <String, Object?>{};
  for (final String name in questionNames) {
    final Object? raw = answers[name];
    if (raw is! Map) {
      continue;
    }
    final Map<String, Object?> answer = raw.cast<String, Object?>();
    final Object? kind = answer['type'];
    if (kind is! String) {
      continue;
    }
    final Object? value = answer[kind];
    switch (kind) {
      case 'noul':
        if (value is num && value.isFinite) {
          evidence[name] = value >= .5;
        }
      case 'score':
        if (value is num && value.isFinite) {
          evidence[name] = value.toInt();
        }
      case 'choice':
        if (value is String && value.isNotEmpty) {
          evidence[name] = value;
        }
    }
  }
  return evidence;
}

/// Reads a TypeSafe answer set into a decision.
///
/// This is the strictest parser in the package, and every strictness is a real
/// failure the ports have seen: a distribution that does not cover all seven
/// strategies, weights that do not sum to 1, a model string that is not a Jev
/// model. Any of them means the answer cannot be trusted to have been about
/// strategy at all, and a plausible-looking wrong strategy is worse than no
/// strategy.
///
/// Failure is one [DomainException]. It never falls back to a default strategy
/// and never re-asks; the caller decides whether to repair or to give up.
StrategyDecision parseJevDecision(
  Object? data, {
  required List<String> strategies,
  required Iterable<String> questionNames,
}) {
  if (data is! Map) {
    throw const DomainException('Jev 响应不是预期的策略判断格式');
  }
  final Map<String, Object?> root = data.cast<String, Object?>();
  final Object? rawAnswers = root['answers'];
  final Object? rawAnswer =
      rawAnswers is Map ? rawAnswers.cast<String, Object?>()['reply_strategy'] : null;
  if (rawAnswer is! Map) {
    throw const DomainException('Jev 响应不是预期的策略判断格式');
  }
  final Map<String, Object?> answer = rawAnswer.cast<String, Object?>();

  final Object? kind = answer['type'];
  if (kind is! String) {
    throw const DomainException('Jev 响应不是预期的策略判断格式');
  }
  final Object? strategy = answer['choice'];
  if (kind != 'choice' ||
      strategy is! String ||
      !strategies.contains(strategy)) {
    throw const DomainException('Jev 返回了未知策略');
  }

  final Object? rawDistribution = answer['probabilities'];
  if (rawDistribution is! Map) {
    throw const DomainException('Jev 返回的策略分布不完整');
  }
  final Map<String, Object?> distribution = rawDistribution.cast<String, Object?>();
  if (distribution.length != strategies.length ||
      !strategies.every(distribution.containsKey)) {
    throw const DomainException('Jev 返回的策略分布不完整');
  }

  final Map<String, double> probabilities = <String, double>{
    for (final MapEntry<String, Object?> entry in distribution.entries)
      entry.key: _probability(entry.value),
  };
  double total = 0;
  for (final double value in probabilities.values) {
    total += value;
  }
  if ((total - 1).abs() > .02) {
    throw const DomainException('Jev 返回的策略概率总和不正确');
  }

  final Object? model = root['model'];
  if (model is! String || !model.startsWith('jev-') || model.length > 80) {
    throw const DomainException('Jev 返回的模型标识不正确');
  }
  if (!answer.containsKey('confidence')) {
    throw const DomainException('Jev 响应不是预期的策略判断格式');
  }

  return StrategyDecision(
    strategy: strategy,
    confidence: _probability(answer['confidence']),
    probabilities: probabilities,
    model: model,
    method: StrategyMethod.jev,
    evidence: <String, Object?>{
      'judge': judgeEvidence(
        rawAnswers is Map
            ? rawAnswers.cast<String, Object?>()
            : const <String, Object?>{},
        questionNames: questionNames,
      ),
    },
  );
}

/// Reads a DeepSeek evidence answer into a decision.
///
/// Unlike the Jev parser this one is forgiving about *everything except* the
/// strategy: a confidence that is a string or out of range becomes null, a facts
/// list of the wrong shape becomes an empty list, an unrecognised boundary
/// becomes `uncertain`. The strategy itself is not negotiable — naming none of
/// the seven is refused, because there is nothing to fall back to.
///
/// It never publishes probabilities. The evidence pass has no token data; only
/// [parseChoice] can produce a distribution, and only three agreeing rotations of
/// it are ever published.
StrategyDecision parseDeepSeekDecision(
  String raw, {
  required String model,
  required List<String> strategies,
}) {
  final Object? decoded = _tryDecode(raw);
  if (decoded is! Map) {
    throw const DomainException('DeepSeek 策略判断格式不正确；未生成候选，请重试');
  }
  final Map<String, Object?> data = decoded.cast<String, Object?>();

  final Object? rawStrategy = data['strategy'];
  final Object? strategy = rawStrategy is String ? rawStrategy.trim() : rawStrategy;
  if (strategy is! String || !strategies.contains(strategy)) {
    throw const DomainException('DeepSeek 策略判断格式不正确；未生成候选，请重试');
  }

  return StrategyDecision(
    strategy: strategy,
    confidence: looseConfidence(data['confidence']),
    probabilities: const <String, double>{},
    model: model,
    method: StrategyMethod.deepseekSelfReport,
    evidence: <String, Object?>{
      for (final String key in const <String>['facts', 'unknowns'])
        key: evidenceRows(data[key]),
      'boundary': boundaryToken(data['boundary']),
    },
  );
}

/// Reads one rotated choice answer into a strategy distribution.
///
/// Three guards, each a mistake that was made for real:
///
/// * the emitted token must be the **first** output token and must equal the
///   content — otherwise a later token in the same reply could be read as the
///   choice;
/// * every one of the seven labels must appear among the alternatives, and none
///   may appear twice — a partial set normalised to 1 would invent a
///   distribution;
/// * no logprob may be non-finite or ≤ −1000, the provider's floor for "never
///   considered".
///
/// The probabilities come from a softmax over the logprobs, which is why the peak
/// is subtracted first: exponentiating raw logprobs underflows to zero.
Map<String, double> parseChoice({
  required String content,
  required List<TopLogprob> top,
  required String? firstToken,
  required Map<String, String> labels,
}) {
  final String trimmed = content.trim();
  if (!labels.containsKey(trimmed) || firstToken != trimmed) {
    throw const DomainException('DeepSeek 策略 token 权重不可用');
  }
  final Map<String, double> scores = <String, double>{};
  for (final TopLogprob row in top) {
    if (!labels.containsKey(row.token)) {
      continue;
    }
    if (scores.containsKey(row.token) ||
        !row.logprob.isFinite ||
        row.logprob <= -1000) {
      throw const DomainException('DeepSeek 策略 token 权重不可用');
    }
    scores[row.token] = row.logprob;
  }
  if (scores.length != labels.length || !labels.keys.every(scores.containsKey)) {
    throw const DomainException('DeepSeek 策略 token 权重不可用');
  }
  final double peak = scores.values.reduce(math.max);
  final Map<String, double> shifted = <String, double>{
    for (final MapEntry<String, double> entry in scores.entries)
      entry.key: math.exp(entry.value - peak),
  };
  double total = 0;
  for (final double value in shifted.values) {
    total += value;
  }
  if (!total.isFinite || total <= 0) {
    throw const DomainException('DeepSeek 策略 token 权重不可用');
  }
  return <String, double>{
    for (final MapEntry<String, double> entry in shifted.entries)
      labels[entry.key]!: entry.value / total,
  };
}

/// A facts/unknowns list from a loose model answer: dict rows with a `text` key
/// are unwrapped, blanks are dropped, each row is capped at 200 characters and
/// the list at five rows.
List<String> evidenceRows(Object? raw) {
  Object? rows = raw;
  if (rows is String) {
    rows = <String>[rows];
  }
  if (rows is! List) {
    return const <String>[];
  }
  final List<String> cleaned = <String>[];
  for (Object? row in rows) {
    if (row is Map) {
      row = row['text'];
    }
    if (row is String) {
      final String trimmed = row.trim();
      if (trimmed.isNotEmpty) {
        cleaned.add(
          trimmed.length <= 200 ? trimmed : trimmed.substring(0, 200),
        );
      }
    }
  }
  return cleaned.length <= 5 ? cleaned : cleaned.sublist(0, 5);
}

/// The boundary flag, in its wire spelling. Anything unrecognised is
/// `uncertain`, never `none`: an unreadable refusal must not read as consent.
String boundaryToken(Object? raw) {
  final String value = raw is String ? raw : 'uncertain';
  final String mapped = const <String, String>{
        '明确拒绝': 'explicit_refusal',
        '没有明确拒绝': 'none',
        '不确定': 'uncertain',
      }[value] ??
      value;
  return const <String>{'none', 'explicit_refusal', 'uncertain'}.contains(mapped)
      ? mapped
      : 'uncertain';
}

/// A confidence that may be a number, a numeric string, or nonsense. Nonsense is
/// null rather than an error: the evidence pass's job is the strategy, and losing
/// it over a malformed self-assessment would be a worse trade.
double? looseConfidence(Object? value) {
  if (value is String) {
    final double? parsed = double.tryParse(value.trim());
    return (parsed != null && parsed.isFinite && parsed >= 0 && parsed <= 1)
        ? parsed
        : null;
  }
  if (value is num && value.isFinite && value >= 0 && value <= 1) {
    return value.toDouble();
  }
  return null;
}

double _probability(Object? value) {
  if (value is! num || !value.isFinite || value < 0 || value > 1) {
    throw const DomainException('Jev 返回的概率格式不正确');
  }
  return value.toDouble();
}

Object? _tryDecode(String raw) {
  try {
    return jsonDecode(raw);
  } on FormatException {
    return null;
  }
}
