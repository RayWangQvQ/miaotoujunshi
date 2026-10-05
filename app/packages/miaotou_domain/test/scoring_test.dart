import 'dart:convert';

import 'package:miaotou_domain/miaotou_domain.dart';
import 'package:test/test.dart';

import 'support/fake_transport.dart';
import 'support/repo_payload.dart';

/// Candidate scoring, re-expressed from the existing suite.
///
/// The feature has one promise and three failure modes, and the promise is not
/// "the candidates get numbers". It is that **the drafts survive**. A scoring
/// that failed leaves the drafts in generation order and says so; it never
/// invents weights, never drops a candidate and never swaps provider to get an
/// answer.
void main() {
  Candidate candidate(String text, {String reason = '理由', String tradeoff = '代价'}) =>
      Candidate(text: text, reason: reason, tradeoff: tradeoff);

  List<Candidate> drafts() => <Candidate>[
        candidate('好，明天下午'),
        candidate('行，那改天再聊', reason: '第二条理由'),
      ];

  Advice adviceWith(List<Candidate> candidates) => Advice(
        support: '先不用急。',
        facts: const <String>['对方说这周忙'],
        hypotheses: const <String>[],
        unknowns: const <String>[],
        intent: '可能想暂缓见面',
        intentConfidence: null,
        strategy: '降压',
        recommendation: '先让对方休息。',
        nextStep: '等下周再聊。',
        stopCondition: '明确拒绝时停止推进。',
        question: '',
        candidates: candidates,
      );

  Future<Advice> rank(
    FakeTransport transport,
    List<Candidate> candidates, {
    ReplyPreferences? preferences,
  }) =>
      rankCandidates(
        transport: transport,
        model: 'reply-model',
        snapshot: Snapshot(title: 'A', transcript: '我：周六见吗\n对方：这周忙'),
        scene: '日常回复',
        background: '',
        advice: adviceWith(candidates),
        preferences: preferences,
      );

  group('reading the scores', () {
    test('reorders whole candidates and makes the weights sum to 100', () {
      final List<Candidate> original = drafts();
      final List<Candidate> rows = applyScores(
        original,
        jsonEncode(<String, Object?>{
          'scores': <Object?>[
            <String, Object?>{'id': 1, 'score': 80},
            <String, Object?>{'id': 0, 'score': 20},
          ],
        }),
      );
      expect(rows.map((Candidate c) => c.weight), <int>[80, 20]);
      expect(rows.first.text, original[1].text);
      expect(rows.first.reason, original[1].reason);
      // The input is untouched: a weight is added, never written back.
      expect(original[0].weight, isNull);
    });

    test('spreads the rounding remainder instead of losing it', () {
      final List<Candidate> three = <Candidate>[
        ...drafts(),
        candidate('第三条'),
      ];
      final List<Candidate> rows = applyScores(
        three,
        jsonEncode(<String, Object?>{
          'scores': <Object?>[
            for (int i = 0; i < 3; i++) <String, Object?>{'id': i, 'score': 1},
          ],
        }),
      );
      expect(rows.map((Candidate c) => c.weight), <int>[34, 33, 33]);
      expect(
        rows.map((Candidate c) => c.weight!).reduce((int a, int b) => a + b),
        100,
      );
    });

    test('refuses a bad identity, a non-finite value or a non-number', () {
      /// A two-candidate answer whose first score is a raw JSON literal.
      ///
      /// `jsonEncode` cannot write a non-finite double, so these have to be
      /// spliced in textually. They are worth the trouble: `NaN` compares false
      /// against every bound, so a check written as a chain of `<`/`>` would let
      /// it through and poison the total.
      String scoresWithRawNumber(String literal) => jsonEncode(<String, Object?>{
            'scores': <Object?>[
              <String, Object?>{'id': 0, 'score': 0},
              <String, Object?>{'id': 1, 'score': 10},
            ],
          }).replaceFirst('"id":0,"score":0', '"id":0,"score":$literal');

      final List<String> invalid = <String>[
        '{}',
        '[]',
        'not json',
        jsonEncode(<String, Object?>{
          'scores': <Object?>[
            <String, Object?>{'id': 0, 'score': 1},
            <String, Object?>{'id': 0, 'score': 1},
          ],
        }),
        jsonEncode(<String, Object?>{
          'scores': <Object?>[
            <String, Object?>{'id': 0, 'score': 1},
            <String, Object?>{'id': 2, 'score': 5},
          ],
        }),
        jsonEncode(<String, Object?>{
          'scores': <Object?>[
            for (int i = 0; i < 2; i++) <String, Object?>{'id': i, 'score': 0},
          ],
        }),
      ];
      for (final Object? value in <Object?>[true, -1, 101, '80']) {
        invalid.add(jsonEncode(<String, Object?>{
          'scores': <Object?>[
            <String, Object?>{'id': 0, 'score': value},
            <String, Object?>{'id': 1, 'score': 10},
          ],
        }));
      }
      for (final String literal in <String>['NaN', 'Infinity', '-Infinity']) {
        invalid.add(scoresWithRawNumber(literal));
      }
      for (final String raw in invalid) {
        expect(
          () => applyScores(drafts(), raw),
          throwsA(isA<DomainException>()),
          reason: 'accepted $raw',
        );
      }
    });
  });

  group('keeping the drafts', () {
    test('a failed scoring leaves them, with no invented weights', () async {
      for (final Object scripted in <Object>[
        'bad json',
        const DomainException('provider failed'),
      ]) {
        final FakeTransport transport = FakeTransport(chatAnswers: <Object>[scripted]);
        final Advice result = await rank(transport, drafts());
        expect(result.rankingStatus, RankingStatus.unavailable);
        expect(result.candidates, hasLength(2));
        expect(
          result.candidates.every((Candidate c) => c.weight == null),
          isTrue,
          reason: 'for $scripted',
        );
        expect(transport.chats, hasLength(1));
      }
    });

    test('zero and one candidate need no request at all', () async {
      final FakeTransport none = FakeTransport();
      final Advice notNeeded = await rank(none, <Candidate>[]);
      expect(notNeeded.rankingStatus, RankingStatus.notNeeded);
      expect(none.chats, isEmpty);

      final FakeTransport single = FakeTransport();
      final Advice one = await rank(single, <Candidate>[candidate('好')]);
      expect(one.rankingStatus, RankingStatus.single);
      expect(one.candidates.single.weight, 100);
      expect(single.chats, isEmpty);
    });
  });

  group('the round trip', () {
    test('generates, then ranks on the same route with the conversation in '
        'context', () async {
      final SharedMaterial material = await loadRealMaterial();
      final Snapshot snapshot = Snapshot(title: 'A', transcript: '我：周六见吗\n对方：这周忙');
      final Map<String, Object?> generated = <String, Object?>{
        'support': '先不用急。',
        'facts': <String>['对方说这周忙'],
        'hypotheses': <String>[],
        'unknowns': <String>[],
        'intent': '可能想暂缓安排',
        'strategy': '降压',
        'recommendation': '先让对方休息。',
        'next_step': '等下周再聊。',
        'stop_condition': '明确拒绝时停止推进。',
        'question': '',
        'candidates': <Object?>[
          <String, Object?>{
            'text': '好，明天下午',
            'reason': '呼应原话',
            'tradeoff': '略显急',
          },
          <String, Object?>{
            'text': '行，那改天再聊',
            'reason': '第二条理由',
            'tradeoff': '更保守',
          },
        ],
      };
      final FakeTransport transport = FakeTransport(chatAnswers: <Object>[
        jsonEncode(generated),
        jsonEncode(<String, Object?>{
          'scores': <Object?>[
            <String, Object?>{'id': 0, 'score': 20},
            <String, Object?>{'id': 1, 'score': 80},
          ],
        }),
      ]);

      final Advice result = await analyzeSnapshot(
        transport: transport,
        material: material,
        snapshot: snapshot,
        scene: '日常回复',
        background: '当前对象专属背景',
        replyModel: 'reply-model',
      );

      expect(transport.chats, hasLength(2));
      expect(
        transport.chats.map((RecordedChat chat) => chat.route),
        everyElement(ChatRoute.reply),
      );

      final Map<String, Object?> scoring = transport.chats[1].payload;
      expect(scoring['visible_transcript'], snapshot.transcript);
      expect(scoring['scene'], '日常回复');
      expect(scoring['user_background'], '当前对象专属背景');
      expect(scoring['strategy'], '降压');
      expect(
        (scoring['candidates']! as List).first,
        <String, Object?>{'id': 0, 'text': '好，明天下午'},
        reason: 'the scorer sees the text only, never the reasons it might be '
            'biased by',
      );

      expect(result.rankingStatus, RankingStatus.ranked);
      expect(result.candidates.first.text, '行，那改天再聊');
      expect(result.candidates.first.weight, 80);
    });
  });
}
