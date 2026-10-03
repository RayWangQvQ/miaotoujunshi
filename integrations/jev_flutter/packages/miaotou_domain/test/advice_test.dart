import 'dart:convert';

import 'package:miaotou_domain/miaotou_domain.dart';
import 'package:test/test.dart';

import 'support/repo_payload.dart';

/// The reply contract, re-expressed from the existing suite.
///
/// Every rule here is one the ports agreed with the model and then had to
/// enforce, because the model does not always keep it. The intent must be hedged
/// and short; a self-assessed confidence may not be claimed without a visible
/// fact; a candidate must be a sendable sentence. Refusing is the point — a
/// partial result the panel could render is a worse outcome than an error.
void main() {
  late List<String> strategies;

  setUpAll(() async {
    strategies = (await loadRealMaterial()).vocabulary.strategies;
  });

  Map<String, Object?> drafts() => <String, Object?>{
        'support': '先不用急。',
        'facts': <String>['对方说这周忙'],
        'hypotheses': <String>['可能真的忙'],
        'unknowns': <String>['下周是否有空'],
        'intent': '可能想暂缓见面',
        'strategy': '降压',
        'recommendation': '先让对方休息。',
        'next_step': '等下周再聊。',
        'stop_condition': '明确拒绝时停止推进。',
        'question': '',
        'candidates': <Object?>[
          <String, Object?>{
            'text': '行，那你先忙',
            'reason': '降压力度合适',
            'tradeoff': '推进慢一点',
          },
        ],
      };

  String encode(Map<String, Object?> data) => jsonEncode(data);

  /// An answer whose [key] is spliced in as a raw JSON literal.
  ///
  /// `jsonEncode` refuses to write a non-finite double, so `NaN` and `Infinity`
  /// cannot be built the usual way. They are still worth testing: they are the
  /// values whose arithmetic propagates silently, and the old suite asserted
  /// them. Splicing the literal keeps the rest of the answer honest.
  String encodeRaw(String key, String literal) =>
      encode(<String, Object?>{...drafts(), key: null})
          .replaceFirst('"$key":null', '"$key":$literal');

  group('the intent field', () {
    test('is refused when it is empty, mis-typed or too long', () {
      for (final Object? value in <Object?>[<Object?>[], '', '字' * 81]) {
        expect(
          () => parseAdvice(
            encode(<String, Object?>{...drafts(), 'intent': value}),
            strategies: strategies,
          ),
          throwsA(isA<DomainException>()),
          reason: 'accepted $value',
        );
      }
    });

    test('is optional, because "cannot tell" is a legitimate answer', () {
      final Map<String, Object?> data = drafts()..remove('intent');
      final Advice advice = parseAdvice(encode(data), strategies: strategies);
      expect(advice.intent, isNull);
      expect(advice.facts, <String>['对方说这周忙']);
    });
  });

  group('the intent confidence', () {
    test('is bounded and refuses a boolean or a formatted string', () {
      for (final Object? value in <Object?>[true, false, -.1, 1.01, '62%']) {
        expect(
          () => parseAdvice(
            encode(<String, Object?>{...drafts(), 'intent_confidence': value}),
            strategies: strategies,
          ),
          throwsA(isA<DomainException>()),
          reason: 'accepted $value',
        );
      }
    });

    test('refuses a non-finite number', () {
      // Strict JSON cannot carry these at all, which is itself a refusal: the
      // answer is not a confidence, so it must not become one.
      for (final String literal in <String>['NaN', 'Infinity', '-Infinity']) {
        expect(
          () => parseAdvice(
            encodeRaw('intent_confidence', literal),
            strategies: strategies,
          ),
          throwsA(isA<DomainException>()),
          reason: 'accepted $literal',
        );
      }
    });

    test('cannot be claimed without an intent and a visible fact', () {
      expect(
        () => parseAdvice(
          encode(<String, Object?>{...drafts(), 'intent': '', 'intent_confidence': .62}),
          strategies: strategies,
        ),
        throwsA(isA<DomainException>()),
      );
      expect(
        () => parseAdvice(
          encode(<String, Object?>{...drafts(), 'facts': <String>[], 'intent_confidence': .62}),
          strategies: strategies,
        ),
        throwsA(isA<DomainException>()),
      );
    });

    test('keeps 0, a fraction, 1 and null exactly as given', () {
      for (final Object? value in <Object?>[0, .62, 1, null]) {
        final Advice advice = parseAdvice(
          encode(<String, Object?>{...drafts(), 'intent_confidence': value}),
          strategies: strategies,
        );
        expect(advice.intentConfidence, value, reason: 'for $value');
      }
    });

    test('is never rendered as a percentage when it is unknown', () {
      expect(intentConfidenceLabel(null), contains('暂无法判断'));
      expect(intentConfidenceLabel(.62), contains('62%'));
      expect(intentConfidenceLabel(0), contains('0%'));
    });
  });

  group('candidates', () {
    test('are refused beyond three, or without a sendable text', () {
      final Map<String, Object?> one = <String, Object?>{
        'text': '行',
        'reason': '理由',
        'tradeoff': '代价',
      };
      expect(
        () => validateCandidates(<Object?>[one, one, one, one]),
        throwsA(isA<DomainException>()),
      );
      expect(() => validateCandidates('not a list'), throwsA(isA<DomainException>()));
      expect(() => validateCandidates(<Object?>['text only']), throwsA(isA<DomainException>()));
      expect(
        () => validateCandidates(<Object?>[
          <String, Object?>{'text': '', 'reason': '理由', 'tradeoff': '代价'},
        ]),
        throwsA(isA<DomainException>()),
      );
      expect(
        () => validateCandidates(<Object?>[
          <String, Object?>{'text': '字' * 101, 'reason': '理由', 'tradeoff': '代价'},
        ]),
        throwsA(isA<DomainException>()),
      );
    });
  });

  group('a rewrite', () {
    test('may change the drafts and nothing else', () {
      final List<Candidate> rewritten = parseRewrite(
        encode(<String, Object?>{
          'strategy': '降压',
          'facts': <String>['模型试图换掉事实'],
          'candidates': <Object?>[
            <String, Object?>{
              'text': '行，你先忙',
              'reason': '更口语',
              'tradeoff': '信息少',
            },
          ],
        }),
        strategy: '降压',
      );
      expect(rewritten, hasLength(1));
      expect(rewritten.first.text, '行，你先忙');
    });

    test('accepts a candidates-only answer', () {
      final List<Candidate> rewritten = parseRewrite(
        encode(<String, Object?>{
          'candidates': <Object?>[
            <String, Object?>{
              'text': '行，你先忙',
              'reason': '更口语',
              'tradeoff': '信息少',
            },
          ],
        }),
        strategy: '降压',
      );
      expect(rewritten.first.text, '行，你先忙');
    });

    test('is refused when it changes the strategy or overruns the contract', () {
      // 101 characters, the candidate contract's own ceiling — not the user's
      // preference ceiling, which is a separate check with a separate owner
      // (see the preference tests in analysis_test.dart).
      for (final Map<String, Object?> change in <Map<String, Object?>>[
        <String, Object?>{'strategy': '约见'},
        <String, Object?>{
          'candidates': <Object?>[
            <String, Object?>{'text': '字' * 101, 'reason': '理由', 'tradeoff': '代价'},
          ],
        },
      ]) {
        expect(
          () => parseRewrite(encode(change), strategy: '降压'),
          throwsA(isA<DomainException>()),
          reason: 'accepted $change',
        );
      }
    });

    test('may legitimately come back empty', () {
      // Zero candidates is a legal analysis outcome — "this round, say nothing"
      // — so the *shape* is allowed here. That a rewrite may not return nothing
      // is the caller's rule, because a rewrite only exists when there was
      // something to rewrite: see `rewriteSnapshot` in analysis_test.dart.
      expect(
        parseRewrite(
          encode(<String, Object?>{'candidates': <Object?>[]}),
          strategy: '降压',
        ),
        isEmpty,
      );
    });
  });
}
