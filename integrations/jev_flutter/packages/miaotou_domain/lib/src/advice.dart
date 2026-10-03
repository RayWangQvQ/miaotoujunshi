import 'dart:convert';

import 'errors.dart';
import 'strategy.dart';

/// How far the ranking step got with a set of candidates.
///
/// Four states rather than a boolean, because they mean different things to the
/// user: nothing to rank, one candidate that is trivially first, a real ranking,
/// and a ranking that failed and left the drafts in generation order. The last is
/// the one that matters — it is shown as "排序暂不可用" and never as a set of
/// invented weights.
enum RankingStatus {
  notNeeded('not_needed'),
  single('single'),
  ranked('ranked'),
  unavailable('unavailable');

  const RankingStatus(this.wireName);

  final String wireName;
}

/// One draft reply and the two lines that explain it.
///
/// [weight] is the relative preference share, and it is null until the ranking
/// step fills it. Null is not zero: a candidate with no weight has not been
/// compared, and showing it as 0% would claim it lost.
final class Candidate {
  const Candidate({
    required this.text,
    required this.reason,
    required this.tradeoff,
    this.weight,
  });

  final String text;
  final String reason;
  final String tradeoff;
  final int? weight;

  Candidate withWeight(int value) => Candidate(
        text: text,
        reason: reason,
        tradeoff: tradeoff,
        weight: value,
      );

  Map<String, Object?> toJson() => <String, Object?>{
        'text': text,
        'reason': reason,
        'tradeoff': tradeoff,
        if (weight != null) 'weight': weight,
      };

  @override
  String toString() => 'Candidate($text, weight=$weight)';
}

/// One round's analysis: the verdict on the conversation and the drafts.
///
/// This is the object AC1 means by "a verdict and candidate replies" — everything
/// the panel shows, produced without a device. It is immutable and copied rather
/// than mutated, so the ranking step cannot half-write a result the panel is
/// already rendering.
final class Advice {
  const Advice({
    required this.support,
    required this.facts,
    required this.hypotheses,
    required this.unknowns,
    required this.intent,
    required this.intentConfidence,
    required this.strategy,
    required this.recommendation,
    required this.nextStep,
    required this.stopCondition,
    required this.question,
    required this.candidates,
    this.rankingStatus,
    this.strategyDecision,
  });

  /// A short line that receives the other person's feeling before anything else.
  final String support;

  final List<String> facts;
  final List<String> hypotheses;
  final List<String> unknowns;

  /// The one main intent, in hedged wording, or null when the model said it could
  /// not tell. Null and the empty string are different: the empty string is a
  /// format error, null is an admission.
  final String? intent;

  /// The model's self-assessed grip on [intent]. Null when it declined to give
  /// one, which is required whenever it said it could not tell.
  final double? intentConfidence;

  final String strategy;
  final String recommendation;
  final String nextStep;
  final String stopCondition;
  final String question;
  final List<Candidate> candidates;

  final RankingStatus? rankingStatus;

  /// The independent strategy step that pinned [strategy], when one ran.
  final StrategyDecision? strategyDecision;

  Advice copyWith({
    List<Candidate>? candidates,
    RankingStatus? rankingStatus,
    StrategyDecision? strategyDecision,
  }) =>
      Advice(
        support: support,
        facts: facts,
        hypotheses: hypotheses,
        unknowns: unknowns,
        intent: intent,
        intentConfidence: intentConfidence,
        strategy: strategy,
        recommendation: recommendation,
        nextStep: nextStep,
        stopCondition: stopCondition,
        question: question,
        candidates: candidates ?? this.candidates,
        rankingStatus: rankingStatus ?? this.rankingStatus,
        strategyDecision: strategyDecision ?? this.strategyDecision,
      );

  Map<String, Object?> toJson() => <String, Object?>{
        'support': support,
        'facts': facts,
        'hypotheses': hypotheses,
        'unknowns': unknowns,
        if (intent != null) 'intent': intent,
        'intent_confidence': intentConfidence,
        'strategy': strategy,
        'recommendation': recommendation,
        'next_step': nextStep,
        'stop_condition': stopCondition,
        'question': question,
        'candidates': <Object?>[for (final Candidate c in candidates) c.toJson()],
        if (rankingStatus != null) 'ranking_status': rankingStatus!.wireName,
        if (strategyDecision != null)
          'strategy_decision': strategyDecision!.toJson(),
      };

  @override
  String toString() =>
      'Advice($strategy, ${candidates.length} candidates, ${intent ?? '<no intent>'})';
}

/// Reads one reply model answer into an [Advice].
///
/// Every check here is a rule the ports agreed on with the model and then had to
/// enforce, because the model does not always keep it: the intent must be hedged
/// and short, a self-assessed confidence may not be claimed without at least one
/// visible fact, the evidence lists are bounded, and a candidate must be a
/// sendable sentence with a reason and a trade-off.
///
/// The one place it is forgiving is the shape of the evidence lists: a bare
/// string, a `{"text": …}` object, or a list of either all normalise to a list of
/// strings. That is because the model has produced all three, and none of them
/// changes what the words mean.
///
/// It **fails closed**: a malformed answer yields an exception and no candidates,
/// never a partial [Advice] the panel could render.
Advice parseAdvice(String raw, {required List<String> strategies}) {
  final Object? decoded = _decode(raw, '模型未返回有效 JSON；未展示候选，请重试');
  if (decoded is! Map) {
    throw const DomainException('模型返回的分析格式不正确');
  }
  final Map<String, Object?> data = decoded.cast<String, Object?>();

  if (data.containsKey('intent')) {
    final Object? intent = data['intent'];
    if (intent is! String || intent.trim().isEmpty || intent.length > 80) {
      throw const DomainException('模型意图判断格式不正确');
    }
  }

  final Object? rawConfidence = data['intent_confidence'];
  final double? confidence = rawConfidence is num ? rawConfidence.toDouble() : null;
  if (rawConfidence != null) {
    final String? intent = data['intent'] as String?;
    if (rawConfidence is! num ||
        rawConfidence is bool ||
        !rawConfidence.isFinite ||
        rawConfidence < 0 ||
        rawConfidence > 1 ||
        intent == null ||
        intent.isEmpty) {
      throw const DomainException('模型意图把握格式不正确');
    }
  }

  for (final String key in const <String>[
    'support',
    'recommendation',
    'next_step',
    'stop_condition',
    'question',
  ]) {
    final Object? value = data[key];
    if (value is! String || value.length > 300) {
      throw const DomainException('模型分析缺少字段或文字过长');
    }
  }

  final Object? strategy = data['strategy'];
  if (strategy is! String || !strategies.contains(strategy)) {
    throw const DomainException('模型返回了未知策略');
  }

  final Map<String, List<String>> evidence = <String, List<String>>{};
  for (final String key in const <String>['facts', 'hypotheses', 'unknowns']) {
    evidence[key] = _normaliseEvidence(data[key], key);
  }

  if (confidence != null && evidence['facts']!.isEmpty) {
    throw const DomainException('缺少可见事实，不能给出意图把握');
  }

  final List<Candidate> candidates = validateCandidates(data['candidates']);

  return Advice(
    support: data['support']! as String,
    facts: evidence['facts']!,
    hypotheses: evidence['hypotheses']!,
    unknowns: evidence['unknowns']!,
    intent: data['intent'] as String?,
    intentConfidence: confidence,
    strategy: strategy,
    recommendation: data['recommendation']! as String,
    nextStep: data['next_step']! as String,
    stopCondition: data['stop_condition']! as String,
    question: data['question']! as String,
    candidates: candidates,
  );
}

/// Checks a candidate list. Shared by the reading step and the rewrite step, so
/// that a rewrite cannot be held to a looser rule than the original.
///
/// Three is the ceiling because the payload's vocabulary sets it there; a fourth
/// candidate would be a screen nobody designed.
List<Candidate> validateCandidates(Object? raw) {
  if (raw is! List || raw.length > 3) {
    throw const DomainException('模型候选数量不正确');
  }
  final List<Candidate> candidates = <Candidate>[];
  for (final Object? item in raw) {
    if (item is! Map) {
      throw const DomainException('模型候选格式不正确');
    }
    final Map<String, Object?> row = item.cast<String, Object?>();
    for (final (String key, int limit) in const <(String, int)>[
      ('text', 100),
      ('reason', 300),
      ('tradeoff', 300),
    ]) {
      final Object? value = row[key];
      if (value is! String || value.length > limit) {
        throw const DomainException('模型候选缺少字段或文字过长');
      }
    }
    final String text = row['text']! as String;
    if (text.trim().isEmpty) {
      throw const DomainException('模型返回空回复');
    }
    candidates.add(Candidate(
      text: text,
      reason: row['reason']! as String,
      tradeoff: row['tradeoff']! as String,
    ));
  }
  return candidates;
}

/// Reads a rewrite answer into a new candidate list.
///
/// **Only candidates may change.** The analysis the user accepted — facts,
/// intent, recommendation, stop condition — is not the rewrite's to revise, so
/// anything else in the answer is dropped rather than merged. A rewrite that
/// changes the strategy is refused outright: that is not a tone change, it is a
/// different decision made without the strategy step.
List<Candidate> parseRewrite(String raw, {required String strategy}) {
  final Object? decoded =
      _decode(raw, '口吻改写未返回有效 JSON；原候选已保留');
  if (decoded is! Map) {
    throw const DomainException('口吻改写格式不正确；原候选已保留');
  }
  final Map<String, Object?> data = decoded.cast<String, Object?>();
  if (data.containsKey('strategy') && data['strategy'] != strategy) {
    throw const DomainException('改写改变了本轮策略，已保留原回复');
  }
  return validateCandidates(data['candidates']);
}

List<String> _normaliseEvidence(Object? raw, String key) {
  Object? items = raw;
  if (items == null) {
    items = const <Object?>[];
  } else if (items is String) {
    items = items.trim().isEmpty ? const <Object?>[] : <Object?>[items];
  } else if (items is Map && items.length == 1 && items.containsKey('text')) {
    items = <Object?>[items['text']];
  }
  if (items is! List || items.length > 20) {
    throw DomainException('模型证据格式不正确（$key）；请重新分析');
  }
  final List<String> normalised = <String>[];
  for (Object? item in items) {
    if (item is Map && item.length == 1 && item.containsKey('text')) {
      item = item['text'];
    }
    if (item is! String || item.length > 500) {
      throw DomainException('模型证据格式不正确（$key）；请重新分析');
    }
    if (item.trim().isNotEmpty) {
      normalised.add(item.trim());
    }
  }
  return normalised;
}

Object? _decode(String raw, String message) {
  try {
    return jsonDecode(raw);
  } on FormatException {
    throw DomainException(message);
  } on TypeError {
    throw DomainException(message);
  }
}
