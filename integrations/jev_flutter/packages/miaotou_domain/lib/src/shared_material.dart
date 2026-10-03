import 'dart:convert';

import 'package:miaotou_capabilities/miaotou_capabilities.dart';

import 'errors.dart';
import 'preferences.dart';

// The keys are repository-root-relative, exactly the convention `payload-map.json`
// already uses and `SharedPayload.read` documents (ADR-0008). Spelling them once,
// here, is what lets the packaging guard assert that every key the app ever asks
// for really shipped.
const String payloadMapPath = 'miaotoujunshi/references/data/payload-map.json';
const String strategyCriteriaPath =
    'miaotoujunshi/references/data/strategy-criteria.json';
const String judgeQuestionsPath =
    'miaotoujunshi/references/data/judge-questions.json';
const String replyPreferencesPath =
    'miaotoujunshi/references/data/reply-preferences.json';

/// The upstream skill document, which the reply prompt quotes whole.
const String skillDocumentPath = 'goutoujunshi/SKILL.md';

/// The heading the strategy guide is cut before.
///
/// It is an **upstream** heading string, so it is data the app depends on rather
/// than a choice: the examples that follow it are written for the reply model,
/// and letting them into the strategy decision would show that model its own
/// answers. The existing suite locks the cut, which is why the constant lives
/// here and not at the call site.
const String guideHeading = '## 常用话术库';

/// One of the seven calibrated judge questions.
final class JudgeQuestion {
  const JudgeQuestion({
    required this.type,
    required this.instructions,
    this.criteria,
  });

  /// `noul`, `score` or `choice` — which answer shape the question expects.
  final String type;

  final String instructions;

  /// The criteria, as whatever shape the question declares: a map for the
  /// choice questions, a list of bands for the score question. Kept as raw JSON
  /// because these strings travel to the provider and any re-typing would break
  /// the calibration they passed.
  final Object? criteria;
}

/// The judge set and the two strings that go with it.
final class JudgeSet {
  const JudgeSet({
    required this.questions,
    required this.rankInstructions,
    required this.nextStep,
    required this.nextStepFallback,
  });

  /// In the order the payload lists them, which is the order they are asked.
  final Map<String, JudgeQuestion> questions;

  final String rankInstructions;
  final Map<String, String> nextStep;
  final String nextStepFallback;
}

/// The reply tone, length and count vocabularies, and the rules for turning a
/// choice into a preference.
final class ReplyVocabulary {
  const ReplyVocabulary({
    required this.tones,
    required this.toneGuidance,
    required this.lengths,
    required this.defaultCount,
    required this.minCount,
    required this.maxCount,
  });

  final List<String> tones;
  final Map<String, String> toneGuidance;

  /// Tier name → the character ceiling for one candidate.
  final Map<String, int> lengths;

  final int defaultCount;
  final int minCount;
  final int maxCount;

  /// Validates one round's choice and resolves its ceiling.
  ///
  /// Named `resolve` rather than `reply` so that it cannot be confused with the
  /// [SharedVocabulary.reply] field that holds this object: a round's settings
  /// are a *reading* of the vocabulary, not the vocabulary itself.
  ReplyPreferences resolve({String? tone, String? length, int? count}) {
    final String chosenTone = tone ?? tones.first;
    final String chosenLength = length ?? lengths.keys.first;
    final int chosenCount = count ?? defaultCount;
    if (!tones.contains(chosenTone) ||
        !lengths.containsKey(chosenLength) ||
        chosenCount < minCount ||
        chosenCount > maxCount) {
      throw const DomainException('请选择有效的回复口吻、长度和候选数量');
    }
    return ReplyPreferences(
      tone: chosenTone,
      length: chosenLength,
      count: chosenCount,
      maxChars: lengths[chosenLength]!,
    );
  }
}

/// Everything the domain reads out of the shared *data* files.
///
/// One value, parsed once, so that a strategy name, a criterion, a label and a
/// tone all come from the same read — and so that the two criteria maps can never
/// be swapped by accident. They are not interchangeable: see [typesafeCriteria].
final class SharedVocabulary {
  const SharedVocabulary({
    required this.strategies,
    required this.typesafeCriteria,
    required this.deepseekCriteria,
    required this.labels,
    required this.rotations,
    required this.judge,
    required this.reply,
    required this.strategyGuidePath,
    required this.sharedToneDocumentPath,
    required this.sceneKnowledge,
  });

  /// The seven strategies, in the order the payload declares them.
  final List<String> strategies;

  /// English. Goes to the TypeSafe Jev endpoint, and nowhere else.
  final Map<String, String> typesafeCriteria;

  /// Chinese. Goes to the DeepSeek strategy route, and nowhere else.
  ///
  /// The split is not cosmetic and it is not this package's invention: the
  /// payload's own provenance says which of the two each route gets, and the
  /// Windows and Android ports already read it that way. The macOS port sent the
  /// English map to DeepSeek as well — a divergence this convergence removes,
  /// because "one implementation rather than three" has to pick, and the payload
  /// is the source of truth the ports agreed on (ADR-0005).
  final Map<String, String> deepseekCriteria;

  /// The letters a rotated choice request offers, one per strategy.
  final List<String> labels;

  /// The label-map offsets the DeepSeek route rotates through. Three of them,
  /// and agreement between all three is what earns a published distribution.
  final List<int> rotations;

  final JudgeSet judge;
  final ReplyVocabulary reply;

  /// Repository-root-relative path of the strategy guide.
  final String strategyGuidePath;

  /// …of the tone document this repository adds on top of the payload.
  final String sharedToneDocumentPath;

  /// Scene name → the knowledge document that scene is analysed against.
  final Map<String, String> sceneKnowledge;

  /// The scene names, in the payload's order.
  List<String> get scenes => sceneKnowledge.keys.toList();

  /// Parses the four data files. Pure: the caller has already read them.
  static SharedVocabulary parse({
    required String criteria,
    required String judge,
    required String preferences,
    required String payloadMap,
  }) {
    final Map<String, Object?> criteriaJson = _asMap(jsonDecode(criteria));
    final Map<String, Object?> judgeJson = _asMap(jsonDecode(judge));
    final Map<String, Object?> preferencesJson = _asMap(jsonDecode(preferences));
    final Map<String, Object?> mapJson = _asMap(jsonDecode(payloadMap));

    final Map<String, Object?> questionsJson =
        _asMap(judgeJson['questions'] ?? const <String, Object?>{});
    final Map<String, Object?> candidateLimits =
        _asMap(preferencesJson['candidates'] ?? const <String, Object?>{});
    final Map<String, Object?> lengthsJson = _asMap(preferencesJson['lengths']);

    return SharedVocabulary(
      strategies: _asStringList(criteriaJson['strategies']),
      typesafeCriteria: _asStringMap(criteriaJson['typesafe_criteria']),
      deepseekCriteria: _asStringMap(criteriaJson['deepseek_criteria']),
      labels: _asString(criteriaJson['choice_labels']).split(''),
      rotations: <int>[
        for (final Object? offset in _asList(criteriaJson['rotations']))
          _asInt(offset),
      ],
      judge: JudgeSet(
        questions: <String, JudgeQuestion>{
          for (final MapEntry<String, Object?> entry in questionsJson.entries)
            entry.key: _judgeQuestion(entry.value),
        },
        rankInstructions: _asString(judgeJson['rank_instructions']),
        nextStep: _asStringMap(judgeJson['next_step']),
        nextStepFallback: _asString(judgeJson['next_step_fallback']),
      ),
      reply: ReplyVocabulary(
        tones: _asStringList(preferencesJson['tones']),
        toneGuidance: _asStringMap(preferencesJson['tone_guidance']),
        lengths: <String, int>{
          for (final MapEntry<String, Object?> entry in lengthsJson.entries)
            entry.key: _asInt(entry.value),
        },
        defaultCount: _asInt(candidateLimits['default']),
        minCount: _asInt(candidateLimits['min']),
        maxCount: _asInt(candidateLimits['max']),
      ),
      strategyGuidePath: _asString(mapJson['strategy_guide']),
      sharedToneDocumentPath: _asString(mapJson['shared_tone_document']),
      sceneKnowledge: _asStringMap(mapJson['scene_knowledge']),
    );
  }
}

/// The documents one scene is analysed against, already read and already cut.
final class SceneMaterial {
  const SceneMaterial({
    required this.scene,
    required this.skill,
    required this.strategyGuide,
    required this.toneDocument,
    required this.sceneKnowledge,
    required this.materialPaths,
  });

  final String scene;

  /// The upstream skill document, quoted whole into the reply prompt.
  final String skill;

  /// The strategy guide, cut before [guideHeading].
  final String strategyGuide;

  final String toneDocument;
  final String sceneKnowledge;

  /// The three repository-relative paths, in the order the ports loaded them.
  /// Carried so the application can show which material a verdict rested on.
  final List<String> materialPaths;

  /// The three documents as the prompt wants them: in one block, in order.
  String get references =>
      <String>[strategyGuide, toneDocument, sceneKnowledge].join('\n\n');
}

/// Reads the shared payload, once per file, and hands back what the domain needs.
///
/// It caches because the same guide is re-read for every analysis and the
/// documents are not small; it is not a general-purpose loader and deliberately
/// offers no write, no list and no fallback. A missing file is a hard error all
/// the way up: a forgotten packaging entry has to be loud, not a quietly empty
/// prompt (ADR-0008).
final class SharedMaterial {
  SharedMaterial(this.vocabulary, {required this.payload});

  final SharedVocabulary vocabulary;

  /// The capability the documents are read through. Held rather than copied from,
  /// because a scene is loaded lazily and the payload is what loads it.
  final SharedPayload payload;

  final Map<String, String> _texts = <String, String>{};
  final Map<String, SceneMaterial> _scenes = <String, SceneMaterial>{};

  static Future<SharedMaterial> load(SharedPayload payload) async {
    final SharedVocabulary vocabulary = SharedVocabulary.parse(
      criteria: await _text(payload, strategyCriteriaPath),
      judge: await _text(payload, judgeQuestionsPath),
      preferences: await _text(payload, replyPreferencesPath),
      payloadMap: await _text(payload, payloadMapPath),
    );
    return SharedMaterial(vocabulary, payload: payload);
  }

  /// One payload file as text, decoded once.
  Future<String> text(String repoRelativePath) async {
    final String? cached = _texts[repoRelativePath];
    if (cached != null) {
      return cached;
    }
    final String value = await _text(payload, repoRelativePath);
    _texts[repoRelativePath] = value;
    return value;
  }

  /// Everything one scene needs, read and cut once.
  ///
  /// An unknown scene is refused rather than defaulted: analysing against the
  /// wrong scene's knowledge would produce a confident answer to a question
  /// nobody asked.
  Future<SceneMaterial> scene(String scene) async {
    final SceneMaterial? cached = _scenes[scene];
    if (cached != null) {
      return cached;
    }
    final String? knowledgePath = vocabulary.sceneKnowledge[scene];
    if (knowledgePath == null) {
      throw const DomainException('请选择有效的分析场景');
    }
    final String guidePath = vocabulary.strategyGuidePath;
    final String tonePath = vocabulary.sharedToneDocumentPath;
    final SceneMaterial material = SceneMaterial(
      scene: scene,
      skill: await text(skillDocumentPath),
      strategyGuide: _cutAt(await text(guidePath), guideHeading),
      toneDocument: await text(tonePath),
      sceneKnowledge: await text(knowledgePath),
      materialPaths: <String>[guidePath, tonePath, knowledgePath],
    );
    _scenes[scene] = material;
    return material;
  }
}

/// Everything before the first occurrence of [heading].
///
/// `split` returns the whole string as its only element when the heading is
/// absent, so a guide that lost its examples section degrades to "use all of it"
/// rather than to "use none of it".
String _cutAt(String text, String heading) => text.split(heading).first;

Future<String> _text(SharedPayload payload, String path) async =>
    utf8.decode(await payload.read(path));

JudgeQuestion _judgeQuestion(Object? raw) {
  final Map<String, Object?> map = _asMap(raw);
  return JudgeQuestion(
    type: _asString(map['type']),
    instructions: _asString(map['instructions']),
    criteria: map['criteria'],
  );
}

Map<String, Object?> _asMap(Object? raw) {
  if (raw is! Map) {
    throw DomainException('共享载荷格式不正确：期望一个 JSON 对象，得到 ${raw.runtimeType}');
  }
  return raw.cast<String, Object?>();
}

List<Object?> _asList(Object? raw) {
  if (raw is! List) {
    throw DomainException('共享载荷格式不正确：期望一个数组，得到 ${raw.runtimeType}');
  }
  return raw.cast<Object?>();
}

String _asString(Object? raw) {
  if (raw is! String) {
    throw DomainException('共享载荷格式不正确：期望一个字符串，得到 ${raw.runtimeType}');
  }
  return raw;
}

int _asInt(Object? raw) {
  if (raw is! int) {
    throw DomainException('共享载荷格式不正确：期望一个整数，得到 ${raw.runtimeType}');
  }
  return raw;
}

List<String> _asStringList(Object? raw) =>
    <String>[for (final Object? item in _asList(raw)) _asString(item)];

Map<String, String> _asStringMap(Object? raw) => <String, String>{
      for (final MapEntry<String, Object?> entry in _asMap(raw).entries)
        entry.key: _asString(entry.value),
    };
