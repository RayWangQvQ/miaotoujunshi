import 'advice.dart';
import 'scoring.dart';
import 'strategy.dart';

/// The caveat that always accompanies a self-assessed intent confidence.
const String intentConfidenceNote =
    '这是回复模型对当前意图推测的自评把握，未经过统计校准；不是对方真实意图的已验证概率，也不是回复成功率。';

/// The caveat on a self-reported strategy confidence, when no token weights
/// could be published.
const String selfReportNote = '模型自评把握未经统计校准；不是回复成功率。';

/// How a decision's source is named. The prefix is the only thing that
/// distinguishes the two routes in the output, so it is read from the model
/// string rather than passed alongside it — a call site that forgot to say which
/// one would otherwise be believed.
String strategySourceLabel(String model) =>
    model.startsWith('jev-') ? 'Jev' : 'DeepSeek';

/// The one line the panel shows for the model's grip on its own intent guess.
///
/// Three outcomes, not two. Absent means the model declined — which the panel
/// must say in words, because showing `0%` would turn "I cannot tell" into "I am
/// certain it is not that", and those are opposite claims.
String intentConfidenceLabel(double? value) => value == null
    ? '判断把握 · 暂无法判断'
    : '判断把握 · ${(value * 100).round()}%（模型估计）';

/// Renders a strategy decision for a person.
///
/// The three methods read differently on purpose, and the difference is the whole
/// point of having three. A token distribution is shown with all seven weights,
/// ordered, and says where they came from. A self-report says the weights are
/// unavailable instead of showing an empty list as if it were a distribution. A
/// Jev decision says neither — it reports the service's own confidence and warns
/// that it is not a success rate.
///
/// Every branch ends with the same refusal: none of these numbers is a
/// probability of anything about the other person.
String formatStrategyDecision(
  StrategyDecision decision, {
  required List<String> strategies,
}) {
  final String source = strategySourceLabel(decision.model);
  final String name = decision.strategy;
  final StringBuffer text = StringBuffer();

  switch (decision.method) {
    case StrategyMethod.deepseekLogprobs:
      final double confidence = decision.confidence ?? 0;
      final List<String> ordered = List<String>.of(strategies)
        ..sort((String a, String b) {
          final int byWeight =
              decision.probabilities[b]!.compareTo(decision.probabilities[a]!);
          return byWeight != 0 ? byWeight : strategies.indexOf(a).compareTo(strategies.indexOf(b));
        });
      text
        ..write('$source 选择「$name」；策略选择权重 ${_percent1(confidence)}。\n')
        ..write('七策略相对权重：')
        ..write(ordered
            .map((String strategy) =>
                '$strategy ${_weightText(decision.probabilities[strategy] ?? 0)}')
            .join(' · '))
        ..write('\n来自三次标签轮换的首 token 概率，未经统计校准；不是回复成功率。');
    case StrategyMethod.deepseekSelfReport:
      final double? confidence = decision.confidence;
      final String estimate = confidence == null
          ? '模型自评把握暂不可用；不是回复成功率。'
          : '模型自评把握 ${(confidence * 100).round()}%，$selfReportNote';
      text
        ..write('$source 选择「$name」；策略 token 权重暂不可用。\n')
        ..write(estimate);
    case StrategyMethod.jev:
      final double confidence = decision.confidence ?? 0;
      text
        ..write('$source 选择「$name」；策略置信度 ${(confidence * 100).round()}%。\n')
        ..write('这是模型对策略选择的判断，不是回复成功率，也不是候选推荐权重。');
  }

  final Object? facts = decision.evidence['facts'];
  if (facts is List && facts.isNotEmpty) {
    text.write('\n判断依据：${facts.join('；')}');
  }
  return text.toString();
}

/// Renders a whole analysis, in the order the panel shows it.
///
/// Pure and deterministic: the same [Advice] always produces the same text. It
/// takes no widget type and returns no widget — the panel paints it, the tests
/// assert on it, and neither needs a device.
String formatAdvice(Advice advice, {required List<String> strategies}) {
  final List<String> chunks = <String>[
    advice.support,
    '首选 · ${advice.strategy}\n${advice.recommendation}',
    '对方可能的意图\n${advice.intent ?? _fallbackIntent(advice)}',
    '${intentConfidenceLabel(advice.intentConfidence)}\n$intentConfidenceNote',
  ];

  final StrategyDecision? decision = advice.strategyDecision;
  if (decision != null) {
    chunks.add(
      '策略来源：${decision.model}\n'
      '${formatStrategyDecision(decision, strategies: strategies)}',
    );
  }

  for (final (List<String> rows, String label) in <(List<String>, String)>[
    (advice.facts, '已知事实'),
    (advice.hypotheses, '合理推测'),
    (advice.unknowns, '仍未知'),
  ]) {
    if (rows.isNotEmpty) {
      chunks.add('$label\n${rows.map((String row) => '• $row').join('\n')}');
    }
  }

  chunks
    ..add('下一步\n${advice.nextStep}')
    ..add('停止条件\n${advice.stopCondition}');
  if (advice.question.isNotEmpty) {
    chunks.add('关键追问\n${advice.question}');
  }

  for (int i = 0; i < advice.candidates.length; i++) {
    final Candidate candidate = advice.candidates[i];
    final String weight = candidate.weight == null ? '' : ' · ${candidate.weight}%';
    chunks.add(
      '候选 ${i + 1}$weight\n${candidate.text}\n'
      '理由：${candidate.reason}\n代价：${candidate.tradeoff}',
    );
  }
  if (advice.candidates.isNotEmpty) {
    chunks.add(
      '候选回复排序\n'
      '${advice.rankingStatus == RankingStatus.unavailable ? '排序暂不可用；保留生成顺序。' : rankingExplanation}',
    );
  }

  return chunks.join('\n\n');
}

String _fallbackIntent(Advice advice) =>
    advice.hypotheses.isNotEmpty ? advice.hypotheses.join('；') : '证据不足，暂无法判断';

String _percent1(double value) => '${(value * 100).toStringAsFixed(1)}%';

String _weightText(double value) =>
    (value > 0 && value < .001) ? '<0.1%' : '${(value * 100).toStringAsFixed(1)}%';
