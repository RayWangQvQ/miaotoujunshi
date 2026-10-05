import 'dart:convert';

import 'package:miaotou_capabilities/miaotou_capabilities.dart';

import 'errors.dart';
import 'prompts.dart';

/// The stage/goal/scene vocabulary this application adds on top of the payload.
///
/// Source: [relationshipEnumsPath], whose own provenance says "this repository's
/// own vocabulary, app layer". macOS was the only port that read it; Windows
/// spelled the stages and goals out as a Python tuple, and Android kept them as
/// free text with a hint. This convergence reads the payload on all three,
/// because inventing the values a second time is exactly how the ports drifted.
const String relationshipEnumsPath =
    'miaotoujunshi/references/data/relationship-enums.json';

/// The fields a profile holds, in the order they are saved and restored.
///
/// `label` leads and is written to the store as `display_label` (see
/// [Profile.storeField]); the remaining eight are the payload's
/// `profile_fields` verbatim. Listing them here once keeps [Profile.value]
/// and the diff loop addressing the same names the payload uses.
const List<String> profileFields = <String>[
  'label',
  'stage',
  'goal',
  'background',
  'my_mbti',
  'their_mbti',
  'my_score',
  'their_score',
  'notes',
];

/// One remembered conversation partner, in the values the application works in.
///
/// "Unknown" is the empty string. The store-level marker `未填写` is a separate
/// concern — the upstream CLI does not accept empty strings, so the bridge
/// writes the marker and reads it back; the domain never sees the marker, and
/// `stage`/`goal` keep `未填写` as a real value (the first stage is named that).
final class Profile {
  const Profile({
    required this.id,
    required this.label,
    this.stage = '未填写',
    this.goal = '自然接话',
    this.background = '',
    this.myMbti = '',
    this.theirMbti = '',
    this.myScore = '',
    this.theirScore = '',
    this.notes = '',
  });

  final String id;
  final String label;
  final String stage;
  final String goal;
  final String background;
  final String myMbti;
  final String theirMbti;
  final String myScore;
  final String theirScore;
  final String notes;

  /// A new profile with a fresh id. The id itself is a port concern
  /// (macOS prefixed `mac-`, Android will prefix `android-`), so the caller
  /// supplies it; the domain only carries it.
  factory Profile.empty({required String id, String label = '当前会话'}) =>
      Profile(id: id, label: label);

  /// Maps a profile field key to the field name the memory store uses.
  static String storeField(String key) =>
      key == 'label' ? 'display_label' : key;

  /// The current value of one field by its payload key.
  String value(String key) {
    switch (key) {
      case 'label':
        return label;
      case 'stage':
        return stage;
      case 'goal':
        return goal;
      case 'background':
        return background;
      case 'my_mbti':
        return myMbti;
      case 'their_mbti':
        return theirMbti;
      case 'my_score':
        return myScore;
      case 'their_score':
        return theirScore;
      case 'notes':
        return notes;
      default:
        throw DomainException('未知资料字段：$key');
    }
  }

  /// A copy with one field changed by payload key. Used by the test fixtures and
  /// by the diff loop's caller; not by [diffProfile] itself.
  Profile withValue(String key, String value) {
    switch (key) {
      case 'label':
        return Profile(id: id, label: value, stage: stage, goal: goal,
            background: background, myMbti: myMbti, theirMbti: theirMbti,
            myScore: myScore, theirScore: theirScore, notes: notes);
      case 'stage':
        return Profile(id: id, label: label, stage: value, goal: goal,
            background: background, myMbti: myMbti, theirMbti: theirMbti,
            myScore: myScore, theirScore: theirScore, notes: notes);
      case 'goal':
        return Profile(id: id, label: label, stage: stage, goal: value,
            background: background, myMbti: myMbti, theirMbti: theirMbti,
            myScore: myScore, theirScore: theirScore, notes: notes);
      case 'background':
        return Profile(id: id, label: label, stage: stage, goal: goal,
            background: value, myMbti: myMbti, theirMbti: theirMbti,
            myScore: myScore, theirScore: theirScore, notes: notes);
      case 'my_mbti':
        return Profile(id: id, label: label, stage: stage, goal: goal,
            background: background, myMbti: value, theirMbti: theirMbti,
            myScore: myScore, theirScore: theirScore, notes: notes);
      case 'their_mbti':
        return Profile(id: id, label: label, stage: stage, goal: goal,
            background: background, myMbti: myMbti, theirMbti: value,
            myScore: myScore, theirScore: theirScore, notes: notes);
      case 'my_score':
        return Profile(id: id, label: label, stage: stage, goal: goal,
            background: background, myMbti: myMbti, theirMbti: theirMbti,
            myScore: value, theirScore: theirScore, notes: notes);
      case 'their_score':
        return Profile(id: id, label: label, stage: stage, goal: goal,
            background: background, myMbti: myMbti, theirMbti: theirMbti,
            myScore: myScore, theirScore: value, notes: notes);
      case 'notes':
        return Profile(id: id, label: label, stage: stage, goal: goal,
            background: background, myMbti: myMbti, theirMbti: theirMbti,
            myScore: myScore, theirScore: theirScore, notes: value);
      default:
        throw DomainException('未知资料字段：$key');
    }
  }

  @override
  String toString() => 'Profile($id, $label)';
}

/// The stage/goal/scene vocabulary parsed from [relationshipEnumsPath].
///
/// Every goal maps to a scene, and the scene is what [SharedMaterial.scene]
/// loads knowledge for. The mapping is therefore checked at parse time: a goal
/// that points at a scene nobody declared is a payload bug, not a runtime guess.
final class RelationshipVocabulary {
  const RelationshipVocabulary({
    required this.stages,
    required this.goals,
    required this.scenes,
    required this.profileFields,
  });

  final List<String> stages;

  /// Goal name → the scene analyses for that goal run against.
  final Map<String, String> goals;

  final List<String> scenes;

  /// The payload's `profile_fields`, in their order, without `label`.
  final List<String> profileFields;

  static RelationshipVocabulary parse(String source) {
    final Map<String, Object?> json = _asMap(jsonDecode(source));
    final List<String> stages = _asStringList(json['stages']);
    final Map<String, String> goals = _asStringMap(json['goals']);
    final List<String> scenes = _asStringList(json['scenes']);
    final List<String> fields = _asStringList(json['profile_fields']);
    for (final String scene in goals.values) {
      if (!scenes.contains(scene)) {
        throw DomainException('关系词表：目标指向了未知的场景 $scene');
      }
    }
    return RelationshipVocabulary(
      stages: stages,
      goals: goals,
      scenes: scenes,
      profileFields: fields,
    );
  }

  /// The scene analyses for [goal] run against.
  ///
  /// Throws when the goal is not in the vocabulary. An unknown goal is a
  /// refusal, not a fall-back: choosing the scene is the one steering the model
  /// gets, and a guess would analyse against knowledge written for a different
  /// goal.
  String sceneFor(String goal) {
    final String? scene = goals[goal];
    if (scene == null) {
      throw const DomainException('请选择有效的本轮目标');
    }
    return scene;
  }
}

/// Validates a profile against the vocabulary, returning it when it holds.
///
/// The rules are the upstream ones, ported line for line: `stage` must be a
/// known stage, `goal` a known goal, every field a string of no more than 200
/// characters, `my_score`/`their_score` — if not empty — a whole number in
/// 0–100, and `label` not blank. The four refusals are four sentences, not one,
/// because they tell the user four different things to fix.
Profile validateProfile(Profile profile, RelationshipVocabulary vocabulary) {
  if (!vocabulary.stages.contains(profile.stage)) {
    throw const DomainException('请选择关系阶段');
  }
  if (!vocabulary.goals.containsKey(profile.goal)) {
    throw const DomainException('请选择有效的本轮目标');
  }
  for (final String field in profileFields) {
    if (profile.value(field).length > 200) {
      throw const DomainException('每项资料最多 200 字；不确定的信息可以留空');
    }
  }
  for (final String key in <String>['my_score', 'their_score']) {
    final String score = profile.value(key).trim();
    if (score.isEmpty) continue;
    final int? n = int.tryParse(score);
    if (n == null || n < 0 || n > 100) {
      throw const DomainException('主观综合评分请填 0–100；不知道可留空');
    }
  }
  if (profile.label.trim().isEmpty) {
    throw const DomainException('请给当前对象填写一个称呼或代号');
  }
  return profile;
}

/// The model-facing fragment for a profile: the non-empty fields, as JSON.
///
/// The id is never sent (it is a port-level handle, not a fact the model should
/// weigh); only the user-facing fields travel, and only when filled. This is
/// [experience.profile_context] lifted verbatim — including the choice of JSON,
/// which the existing suite asserts verb-for-verb.
String profileContext(Profile profile) {
  final Map<String, Object?> fragment = <String, Object?>{};
  for (final String key in profileFields) {
    final String v = profile.value(key);
    if (v.isNotEmpty) fragment[key] = v;
  }
  return jsonEncode(fragment);
}

/// Builds the model-facing background string from everything one analysis gets
/// to see beyond the live lines: the profile fragment, the notes that apply,
/// recent history and the snapshot text itself, in that order.
///
/// Truncated at [cap] — the same constant #7's [maxBackground] names — and the
/// cut is a line break, so the model never receives a half-sentence that began
/// in one fact and ended in another. Notes that are turned off are not injected;
/// `alwaysOn` notes are no different from the rest here, because the caller has
/// already decided which notes apply.
///
/// This is the function Android's `ChatContext.background` did alone, and the
/// one #7's `analyzeSnapshot(background:)` consumes. The three ports each had
/// their own budget for it; one of them — the application-level cap — is the
/// one that ships, and it is the one the domain already names.
String buildBackground({
  required Profile profile,
  Iterable<KnowledgeNote> notes = const <KnowledgeNote>[],
  Iterable<KnowledgeLogEntry> recentLog = const <KnowledgeLogEntry>[],
  String snapshotText = '',
  int cap = maxBackground,
}) {
  final List<String> parts = <String>[];
  final String context = profileContext(profile);
  if (context != '{}') parts.add(context);
  for (final KnowledgeNote note in notes) {
    if (!note.enabled) continue;
    final String body =
        note.title.isEmpty ? note.content : '${note.title}\n${note.content}';
    if (body.isNotEmpty) parts.add(body);
  }
  if (snapshotText.isNotEmpty) parts.add(snapshotText);
  for (final KnowledgeLogEntry line in recentLog) {
    final String who = line.speaker == Speaker.me ? '我:' : '对方:';
    parts.add('$who ${line.text}');
  }
  final String full = parts.join('\n\n');
  if (full.length <= cap) return full;
  final int cut = full.lastIndexOf('\n', cap);
  return full.substring(0, cut > 0 ? cut : cap);
}

Map<String, Object?> _asMap(Object? raw) {
  if (raw is! Map) {
    throw DomainException('关系词表格式不正确：期望一个 JSON 对象，得到 ${raw.runtimeType}');
  }
  return raw.cast<String, Object?>();
}

List<Object?> _asList(Object? raw) {
  if (raw is! List) {
    throw DomainException('关系词表格式不正确：期望一个数组，得到 ${raw.runtimeType}');
  }
  return raw.cast<Object?>();
}

String _asString(Object? raw) {
  if (raw is! String) {
    throw DomainException('关系词表格式不正确：期望一个字符串，得到 ${raw.runtimeType}');
  }
  return raw;
}

List<String> _asStringList(Object? raw) =>
    <String>[for (final Object? item in _asList(raw)) _asString(item)];

Map<String, String> _asStringMap(Object? raw) => <String, String>{
      for (final MapEntry<String, Object?> entry in _asMap(raw).entries)
        entry.key: _asString(entry.value),
    };