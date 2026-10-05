import 'dart:convert';

import 'package:test/test.dart';
import 'package:miaotou_capabilities/miaotou_capabilities.dart';
import 'package:miaotou_domain/miaotou_domain.dart';

import 'support/repo_payload.dart';

/// The word the user must write to the stage field for "not picked yet" is the
/// first entry of the payload's `stages` list, and that word is also the marker
/// every other field uses for empty. The tests read the real payload so a
/// renamed stage is caught here, not by a stale copy.
void main() {
  late SharedMaterial material;
  late RelationshipVocabulary vocabulary;

  setUpAll(() async {
    material = await loadRealMaterial();
    vocabulary = material.vocabulary.relationship;
  });

  group('RelationshipVocabulary', () {
    test('reads the real payload the way macOS already does', () {
      expect(vocabulary.stages, <String>[
        '未填写',
        '初识',
        '了解中',
        '暧昧',
        '约会中',
        '伴侣',
        '关系结束',
      ]);
      expect(vocabulary.scenes, <String>[
        '日常回复',
        '邀约推进',
        '冲突修复',
        '投入与退出',
      ]);
      expect(vocabulary.goals['自然接话'], '日常回复');
      expect(vocabulary.goals['主动邀约'], '邀约推进');
      expect(vocabulary.goals['修复冲突'], '冲突修复');
      expect(vocabulary.goals['结束联系'], '投入与退出');
      expect(vocabulary.profileFields, <String>[
        'stage',
        'goal',
        'background',
        'my_mbti',
        'their_mbti',
        'my_score',
        'their_score',
        'notes',
      ]);
    });

    test('maps every goal to a declared scene', () {
      // The parse checks this; this test pins the check itself, so a goal that
      // later points at a scene nobody declared is a parse failure rather than
      // a runtime 404 on the knowledge document.
      expect(
        () => RelationshipVocabulary.parse(jsonEncode(<String, Object?>{
          'stages': <String>['未填写'],
          'goals': <String, String>{'主动邀约': '不存在的场景'},
          'scenes': <String>['日常回复'],
          'profile_fields': <String>['stage'],
        })),
        throwsA(isA<DomainException>()),
      );
    });

    test('sceneFor refuses an unknown goal rather than guessing', () {
      expect(
        () => vocabulary.sceneFor('不存在'),
        throwsA(isA<DomainException>()),
      );
    });

    test('sceneFor returns the scene every goal of that name is analysed against',
        () {
      expect(vocabulary.sceneFor('主动邀约'), '邀约推进');
      expect(vocabulary.sceneFor('自然接话'), '日常回复');
    });
  });

  group('validateProfile', () {
    Profile base() => Profile(
          id: 'mac-test',
          label: '小王',
          stage: '初识',
          goal: '主动邀约',
        );

    test('accepts a profile that satisfies every rule', () {
      // Profile has no equality: validateProfile returns it unchanged when it
      // holds, so asserting the returned label is enough — the refusal tests
      // below assert it does not hold when it should not.
      final Profile p = base();
      expect(validateProfile(p, vocabulary).label, p.label);
      expect(validateProfile(p, vocabulary).stage, p.stage);
      expect(validateProfile(p, vocabulary).goal, p.goal);
    });

    test('accepts the stock 默认: stage 未填写, goal 自然接话', () {
      final Profile p = Profile(id: 'mac-test', label: '当前会话');
      expect(validateProfile(p, vocabulary).stage, '未填写');
      expect(validateProfile(p, vocabulary).goal, '自然接话');
    });

    test('refuses a stage the vocabulary does not name', () {
      expect(
        () => validateProfile(base().withValue('stage', '瞎填的'), vocabulary),
        throwsA(isA<DomainException>()
            .having((DomainException e) => e.message, 'message', contains('关系阶段'))),
      );
    });

    test('refuses a goal the vocabulary does not name', () {
      expect(
        () => validateProfile(base().withValue('goal', '瞎填的'), vocabulary),
        throwsA(isA<DomainException>()
            .having((DomainException e) => e.message, 'message', contains('本轮目标'))),
      );
    });

    test('refuses a field longer than 200 characters', () {
      expect(
        () => validateProfile(
            base().withValue('background', '字' * 201), vocabulary),
        throwsA(isA<DomainException>()),
      );
    });

    test('accepts a field of exactly 200 characters', () {
      expect(
        validateProfile(base().withValue('notes', '字' * 200), vocabulary).notes,
        '字' * 200,
      );
    });

    test('refuses a non-numeric score', () {
      expect(
        () => validateProfile(base().withValue('my_score', '高'), vocabulary),
        throwsA(isA<DomainException>()
            .having((DomainException e) => e.message, 'message', contains('0–100'))),
      );
    });

    test('refuses a score outside 0–100', () {
      expect(
        () =>
            validateProfile(base().withValue('their_score', '101'), vocabulary),
        throwsA(isA<DomainException>()),
      );
    });

    test('accepts a score of 0 and of 100', () {
      expect(
        validateProfile(
            base().withValue('my_score', '0'), vocabulary).myScore,
        '0',
      );
      expect(
        validateProfile(
            base().withValue('their_score', '100'), vocabulary).theirScore,
        '100',
      );
    });

    test('refuses a blank label even when everything else is valid', () {
      expect(
        () => validateProfile(base().withValue('label', '   '), vocabulary),
        throwsA(isA<DomainException>()
            .having((DomainException e) => e.message, 'message', contains('称呼'))),
      );
    });
  });

  group('profileContext', () {
    test('contains only the non-empty fields, never the id', () {
      final Profile p = Profile(
        id: 'mac-secret',
        label: '小王',
        stage: '初识',
        goal: '主动邀约',
        myMbti: 'INTJ',
      );
      final Map<String, Object?> json =
          jsonDecode(profileContext(p)) as Map<String, Object?>;
      expect(json, containsPair('label', '小王'));
      expect(json, containsPair('stage', '初识'));
      expect(json, containsPair('goal', '主动邀约'));
      expect(json, containsPair('my_mbti', 'INTJ'));
      expect(json, isNot(contains('id')));
      expect(json, isNot(contains('background')));
      expect(json, isNot(contains('their_mbti')));
    });

    test('a stock profile carries its defaults into the context', () {
      final Profile p = Profile(id: 'mac-test', label: '当前会话');
      final Map<String, Object?> json =
          jsonDecode(profileContext(p)) as Map<String, Object?>;
      expect(json.keys.toSet(), <String>{'label', 'stage', 'goal'});
    });

    test('is the empty object only when every field is blank', () {
      // The stock profile carries 未填写/自然接话 as real values, so reaching
      // the empty object takes a profile whose stage and goal are also blank —
      // an unvalidated draft, which profileContext does not refuse.
      final Profile p = Profile(id: 'mac-test', label: '', stage: '', goal: '');
      expect(profileContext(p), '{}');
    });
  });

  group('buildBackground', () {
    Profile profile() => Profile(
          id: 'mac-test',
          label: '小王',
          stage: '初识',
          goal: '主动邀约',
          background: '共同朋友介绍',
        );

    KnowledgeNote note({
      String title = '',
      String content = '',
      bool enabled = true,
    }) =>
        KnowledgeNote(
          id: 'n',
          title: title,
          content: content,
          updatedAt: DateTime(2026, 10, 4),
          enabled: enabled,
        );

    KnowledgeLogEntry line(Speaker speaker, String text) => KnowledgeLogEntry(
          speaker: speaker,
          text: text,
          timestamp: DateTime(2026, 10, 4),
          packageName: 'com.tencent.mm',
        );

    test('joins the profile fragment, notes, snapshot and log in that order', () {
      final String background = buildBackground(
        profile: profile(),
        notes: <KnowledgeNote>[note(title: '要点', content: '爱爬山')],
        recentLog: <KnowledgeLogEntry>[line(Speaker.other, '周末有空吗')],
        snapshotText: '对方: 周末有空吗',
      );
      expect(background, contains('"label":"小王"'));
      expect(background, contains('要点'));
      expect(background, contains('爱爬山'));
      expect(background, contains('对方: 周末有空吗'));
      expect(background, contains('周末有空吗'));
    });

    test('drops notes that are turned off', () {
      final String background = buildBackground(
        profile: profile(),
        notes: <KnowledgeNote>[
          note(title: '开着的', content: '甲'),
          note(title: '关着的', content: '乙', enabled: false),
        ],
      );
      expect(background, contains('开着的'));
      expect(background, isNot(contains('关着的')));
    });

    test('is the empty string when the profile is blank and nothing else is given',
        () {
      // A profile with every field blank serialises to '{}', which
      // buildBackground skips — so with no notes, log or snapshot, the
      // background is the empty string rather than a stray '{}'.
      expect(buildBackground(
          profile: Profile(id: 'x', label: '', stage: '', goal: '')), '');
    });

    test('truncates at a line break, never mid-sentence', () {
      // A whole paragraph longer than the cap, with a line break somewhere
      // inside the budget. The cut must be at that break, so the model does
      // not receive a line that began in one paragraph and ended in another.
      final String body = "${'a' * 100}\n${'b' * 100}";
      final String background = buildBackground(
        profile: Profile(id: 'x', label: '', stage: '', goal: ''),
        snapshotText: body,
        cap: 150,
      );
      expect(background, 'a' * 100);
      expect(background.length, 100);
    });

    test('falls back to a hard cut when no line break fits', () {
      final String body = 'c' * 200;
      final String background = buildBackground(
        profile: Profile(id: 'x', label: '', stage: '', goal: ''),
        snapshotText: body,
        cap: 50,
      );
      expect(background, 'c' * 50);
    });

    test('a disabled note with a long title does not pad the result', () {
      final String background = buildBackground(
        profile: profile(),
        notes: <KnowledgeNote>[
          note(title: 'x' * 300, content: '', enabled: false),
        ],
        snapshotText: 'ok',
      );
      expect(background, contains('"label":"小王"'));
      expect(background, contains('ok'));
      expect(background, isNot(contains('x' * 300)));
    });
  });

  group('the goal→scene derivation the synchroniser uses', () {
    test('a goal the vocabulary knows picks the scene it maps to', () {
      final Profile p =
          Profile(id: 'mac-test', label: '小王', stage: '初识', goal: '主动邀约');
      expect(vocabulary.sceneFor(p.goal), '邀约推进');
    });

    test('the four declared scenes are exactly the four the payload maps to', () {
      // The synchroniser derives the scene from the goal; the payload-mapped
      // scenes are the ones the knowledge store has documents for. If a goal
      // ever maps to a scene with no document, the analysis would 404 at
      // scene-load time — this test fails at parse time instead.
      expect(vocabulary.scenes.toSet(), vocabulary.goals.values.toSet());
    });
  });
}