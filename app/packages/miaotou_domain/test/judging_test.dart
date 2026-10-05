import 'dart:convert';

import 'package:miaotou_domain/miaotou_domain.dart';
import 'package:test/test.dart';

import 'support/fake_transport.dart';
import 'support/repo_payload.dart';

/// The strategy decision, re-expressed from the existing suite.
///
/// Two routes, two temperaments, and both temperaments are load-bearing. The
/// TypeSafe route is strict to the point of paranoia, because the answer arrives
/// as a distribution and a distribution that does not add up is a distribution
/// about something else. The DeepSeek route is forgiving about everything except
/// the strategy itself, and refuses to publish weights it cannot justify.
void main() {
  late SharedMaterial material;
  late List<String> strategies;
  late List<String> labels;
  late List<int> rotations;

  setUpAll(() async {
    material = await loadRealMaterial();
    strategies = material.vocabulary.strategies;
    labels = material.vocabulary.labels;
    rotations = material.vocabulary.rotations;
  });

  Map<String, Object?> decisionResponse() => <String, Object?>{
        'model': 'jev-1.13.0',
        'answers': <String, Object?>{
          'reply_strategy': <String, Object?>{
            'type': 'choice',
            'choice': '降压',
            'confidence': .85,
            'probabilities': <String, double>{
              for (final String strategy in strategies)
                strategy: strategy == '降压' ? 1.0 : 0.0,
            },
          },
        },
      };

  group('the TypeSafe answer', () {
    test('yields the strategy, its confidence and the full distribution', () {
      final StrategyDecision decision = parseJevDecision(
        decisionResponse(),
        strategies: strategies,
        questionNames: material.vocabulary.judge.questions.keys,
      );
      expect(decision.strategy, '降压');
      expect(decision.confidence, .85);
      expect(decision.model, 'jev-1.13.0');
      expect(decision.method, StrategyMethod.jev);
      expect(decision.probabilities, hasLength(strategies.length));
      expect(decision.probabilities['降压'], 1.0);
    });

    test('fails closed on a missing or wrongly shaped answer set', () {
      for (final Object? broken in <Object?>[
        null,
        <Object?>[],
        <String, Object?>{},
        <String, Object?>{'answers': <Object?>[]},
      ]) {
        expect(
          () => parseJevDecision(
            broken,
            strategies: strategies,
            questionNames: material.vocabulary.judge.questions.keys,
          ),
          throwsA(isA<DomainException>()),
          reason: 'accepted $broken',
        );
      }
    });

    test('fails closed on every incomplete or impossible distribution', () {
      for (final Map<String, Object?> change in <Map<String, Object?>>[
        <String, Object?>{'choice': '操控'},
        <String, Object?>{'confidence': double.nan},
        <String, Object?>{'confidence': true},
        <String, Object?>{'probabilities': <String, double>{}},
        <String, Object?>{
          'probabilities': <String, double>{for (final String s in strategies) s: .5},
        },
        <String, Object?>{'type': 'score'},
      ]) {
        final Map<String, Object?> data = decisionResponse();
        final Map<String, Object?> answer = (data['answers']! as Map)
            .cast<String, Object?>()['reply_strategy']! as Map<String, Object?>;
        answer.addAll(change);
        expect(
          () => parseJevDecision(
            data,
            strategies: strategies,
            questionNames: material.vocabulary.judge.questions.keys,
          ),
          throwsA(isA<DomainException>()),
          reason: 'accepted $change',
        );
      }
    });

    test('reads the seven judge answers into typed evidence', () {
      final Map<String, Object?> data = decisionResponse();
      final Map<String, Object?> answers =
          (data['answers']! as Map).cast<String, Object?>();
      answers
        ..['literal_question'] = <String, Object?>{'type': 'noul', 'noul': .7}
        ..['danger_level'] = <String, Object?>{'type': 'score', 'score': 4.0}
        ..['true_intent'] = <String, Object?>{'type': 'choice', 'choice': 'vent_anger'}
        ..['tension_resolved'] = <String, Object?>{'type': 'noul', 'noul': .1};

      final StrategyDecision decision = parseJevDecision(
        data,
        strategies: strategies,
        questionNames: material.vocabulary.judge.questions.keys,
      );
      final Map<String, Object?> judge = decision.judgeEvidence!;
      expect(judge['literal_question'], isTrue);
      expect(judge['danger_level'], 4);
      expect(judge['true_intent'], 'vent_anger');
      expect(judge['tension_resolved'], isFalse);
      // Unanswered questions are absent, never guessed at.
      expect(judge.containsKey('best_action'), isFalse);
      expect(judge.containsKey('she_needs'), isFalse);
    });

    test('drops an unusable judge answer instead of failing the round', () {
      // These answers inform the draft; they do not decide it, so a bad shape
      // must not cost the user the strategy.
      final Map<String, Object?> evidence = judgeEvidence(
        <String, Object?>{
          'literal_question': 'not an object',
          'danger_level': <String, Object?>{'type': 'score', 'score': double.nan},
          'true_intent': <String, Object?>{'type': 'choice', 'choice': ''},
          'she_needs': <String, Object?>{'type': 'choice', 'choice': 'care'},
        },
        questionNames: material.vocabulary.judge.questions.keys,
      );
      expect(evidence.keys, <String>['she_needs']);
    });
  });

  group('the DeepSeek evidence answer', () {
    test('refuses an unknown strategy outright', () {
      expect(
        () => parseDeepSeekDecision(
          jsonEncode(<String, Object?>{'strategy': '操控', 'confidence': .5}),
          model: 'deepseek-flash',
          strategies: strategies,
        ),
        throwsA(isA<DomainException>()),
      );
    });

    test('turns an unusable confidence into null instead of refusing the round',
        () {
      for (final Object? confidence in <Object?>[2, true, '不确定']) {
        final StrategyDecision decision = parseDeepSeekDecision(
          jsonEncode(<String, Object?>{'strategy': '降压', 'confidence': confidence}),
          model: 'deepseek-flash',
          strategies: strategies,
        );
        expect(decision.confidence, isNull, reason: 'for $confidence');
        expect(decision.method, StrategyMethod.deepseekSelfReport);
        expect(decision.probabilities, isEmpty);
      }
    });

    test('an odd evidence shape does not block a valid strategy', () {
      final StrategyDecision decision = parseDeepSeekDecision(
        jsonEncode(<String, Object?>{
          'strategy': '降压',
          'confidence': '0.62',
          'facts': <Object?>[
            <String, Object?>{'text': '对方说忙'},
            '下周未定',
            <String, Object?>{'text': '对方说忙'},
            '下周未定',
            <String, Object?>{'text': '对方说忙'},
            '下周未定',
            <String, Object?>{'text': '对方说忙'},
            '下周未定',
          ],
          'unknowns': '此前是否有过约定',
          'boundary': '不确定',
        }),
        model: 'deepseek-flash',
        strategies: strategies,
      );
      expect(decision.confidence, .62);
      expect(decision.evidence['unknowns'], <String>['此前是否有过约定']);
      expect(decision.evidence['facts'], hasLength(5));
      expect(decision.evidence['boundary'], 'uncertain');
    });
  });

  group('the DeepSeek route', () {
    test('retries once, then keeps the evidence-backed decision', () async {
      final FakeTransport transport = FakeTransport(chatAnswers: <Object>[
        '{bad-json',
        jsonEncode(<String, Object?>{
          'strategy': '降压',
          'confidence': null,
          'facts': <String>['对方说忙'],
        }),
        const ChatCompletion('A'), // no logprobs -> the weights are unusable
      ]);
      final StrategyDecision decision = await decideDeepSeek(
        transport: transport,
        vocabulary: material.vocabulary,
        material: await material.scene('邀约推进'),
        snapshot: Snapshot(title: '对象 A', transcript: '对方：这周忙'),
        scene: '邀约推进',
        background: '',
        model: 'deepseek-flash',
      );
      expect(transport.chats, hasLength(3));
      expect(decision.strategy, '降压');
      expect(decision.confidence, isNull);
      expect(decision.method, StrategyMethod.deepseekSelfReport);
    });

    test('gives up after two malformed answers', () async {
      final FakeTransport transport = FakeTransport(chatAnswers: <Object>[
        'not json at all',
        jsonEncode(<String, Object?>{'strategy': '操控'}),
      ]);
      await expectLater(
        decideDeepSeek(
          transport: transport,
          vocabulary: material.vocabulary,
          material: await material.scene('邀约推进'),
          snapshot: Snapshot(title: '对象 A', transcript: '对方：这周忙'),
          scene: '邀约推进',
          background: '',
          model: 'deepseek-flash',
        ),
        throwsA(isA<DomainException>().having(
          (DomainException e) => e.message,
          'message',
          contains('连续两次'),
        )),
      );
    });

    test('publishes no weights when a line is unattributed', () async {
      final FakeTransport transport = FakeTransport(chatAnswers: <Object>[
        jsonEncode(<String, Object?>{'strategy': '澄清', 'confidence': .8}),
      ]);
      final StrategyDecision decision = await decideDeepSeek(
        transport: transport,
        vocabulary: material.vocabulary,
        material: await material.scene('日常回复'),
        snapshot: Snapshot(title: '对象 A', transcript: '说话人待确认：你好 [OCR待核对]'),
        scene: '日常回复',
        background: '',
        model: 'deepseek-flash',
      );
      expect(transport.chats, hasLength(1));
      expect(decision.confidence, isNull);
      expect(decision.probabilities, isEmpty);
    });

    test('publishes a distribution only when three rotations agree', () async {
      final FakeTransport transport = FakeTransport(chatAnswers: <Object>[
        jsonEncode(<String, Object?>{
          'facts': <String>['对方说这周忙'],
          'unknowns': <String>['下周是否有空'],
          'boundary': 'none',
          'strategy': '降压',
          'confidence': .62,
        }),
        ...rotationAnswers(
          winner: '降压',
          strategies: strategies,
          rotations: rotations,
          labels: labels,
        ),
      ]);
      final StrategyDecision decision = await decideDeepSeek(
        transport: transport,
        vocabulary: material.vocabulary,
        material: await material.scene('邀约推进'),
        snapshot: Snapshot(title: '对象 A', transcript: '对方：这周忙，下周再说'),
        scene: '邀约推进',
        background: '',
        model: 'deepseek-flash',
      );

      expect(transport.chats, hasLength(1 + rotations.length));
      expect(decision.strategy, '降压');
      expect(decision.method, StrategyMethod.deepseekLogprobs);
      expect(
        decision.probabilities.values.reduce((double a, double b) => a + b),
        closeTo(1, 1e-9),
      );

      // The evidence pass carries the scene's guide and the transcript.
      expect(transport.chats.first.payload['strategy_guide'], isNotEmpty);
      expect(transport.chats.first.payload['transcript'], contains('这周忙'));
      // Only the rotations ask for token weights.
      expect(
        transport.chats.skip(1).every((RecordedChat chat) =>
            chat.request.choiceLogprobs && chat.route == ChatRoute.strategy),
        isTrue,
      );
    });

    test('reads the Chinese criteria on this route, not the English ones', () async {
      final FakeTransport transport = FakeTransport(chatAnswers: <Object>[
        jsonEncode(<String, Object?>{'strategy': '降压', 'confidence': .62}),
        ...rotationAnswers(
          winner: '降压',
          strategies: strategies,
          rotations: rotations,
          labels: labels,
        ),
      ]);
      await decideDeepSeek(
        transport: transport,
        vocabulary: material.vocabulary,
        material: await material.scene('邀约推进'),
        snapshot: Snapshot(title: '对象 A', transcript: '对方：这周忙'),
        scene: '邀约推进',
        background: '',
        model: 'deepseek-flash',
      );

      final String evidenceSystem = transport.chats.first.system;
      expect(evidenceSystem, contains(material.vocabulary.deepseekCriteria['降压']!));
      expect(
        evidenceSystem,
        isNot(contains(material.vocabulary.typesafeCriteria['降压']!)),
        reason: 'the English map is the TypeSafe service\'s; this route is not it',
      );
      expect(
        transport.chats[1].system,
        contains(material.vocabulary.deepseekCriteria['降压']!),
      );
    });

    test('keeps the decision when a rotation\'s weights are missing', () async {
      final FakeTransport transport = FakeTransport(chatAnswers: <Object>[
        jsonEncode(<String, Object?>{
          'facts': <String>['对方说忙'],
          'strategy': '降压',
          'confidence': .62,
        }),
        choice('A', <(String, double)>[('A', -.2)]),
      ]);
      final StrategyDecision decision = await decideDeepSeek(
        transport: transport,
        vocabulary: material.vocabulary,
        material: await material.scene('邀约推进'),
        snapshot: Snapshot(title: '对象 A', transcript: '对方：这周忙'),
        scene: '邀约推进',
        background: '',
        model: 'deepseek-flash',
      );
      expect(transport.chats, hasLength(2));
      expect(decision.method, StrategyMethod.deepseekSelfReport);
      expect(decision.probabilities, isEmpty);
      expect(decision.confidence, .62);
    });

    test('discards a distribution whose rotations disagree', () async {
      final List<Object> scripted = <Object>[
        jsonEncode(<String, Object?>{
          'facts': <String>['对方说忙'],
          'strategy': '降压',
          'confidence': .62,
        }),
      ];
      int index = 0;
      for (final int offset in rotations) {
        index += 1;
        final String preferred = index < rotations.length ? '降压' : '轻推';
        final Map<String, String> mapping = <String, String>{
          for (int i = 0; i < labels.length; i++)
            labels[i]: strategies[(i + offset) % strategies.length],
        };
        final String selected = mapping.entries
            .firstWhere((MapEntry<String, String> entry) => entry.value == preferred)
            .key;
        scripted.add(choice(
          selected,
          <(String, double)>[
            for (final String label in labels) (label, label == selected ? -.1 : -4),
          ],
        ));
      }

      final FakeTransport transport = FakeTransport(chatAnswers: scripted);
      final StrategyDecision decision = await decideDeepSeek(
        transport: transport,
        vocabulary: material.vocabulary,
        material: await material.scene('邀约推进'),
        snapshot: Snapshot(title: '对象 A', transcript: '对方：这周忙'),
        scene: '邀约推进',
        background: '',
        model: 'deepseek-flash',
      );
      expect(transport.chats, hasLength(1 + rotations.length));
      expect(decision.method, StrategyMethod.deepseekSelfReport);
      expect(decision.probabilities, isEmpty);
    });
  });

  group('the rotated choice answer', () {
    Map<String, String> mapping(List<String> values) => <String, String>{
          for (int i = 0; i < labels.length; i++) labels[i]: values[i],
        };

    test('requires the emitted token to be the first one', () {
      final Map<String, String> labels0 = mapping(strategies);
      expect(
        () => parseChoice(
          content: 'A',
          firstToken: ' ',
          top: <TopLogprob>[
            for (int i = 0; i < labels.length; i++) TopLogprob(labels[i], -i.toDouble()),
          ],
          labels: labels0,
        ),
        throwsA(isA<DomainException>().having(
          (DomainException e) => e.message,
          'message',
          contains('权重不可用'),
        )),
      );
    });

    test('requires all seven labels to be present', () {
      final Map<String, String> labels0 = mapping(strategies);
      expect(
        () => parseChoice(
          content: 'A',
          firstToken: 'A',
          top: <TopLogprob>[
            for (int i = 0; i < labels.length - 1; i++)
              TopLogprob(labels[i], -i.toDouble()),
          ],
          labels: labels0,
        ),
        throwsA(isA<DomainException>()),
      );
    });

    test('normalises the seven alternatives to a distribution', () {
      final Map<String, double> distribution = parseChoice(
        content: 'A',
        firstToken: 'A',
        top: <TopLogprob>[
          for (int i = 0; i < labels.length; i++) TopLogprob(labels[i], -i.toDouble()),
        ],
        labels: mapping(strategies),
      );
      expect(distribution.values.reduce((double a, double b) => a + b), closeTo(1, 1e-9));
      expect(distribution, hasLength(strategies.length));
    });
  });
}
