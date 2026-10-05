import 'dart:convert';

import 'package:miaotou_domain/miaotou_domain.dart';
import 'package:test/test.dart';

import 'support/fake_transport.dart';
import 'support/repo_payload.dart';

/// One round end to end, re-expressed from the existing suite's pipeline tests.
///
/// These are the assertions that make the ordering a property rather than a
/// hope: local validation before any request, the strategy decided before the
/// draft, a failed strategy never reaching the reply model, and a reply that
/// ignored the pinned strategy thrown away rather than trimmed.
void main() {
  late SharedMaterial material;

  setUpAll(() async {
    material = await loadRealMaterial();
  });

  final Snapshot snapshot = Snapshot(title: 'A', transcript: '对方：忙，下周再看看吧。');

  Map<String, Object?> jevDecision() => <String, Object?>{
        'model': 'jev-1.13.0',
        'answers': <String, Object?>{
          'reply_strategy': <String, Object?>{
            'type': 'choice',
            'choice': '降压',
            'confidence': .85,
            'probabilities': <String, double>{
              for (final String strategy in material.vocabulary.strategies)
                strategy: strategy == '降压' ? 1.0 : 0.0,
            },
          },
        },
      };

  Map<String, Object?> adviceDrafts({
    String strategy = '降压',
    List<Object?>? candidates,
  }) =>
      <String, Object?>{
        'support': '先不用急。',
        'facts': <String>['对方说这周忙'],
        'hypotheses': <String>[],
        'unknowns': <String>[],
        'intent': '可能想暂缓见面',
        'strategy': strategy,
        'recommendation': '先让对方休息。',
        'next_step': '等下周再聊。',
        'stop_condition': '明确拒绝时停止推进。',
        'question': '',
        'candidates': candidates ??
            <Object?>[
              <String, Object?>{'text': '行，你先忙', 'reason': '理由', 'tradeoff': '代价'},
            ],
      };

  String adviceJson({String strategy = '降压'}) =>
      jsonEncode(adviceDrafts(strategy: strategy));

  Map<String, Object?> candidate(String text) => <String, Object?>{
        'text': text,
        'reason': '理由',
        'tradeoff': '代价',
      };

  Future<Advice> analyze(
    FakeTransport transport, {
    String scene = '邀约推进',
    String background = '',
    StrategyRoute? route,
    ReplyPreferences? preferences,
  }) =>
      analyzeSnapshot(
        transport: transport,
        material: material,
        snapshot: snapshot,
        scene: scene,
        background: background,
        replyModel: 'reply-model',
        strategyRoute: route,
        preferences: preferences,
      );

  test('an unknown scene is refused before the first request', () async {
    // A billed call for an input that was never usable is the failure this
    // ordering exists to prevent.
    final FakeTransport transport = FakeTransport();
    await expectLater(
      analyze(transport, scene: '不存在'),
      throwsA(isA<DomainException>().having(
        (DomainException e) => e.message,
        'message',
        contains('分析场景'),
      )),
    );
    expect(transport.chats, isEmpty);
    expect(transport.systemoneCalls, isEmpty);
  });

  test('an oversized background is refused before the first request', () async {
    final FakeTransport transport = FakeTransport();
    await expectLater(
      analyze(transport, background: '字' * (maxBackground + 1)),
      throwsA(isA<DomainException>()),
    );
    expect(transport.chats, isEmpty);
    expect(transport.systemoneCalls, isEmpty);
  });

  test('decides the strategy before drafting, and pins the draft to it', () async {
    final FakeTransport transport = FakeTransport(
      chatAnswers: <Object>[adviceJson()],
      systemoneAnswer: jsonEncode(jevDecision()),
    );

    final Advice result = await analyze(
      transport,
      route: const StrategyRoute(engine: StrategyEngine.jev, model: 'jev-1.13.0'),
    );

    expect(transport.systemoneCalls, hasLength(1));
    expect(transport.chats, hasLength(1));
    // The service's own model string reaches the request payload.
    expect(transport.systemoneCalls.single['model'], 'jev-1.13.0');

    final ReplyPromptFacts facts = ReplyPromptFacts.of(transport.chats.single);
    expect(facts.system, contains('strategy 字段必须为：降压'));
    expect(facts.strategyDecisionStrategy, '降压');
    expect(result.strategyDecision!.model, 'jev-1.13.0');
  });

  test('a strategy failure never reaches the reply model', () async {
    final FakeTransport transport = FakeTransport(
      chatAnswers: <Object>[adviceJson()],
      systemoneAnswer: 'not json at all',
    );

    await expectLater(
      analyze(
        transport,
        route: const StrategyRoute(engine: StrategyEngine.jev, model: 'jev-1.13.0'),
      ),
      throwsA(isA<DomainException>()),
    );
    expect(transport.systemoneCalls, hasLength(1));
    expect(transport.chats, isEmpty, reason: 'drafting a reply to a question '
        'nobody decided is how a confident wrong answer gets made');
  });

  test('a draft that ignored the pinned strategy is thrown away', () async {
    final FakeTransport transport = FakeTransport(
      chatAnswers: <Object>[adviceJson(strategy: '约见')],
      systemoneAnswer: jsonEncode(jevDecision()),
    );

    await expectLater(
      analyze(
        transport,
        route: const StrategyRoute(engine: StrategyEngine.jev, model: 'jev-1.13.0'),
      ),
      throwsA(isA<DomainException>().having(
        (DomainException e) => e.message,
        'message',
        contains('未遵循'),
      )),
    );
  });

  test('with no strategy route the single-model path is unchanged', () async {
    final FakeTransport transport = FakeTransport(chatAnswers: <Object>[adviceJson()]);

    final Advice result = await analyze(transport);

    expect(transport.systemoneCalls, isEmpty);
    expect(transport.chats, hasLength(1));
    expect(result.strategyDecision, isNull);
    final ReplyPromptFacts facts = ReplyPromptFacts.of(transport.chats.single);
    expect(facts.system, isNot(contains('strategy 字段必须为')));
    expect(facts.payload.containsKey('strategy_decision'), isFalse);
  });

  test('the DeepSeek route records the model it was decided with', () async {
    // One line is unattributed, so the route stops at the self-reported
    // decision: a rotation over labels cannot be read as stable when the labels
    // themselves are in doubt. That also makes this a two-call route, which is
    // what pins the wiring — evidence pass, then the draft.
    final Snapshot doubted = Snapshot(
      title: 'A',
      transcript: '对方：忙，下周再看看吧。\n说话人待确认：那好吧',
    );
    final FakeTransport transport = FakeTransport(chatAnswers: <Object>[
      jsonEncode(<String, Object?>{'strategy': '降压', 'confidence': .62}),
      adviceJson(),
    ]);

    final Advice result = await analyzeSnapshot(
      transport: transport,
      material: material,
      snapshot: doubted,
      scene: '邀约推进',
      background: '',
      replyModel: 'reply-model',
      strategyRoute: const StrategyRoute(
        engine: StrategyEngine.deepseek,
        model: 'deepseek-flash',
      ),
    );

    expect(transport.chats, hasLength(2));
    expect(transport.chats.first.route, ChatRoute.strategy);
    expect(transport.chats.last.route, ChatRoute.reply);
    expect(result.strategyDecision!.model, 'deepseek-flash',
        reason: 'the route model is recorded on the decision, not inferred later');
    expect(result.strategy, '降压');
    // A doubted transcript buys the strategy but not the numbers behind it.
    expect(result.strategyDecision!.confidence, isNull);
    expect(result.strategyDecision!.probabilities, isEmpty);
  });

  test('a rewrite replaces the drafts and re-decides nothing', () async {
    final Advice previous = parseAdvice(
      adviceJson(),
      strategies: material.vocabulary.strategies,
    );
    final FakeTransport transport = FakeTransport(chatAnswers: <Object>[
      jsonEncode(<String, Object?>{
        'strategy': '降压',
        'facts': <String>['模型试图换掉事实'],
        'recommendation': '模型试图换掉建议',
        'candidates': <Object?>[
          <String, Object?>{'text': '行，你先忙', 'reason': '更口语', 'tradeoff': '信息少'},
        ],
      }),
    ]);

    final Advice result = await rewriteSnapshot(
      transport: transport,
      material: material,
      snapshot: snapshot,
      scene: '邀约推进',
      background: '',
      previous: previous,
      replyModel: 'reply-model',
    );

    expect(transport.systemoneCalls, isEmpty,
        reason: 'rewriting is a tone pass, not a second decision');
    expect(result.facts, previous.facts);
    expect(result.intent, previous.intent);
    expect(result.recommendation, previous.recommendation);
    expect(result.intentConfidence, previous.intentConfidence);
    expect(result.candidates.single.text, '行，你先忙');
  });

  test('a rewrite that comes back empty is refused so the originals stay', () async {
    final Advice previous = parseAdvice(
      adviceJson(),
      strategies: material.vocabulary.strategies,
    );
    final FakeTransport transport = FakeTransport(chatAnswers: <Object>[
      jsonEncode(<String, Object?>{'candidates': <Object?>[]}),
    ]);

    await expectLater(
      rewriteSnapshot(
        transport: transport,
        material: material,
        snapshot: snapshot,
        scene: '邀约推进',
        background: '',
        previous: previous,
        replyModel: 'reply-model',
      ),
      throwsA(isA<DomainException>()),
      reason: 'an empty rewrite would silently empty the panel; the drafts that '
          'were already on screen are the better outcome',
    );
  });

  test('there is nothing to rewrite when the advice was to stay silent', () async {
    final Advice silent = parseAdvice(
      adviceJson(),
      strategies: material.vocabulary.strategies,
    ).copyWith(candidates: const <Candidate>[]);
    final FakeTransport transport = FakeTransport();

    await expectLater(
      rewriteSnapshot(
        transport: transport,
        material: material,
        snapshot: snapshot,
        scene: '邀约推进',
        background: '',
        previous: silent,
        replyModel: 'reply-model',
      ),
      throwsA(isA<DomainException>()),
    );
    expect(transport.chats, isEmpty,
        reason: 'a refusal that costs nothing must not be a billed call');
  });

  group('the preferences the user chose', () {
    // A function, not a field: a group body runs at collection time, and the
    // payload is only read in setUpAll. The ceiling and the count both come out
    // of the payload, so the boundary tested here is the payload's rather than a
    // number copied into the test.
    ReplyPreferences brief() =>
        material.vocabulary.reply.resolve(tone: '直接', length: '简短');

    test('are enforced by refusal, never by trimming', () async {
      final ReplyPreferences limits = brief();
      final FakeTransport tooLong = FakeTransport(chatAnswers: <Object>[
        jsonEncode(<String, Object?>{
          ...adviceDrafts(),
          'candidates': <Object?>[candidate('字' * (limits.maxChars + 1))],
        }),
      ]);
      await expectLater(
        analyze(tooLong, preferences: limits),
        throwsA(isA<DomainException>()),
        reason: 'a reply trimmed to fit has already been written for a '
            'different contract',
      );

      final FakeTransport tooMany = FakeTransport(chatAnswers: <Object>[
        jsonEncode(<String, Object?>{
          ...adviceDrafts(),
          'candidates': <Object?>[candidate('行'), candidate('也行')],
        }),
      ]);
      final ReplyPreferences oneOnly =
          material.vocabulary.reply.resolve(tone: '直接', length: '简短', count: 1);
      await expectLater(
        analyze(tooMany, preferences: oneOnly),
        throwsA(isA<DomainException>()),
        reason: 'two candidates against a one-candidate round',
      );
    });

    test('accept a reply exactly at the ceiling', () async {
      final ReplyPreferences limits = brief();
      final FakeTransport transport = FakeTransport(chatAnswers: <Object>[
        jsonEncode(<String, Object?>{
          ...adviceDrafts(),
          'candidates': <Object?>[candidate('字' * limits.maxChars)],
        }),
      ]);

      final Advice result = await analyze(transport, preferences: limits);

      expect(result.candidates.single.text.length, limits.maxChars);
    });

    test('are enforced on a rewrite too, so the originals stay', () async {
      final ReplyPreferences limits = brief();
      final Advice previous = parseAdvice(
        adviceJson(),
        strategies: material.vocabulary.strategies,
      );
      final FakeTransport transport = FakeTransport(chatAnswers: <Object>[
        jsonEncode(<String, Object?>{
          'strategy': '降压',
          'candidates': <Object?>[candidate('字' * (limits.maxChars + 1))],
        }),
      ]);

      await expectLater(
        rewriteSnapshot(
          transport: transport,
          material: material,
          snapshot: snapshot,
          scene: '邀约推进',
          background: '',
          previous: previous,
          replyModel: 'reply-model',
          preferences: limits,
        ),
        throwsA(isA<DomainException>()),
      );
    });
  });

  test('the verdict renders without a device', () async {
    final FakeTransport transport = FakeTransport(chatAnswers: <Object>[adviceJson()]);
    final Advice result = await analyze(transport);
    final String rendered = formatAdvice(
      result,
      strategies: material.vocabulary.strategies,
    );

    expect(rendered, contains('首选 · 降压'));
    expect(rendered, contains('对方可能的意图'));
    expect(rendered, contains('判断把握 · 暂无法判断'));
    expect(rendered, contains('候选 1'));
    expect(rendered, contains('行，你先忙'));
  });
}

/// Reads the two things every pipeline assertion looks at, in one place.
final class ReplyPromptFacts {
  ReplyPromptFacts(this.system, this.payload);

  factory ReplyPromptFacts.of(RecordedChat chat) =>
      ReplyPromptFacts(chat.system, chat.payload);

  final String system;
  final Map<String, Object?> payload;

  String? get strategyDecisionStrategy {
    final Object? decision = payload['strategy_decision'];
    return decision is Map
        ? decision.cast<String, Object?>()['strategy'] as String?
        : null;
  }
}
