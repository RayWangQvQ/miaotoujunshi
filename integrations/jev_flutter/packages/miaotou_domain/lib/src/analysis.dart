import 'advice.dart';
import 'errors.dart';
import 'injection_filter.dart';
import 'judging.dart';
import 'model_gateway.dart';
import 'preferences.dart';
import 'prompts.dart';
import 'scoring.dart';
import 'shared_material.dart';
import 'snapshot.dart';
import 'strategy.dart';

/// One round, end to end: a snapshot in, a verdict and drafts out.
///
/// This is the function AC1 is about. It runs with no device, no toolkit and no
/// Flutter, and everything it needs from outside is one injected
/// [ModelTransport] — so a test can drive the whole product's judgement with a
/// teletype of canned answers and assert on the result in milliseconds.
///
/// The order is a decision, not an implementation detail:
///
/// 1. **validate everything local first.** The scene must resolve, the background
///    must fit, and the transcript must not be entirely unattributable. All three
///    are refusals that cost nothing, and doing them before the first request is
///    what keeps a bad input from becoming a billed call.
/// 2. **decide the strategy, once.** Either route, never both — and with one
///    nullable argument the type makes "both" unrepresentable rather than
///    checked. A strategy failure is fatal here and the reply model is never
///    asked: drafting a reply to a question nobody decided is how a confident
///    wrong answer gets made.
/// 3. **draft, pinned to that strategy.** The decision travels in the system
///    prompt *and* in the payload, so the model sees both the instruction and the
///    evidence behind it.
/// 4. **check that it obeyed**, then rank.
///
/// Step 4's checks are refusals, not corrections: a reply that ignored the
/// user's candidate count or the pinned strategy is not silently trimmed to fit.
/// It is thrown away, because a trimmed reply has already been written for a
/// different contract.
Future<Advice> analyzeSnapshot({
  required ModelTransport transport,
  required SharedMaterial material,
  required Snapshot snapshot,
  required String scene,
  required String background,
  required String replyModel,
  StrategyRoute? strategyRoute,
  ReplyPreferences? preferences,
}) async {
  // Resolving the scene is also the scene's validation: an unknown name is
  // refused here, before the strategy call, not after the money is spent.
  final SceneMaterial sceneMaterial = await material.scene(scene);
  checkAnalysable(snapshot, background);

  final StrategyDecision? decision = switch (strategyRoute?.engine) {
    StrategyEngine.jev => await decideJev(
        transport: transport,
        vocabulary: material.vocabulary,
        material: sceneMaterial,
        snapshot: snapshot,
        scene: scene,
        background: background,
        model: strategyRoute!.model,
      ),
    StrategyEngine.deepseek => await decideDeepSeek(
        transport: transport,
        vocabulary: material.vocabulary,
        material: sceneMaterial,
        snapshot: snapshot,
        scene: scene,
        background: background,
        model: strategyRoute!.model,
      ),
    null => null,
  };

  final ReplyPrompt prompt = buildReplyPrompt(
    snapshot: snapshot,
    scene: scene,
    background: background,
    material: sceneMaterial,
    vocabulary: material.vocabulary,
    preferences: preferences,
    strategyDecision: decision,
  );

  final ChatCompletion completion = await transport.chat(
    ChatRoute.reply,
    ChatRequest(model: replyModel, messages: prompt.messages),
  );
  Advice advice = parseAdvice(
    completion.content,
    strategies: material.vocabulary.strategies,
  );
  advice = advice.copyWith(candidates: _filterCandidates(snapshot, advice.candidates));

  if (preferences != null &&
      (advice.candidates.length > preferences.count ||
          advice.candidates
              .any((Candidate candidate) => candidate.text.length > preferences.maxChars))) {
    throw const DomainException('模型未遵守候选数量或长度设置；未展示候选，请重试');
  }

  if (decision != null) {
    if (advice.strategy != decision.strategy) {
      throw const DomainException('回复模型未遵循独立步骤选定的策略；未展示候选，请重试');
    }
    advice = advice.copyWith(strategyDecision: decision);
  }

  return rankCandidates(
    transport: transport,
    model: replyModel,
    snapshot: snapshot,
    scene: scene,
    background: background,
    advice: advice,
    preferences: preferences,
  );
}

/// Drops candidates that obeyed an injection attempt embedded in the captured
/// conversation, then maps the survivors back to [Candidate] objects.
///
/// A pasted transcript has no captured lines; the filter is a no-op for it, and
/// the system prompt's "chat text is data" instruction is the only defence.
/// For a captured conversation the filter is the structural backstop the system
/// prompt cannot guarantee on its own — the model can be tricked into producing
/// the injection's payload, and the candidate never reaches the user.
///
/// Kept here rather than inside `parseAdvice` because the filter needs the
/// structured lines, and a parser that takes lines would force every caller to
/// fabricate them; the analysis pipeline already has them on the snapshot.
List<Candidate> _filterCandidates(Snapshot snapshot, List<Candidate> candidates) {
  if (snapshot.capturedLines.isEmpty) {
    return candidates;
  }
  final List<String> texts = <String>[
    for (final Candidate candidate in candidates) candidate.text,
  ];
  final List<String> kept = sanitizeCandidateTexts(
    suspects: suspectInjectionTexts(snapshot.capturedLines),
    otherRecent: otherRecentTexts(snapshot.capturedLines),
    candidates: texts,
  );
  // Map back by consuming each survivor once, not by testing membership: the
  // filter deduplicates, so two candidates with the same text must not both
  // match the one survivor. A `Set.contains` here would put three identical
  // TARGETs back on the panel.
  final List<String> remaining = List<String>.of(kept);
  return <Candidate>[
    for (final Candidate candidate in candidates)
      if (remaining.remove(candidate.text)) candidate,
  ];
}

/// Rewrites the drafts so they read more like the user, and nothing else.
///
/// Narrow by construction. The accepted analysis — facts, intent, confidence,
/// recommendation, stop condition — is carried through untouched, because the
/// user already accepted it and a "tone" pass is not entitled to revise it. Only
/// the candidate texts are replaced, and a rewrite that changes the strategy, or
/// comes back empty, or overruns the length the user chose is refused so that the
/// originals stay on screen.
///
/// The strategy step is **not** re-run. There is no argument for it here, which is
/// how "rewriting must not re-decide" is enforced rather than remembered.
Future<Advice> rewriteSnapshot({
  required ModelTransport transport,
  required SharedMaterial material,
  required Snapshot snapshot,
  required String scene,
  required String background,
  required Advice previous,
  required String replyModel,
  ReplyPreferences? preferences,
}) async {
  if (previous.candidates.isEmpty) {
    throw const DomainException('本轮建议不回复，无需改写');
  }
  final SceneMaterial sceneMaterial = await material.scene(scene);

  final ReplyPrompt prompt = buildRewritePrompt(
    snapshot: snapshot,
    scene: scene,
    background: background,
    material: sceneMaterial,
    previous: previous,
    preferences: preferences,
    vocabulary: material.vocabulary,
  );

  final ChatCompletion completion = await transport.chat(
    ChatRoute.reply,
    ChatRequest(model: replyModel, messages: prompt.messages),
  );
  final List<Candidate> candidates = parseRewrite(
    completion.content,
    strategy: previous.strategy,
  );
  final List<Candidate> filtered = _filterCandidates(snapshot, candidates);
  if (filtered.isEmpty) {
    throw const DomainException('改写未返回可用候选，已保留原回复');
  }
  if (preferences != null &&
      (filtered.length > preferences.count ||
          filtered
              .any((Candidate candidate) => candidate.text.length > preferences.maxChars))) {
    throw const DomainException('改写未遵守数量或长度，已保留原回复');
  }

  return rankCandidates(
    transport: transport,
    model: replyModel,
    snapshot: snapshot,
    scene: scene,
    background: background,
    advice: previous.copyWith(candidates: filtered),
    preferences: preferences,
  );
}
