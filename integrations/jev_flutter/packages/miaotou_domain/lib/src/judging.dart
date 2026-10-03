import 'dart:convert';

import 'errors.dart';
import 'model_gateway.dart';
import 'prompts.dart';
import 'shared_material.dart';
import 'snapshot.dart';
import 'strategy.dart';

/// Decides the strategy through the TypeSafe judging endpoint.
///
/// The whole route is: assemble the request, post it, read the answer. The
/// request assembly and the answer's interpretation are both here; only the
/// posting is the transport's, which is why this function has no HTTP status
/// handling in it and no timeouts. A failure on the wire arrives as a
/// [DomainException] the transport composed, and travels out unchanged — the
/// strategy step has no repair path on this route, because the service answers a
/// question at a time and a malformed answer means the question was not the one
/// it heard.
Future<StrategyDecision> decideJev({
  required ModelTransport transport,
  required SharedVocabulary vocabulary,
  required SceneMaterial material,
  required Snapshot snapshot,
  required String scene,
  required String background,
  required String model,
}) async {
  final Map<String, Object?> payload = buildJevRequest(
    model: model,
    snapshot: snapshot,
    scene: scene,
    background: background,
    material: material,
    vocabulary: vocabulary,
  );
  final String body = await transport.systemone(payload);

  final Object? decoded;
  try {
    decoded = jsonDecode(body);
  } on FormatException {
    throw const DomainException('Jev 响应不是有效 JSON');
  }
  return parseJevDecision(
    decoded,
    strategies: vocabulary.strategies,
    questionNames: vocabulary.judge.questions.keys,
  );
}

/// Decides the strategy through the DeepSeek route.
///
/// Three steps, and the escalation between them is the design:
///
/// 1. **the evidence pass** — a JSON answer giving the strategy, the facts, the
///    unknowns and whether there was an explicit refusal. If it does not parse,
///    one shorter request retries with the shape spelled out in an example; two
///    failures in a row is where this route stops.
/// 2. **a stop** — if any line is unattributed or unverified, the answer stops
///    here, as a self-reported decision with **no confidence and no weights**. A
///    rotation over labels cannot be called stable when the labels are in doubt.
/// 3. **the rotated choice requests** — the same question asked three times with
///    the letters permuted. Weights are published only if all three agree with
///    each other *and* with the evidence pass; otherwise the evidence-backed
///    decision stands on its own.
///
/// The failure mode this is built to avoid is a plausible distribution. A single
/// request's weights measure the model's taste for letter order; a partial set
/// normalised to 1 would be arithmetic over noise. So an unusable rotation is
/// discarded, never repaired, and never silently replaced by the other provider.
Future<StrategyDecision> decideDeepSeek({
  required ModelTransport transport,
  required SharedVocabulary vocabulary,
  required SceneMaterial material,
  required Snapshot snapshot,
  required String scene,
  required String background,
  required String model,
}) async {
  checkBackground(background);

  final StrategyDecision fallback = await _evidenceDecision(
    transport: transport,
    evidenceRequest: ChatRequest(
      model: model,
      jsonMode: true,
      messages: buildStrategyEvidencePrompt(
        snapshot: snapshot,
        scene: scene,
        background: background,
        material: material,
        vocabulary: vocabulary,
      ),
    ),
    repairRequest: ChatRequest(
      model: model,
      jsonMode: true,
      messages: buildStrategyRepairPrompt(
        snapshot: snapshot,
        scene: scene,
        background: background,
        vocabulary: vocabulary,
      ),
    ),
    model: model,
    strategies: vocabulary.strategies,
  );

  if (transcriptHasUnconfirmed(snapshot.transcript)) {
    return StrategyDecision(
      strategy: fallback.strategy,
      confidence: null,
      probabilities: const <String, double>{},
      model: fallback.model,
      method: StrategyMethod.deepseekSelfReport,
      evidence: fallback.evidence,
    );
  }

  try {
    final List<Map<String, double>> distributions = <Map<String, double>>[];
    for (final int offset in vocabulary.rotations) {
      final Map<String, String> labels =
          rotatedLabels(vocabulary: vocabulary, offset: offset);
      final ChatCompletion choice = await transport.chat(
        ChatRoute.strategy,
        ChatRequest(
          model: model,
          choiceLogprobs: true,
          messages: buildStrategyChoicePrompt(
            snapshot: snapshot,
            scene: scene,
            background: background,
            evidence: fallback.evidence,
            labels: labels,
            vocabulary: vocabulary,
          ),
        ),
      );
      final Logprobs? logprobs = choice.logprobs;
      if (logprobs == null) {
        throw const DomainException('DeepSeek 策略 token 权重不可用');
      }
      distributions.add(parseChoice(
        content: choice.content,
        top: logprobs.top,
        firstToken: logprobs.firstToken,
        labels: labels,
      ));
    }

    final List<String> winners = <String>[
      for (final Map<String, double> scores in distributions)
        winnerOf(scores, vocabulary.strategies),
    ];
    if (winners.toSet().length != 1 || winners.first != fallback.strategy) {
      return fallback;
    }

    final Map<String, double> average = <String, double>{
      for (final String strategy in vocabulary.strategies)
        strategy: distributions
                .map((Map<String, double> scores) => scores[strategy]!)
                .reduce((double a, double b) => a + b) /
            distributions.length,
    };
    return StrategyDecision(
      strategy: winners.first,
      confidence: average[winners.first],
      probabilities: average,
      model: model,
      method: StrategyMethod.deepseekLogprobs,
      evidence: fallback.evidence,
    );
  } on DomainException {
    // Keep the independent DeepSeek decision; never fabricate a distribution
    // and never silently fall back to the other provider.
    return fallback;
  }
}

/// The strategy with the highest weight, **ties going to the first in the
/// payload's order**.
///
/// The tie rule is not cosmetic: three rotations of a weak preference can easily
/// produce equal weights, and picking by map iteration order would make the
/// published strategy depend on how the payload happened to be written.
String winnerOf(Map<String, double> scores, List<String> strategies) {
  String best = strategies.first;
  for (final String strategy in strategies) {
    if (scores[strategy]! > scores[best]!) {
      best = strategy;
    }
  }
  return best;
}

/// The evidence pass, with its single repair attempt.
///
/// The repair exists because the evidence contract is long and a model
/// occasionally answers the question without its envelope; asking again with the
/// shape spelled out in an example recovers far more often than re-sending the
/// same request. **Two failures in a row is where this route stops**, and it says
/// so — it does not fall back to the other provider, and it does not invent a
/// strategy to keep the round alive.
Future<StrategyDecision> _evidenceDecision({
  required ModelTransport transport,
  required ChatRequest evidenceRequest,
  required ChatRequest repairRequest,
  required String model,
  required List<String> strategies,
}) async {
  final ChatCompletion evidence =
      await transport.chat(ChatRoute.strategy, evidenceRequest);
  try {
    return parseDeepSeekDecision(evidence.content, model: model, strategies: strategies);
  } on DomainException {
    final ChatCompletion repaired =
        await transport.chat(ChatRoute.strategy, repairRequest);
    try {
      return parseDeepSeekDecision(repaired.content, model: model, strategies: strategies);
    } on DomainException {
      throw const DomainException('DeepSeek 连续两次未返回有效策略；请核对原文后重试');
    }
  }
}
