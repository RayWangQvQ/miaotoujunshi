// A migration instrument, not part of the application. See README.md beside this
// file for what it is and for when it is deleted.
//
// It reads the shared fixtures, runs every one of them through the Dart domain
// and prints one canonical conclusion per area as JSON on stdout, for
// `compare.py` to set against the Python ports' own conclusions.
//
// "Canonical" is the whole design: the two sides must not be compared on their
// own data structures but on the decision each one reached — which candidates
// survived, which answer was refused, which candle a day became. Wording is not
// compared anywhere, because a refusal sentence is allowed to differ; only
// accept/reject and the values that follow from it are.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:miaotou_capabilities/miaotou_capabilities.dart';
import 'package:miaotou_domain/miaotou_domain.dart';

void main() {
  final Directory here = File.fromUri(Platform.script).parent;
  // tool/double_run → tool → miaotou_app → apps → jev_flutter → integrations → root
  final Directory root =
      here.parent.parent.parent.parent.parent.parent;
  final Map<String, Object?> fixtures =
      jsonDecode(File('${here.path}/fixtures.json').readAsStringSync())
          as Map<String, Object?>;

  final List<String> strategies = _strings(
      (jsonDecode(_payload(root, strategyCriteriaPath)) as Map)['strategies']);
  final TrendRules rules =
      TrendRules.parse(_payload(root, trendRulesPath));
  final RelationshipVocabulary vocabulary =
      RelationshipVocabulary.parse(_payload(root, relationshipEnumsPath));

  stdout.writeln(jsonEncode(<String, Object?>{
    'injection': _each(fixtures['injection']!, _injectionCase),
    'advice': _each(fixtures['advice']!,
        (Map<String, Object?> f) => _adviceCase(f, strategies)),
    'rewrite': _each(fixtures['rewrite']!, _rewriteCase),
    'scoring': _each(fixtures['scoring']!, _scoringCase),
    'chat_csv': _each(fixtures['chat_csv']!,
        (Map<String, Object?> f) => _chatCsvCase(f, rules)),
    'profile': _each(fixtures['profile']!,
        (Map<String, Object?> f) => _profileCase(f, vocabulary)),
    'update': _each(fixtures['update']!, _updateCase),
    'csv_grid': _each(fixtures['csv_grid']!, _csvGridCase),
  }));
}

/// One payload file, read at runtime exactly as an application would read it.
///
/// The limits and the vocabulary are *not* copied into the fixtures: a payload
/// change has to move both sides of this comparison at once, or the instrument
/// would be comparing two different contracts and calling the difference a
/// divergence.
String _payload(Directory root, String relative) =>
    File('${root.path}/$relative').readAsStringSync();

List<Object?> _each(
  Object? cases,
  Map<String, Object?> Function(Map<String, Object?> fixture) run,
) =>
    <Object?>[
      for (final Object? entry in cases! as List<Object?>)
        run((entry! as Map).cast<String, Object?>()),
    ];

/// #10 — the anti-injection filter, against Windows `core/draft.py`.
///
/// Three conclusions: which past lines are suspect, which recent lines the echo
/// rule reads, and which candidates survive the filter.
Map<String, Object?> _injectionCase(Map<String, Object?> fixture) {
  final List<CapturedLine> lines = <CapturedLine>[
    for (final Object? raw in fixture['messages']! as List<Object?>) _line(raw),
  ];
  final List<String> suspects = suspectInjectionTexts(lines);
  final List<String> recent = otherRecentTexts(lines);
  return <String, Object?>{
    'id': fixture['id'],
    'suspects': suspects,
    'recent': recent,
    'survivors': sanitizeCandidateTexts(
      suspects: suspects,
      otherRecent: recent,
      candidates: (fixture['candidates']! as List<Object?>).cast<String>(),
    ),
  };
}

/// #7 — reading an analysis answer, against macOS `core.parse_advice`.
///
/// Only `ok` and the parsed values are reported: the refusal sentence is a
/// port-local wording and is not part of the conclusion.
Map<String, Object?> _adviceCase(
    Map<String, Object?> fixture, List<String> strategies) {
  final String raw = fixture['raw_text'] as String? ?? jsonEncode(fixture['answer']);
  try {
    final Advice advice = parseAdvice(raw, strategies: strategies);
    return <String, Object?>{
      'id': fixture['id'],
      'ok': true,
      'intent': advice.intent,
      'confidence': advice.intentConfidence,
      'strategy': advice.strategy,
      'support': advice.support,
      'recommendation': advice.recommendation,
      'next_step': advice.nextStep,
      'stop_condition': advice.stopCondition,
      'question': advice.question,
      'facts': advice.facts,
      'hypotheses': advice.hypotheses,
      'unknowns': advice.unknowns,
      'candidates': <Object?>[
        for (final Candidate candidate in advice.candidates)
          <String, Object?>{
            'text': candidate.text,
            'reason': candidate.reason,
            'tradeoff': candidate.tradeoff,
          },
      ],
    };
  } on DomainException {
    return <String, Object?>{'id': fixture['id'], 'ok': false};
  }
}

/// One fixture message as the filter reads it: a speaker and its text.
CapturedLine _line(Object? raw) {
  final List<Object?> row = raw! as List<Object?>;
  return CapturedLine(
    speaker: row[0] == 'other' ? Speaker.other : Speaker.me,
    text: row[1]! as String,
  );
}

/// One fixture row as a candidate.
Candidate _candidate(Object? raw) {
  final Map<String, Object?> row = (raw! as Map).cast<String, Object?>();
  return Candidate(
    text: row['text']! as String,
    reason: row['reason']! as String,
    tradeoff: row['tradeoff']! as String,
  );
}

/// #7 — reading a rewrite answer, against macOS `core.parse_rewrite`.
Map<String, Object?> _rewriteCase(Map<String, Object?> fixture) {
  final String raw = fixture['raw_text'] as String? ?? jsonEncode(fixture['answer']);
  try {
    final List<Candidate> candidates =
        parseRewrite(raw, strategy: fixture['strategy']! as String);
    return <String, Object?>{
      'id': fixture['id'],
      'ok': true,
      'candidates': <Object?>[
        for (final Candidate candidate in candidates)
          <String, Object?>{
            'text': candidate.text,
            'reason': candidate.reason,
            'tradeoff': candidate.tradeoff,
          },
      ],
    };
  } on DomainException {
    return <String, Object?>{'id': fixture['id'], 'ok': false};
  }
}

/// #7 — turning scores into weights, against macOS `ranking.apply_scores`.
///
/// The conclusion is the order and the whole-percentage weights, which is the
/// only thing the panel shows.
Map<String, Object?> _scoringCase(Map<String, Object?> fixture) {
  final String raw = fixture['raw_text'] as String? ?? jsonEncode(fixture['answer']);
  final List<Candidate> candidates = <Candidate>[
    for (final Object? entry in fixture['candidates']! as List<Object?>)
      _candidate(entry),
  ];
  try {
    final List<Candidate> scored = applyScores(candidates, raw);
    return <String, Object?>{
      'id': fixture['id'],
      'ok': true,
      'ranked': <Object?>[
        for (final Candidate candidate in scored)
          <String, Object?>{'text': candidate.text, 'weight': candidate.weight},
      ],
    };
  } on DomainException {
    return <String, Object?>{'id': fixture['id'], 'ok': false};
  }
}

/// #8 — a timestamped chat export, against macOS `trend.load_csv`.
///
/// Reported per candle, because the candles are the chart: a day that became the
/// wrong candle is a regression even when the totals happen to agree.
Map<String, Object?> _chatCsvCase(
    Map<String, Object?> fixture, TrendRules rules) {
  final Uint8List bytes =
      Uint8List.fromList(utf8.encode(fixture['csv']! as String));
  try {
    final Trend trend = readChatCsv(bytes, rules: rules);
    return <String, Object?>{
      'id': fixture['id'],
      'ok': true,
      'messages': trend.messages,
      'candles': <Object?>[
        for (final Candle candle in trend.candles)
          <String, Object?>{
            'date': candle.date,
            'open': candle.open,
            'high': candle.high,
            'low': candle.low,
            'close': candle.close,
            'mine': candle.mine,
            'other': candle.other,
            'events': candle.events,
          },
      ],
    };
  } on DomainException {
    return <String, Object?>{'id': fixture['id'], 'ok': false};
  }
}

/// #9 — a profile, against macOS `experience.validate_profile` / `profile_context`.
///
/// `context` is decoded before it is reported so that key order, which differs
/// between the two languages' encoders, is not mistaken for a divergence.
Map<String, Object?> _profileCase(
    Map<String, Object?> fixture, RelationshipVocabulary vocabulary) {
  final Map<String, Object?> raw =
      (fixture['profile']! as Map).cast<String, Object?>();
  // A field the fixture omits is an empty one, which is what macOS sees too:
  // `validate_profile` reads its fields with `.get`.
  final Profile profile = Profile(
    id: raw['id'] as String? ?? '',
    label: raw['label'] as String? ?? '',
    stage: raw['stage'] as String? ?? '',
    goal: raw['goal'] as String? ?? '',
    background: raw['background'] as String? ?? '',
    myMbti: raw['my_mbti'] as String? ?? '',
    theirMbti: raw['their_mbti'] as String? ?? '',
    myScore: raw['my_score'] as String? ?? '',
    theirScore: raw['their_score'] as String? ?? '',
    notes: raw['notes'] as String? ?? '',
  );
  try {
    validateProfile(profile, vocabulary);
    return <String, Object?>{
      'id': fixture['id'],
      'ok': true,
      'context': jsonDecode(profileContext(profile)),
    };
  } on DomainException {
    return <String, Object?>{'id': fixture['id'], 'ok': false, 'context': null};
  }
}

/// #10 — whether a fetched release is worth reporting, against Windows
/// `app/update.py`.
///
/// The network half of the Windows function is not ported and cannot be: the
/// domain never sees a socket. What is compared is the decision the fetched tag
/// leads to.
Map<String, Object?> _updateCase(Map<String, Object?> fixture) {
  final ReleaseInfo? release = newerRelease(
    current: fixture['current']! as String,
    latest: ReleaseInfo(
      tag: stripLeadingV(fixture['tag']! as String),
      url: fixture['url']! as String,
    ),
  );
  return <String, Object?>{
    'id': fixture['id'],
    'reports': release != null,
    'tag': release?.tag,
  };
}

/// #8 — the CSV grid, against Python's `csv` module.
///
/// The property compared is a round trip: what the writer emits must come back
/// out of the reader unchanged. There is no Python function to pair with
/// `parseCsvGrid`, but there is a contract that both sides' CSV handling has to
/// satisfy, and "a cell survives being written and read" is it.
Map<String, Object?> _csvGridCase(Map<String, Object?> fixture) {
  final List<List<String>> grid = <List<String>>[
    for (final Object? row in fixture['grid']! as List<Object?>)
      (row! as List<Object?>).cast<String>(),
  ];
  final String text = writeCsvGrid(grid);
  final List<List<String>> back = parseCsvGrid(text);
  return <String, Object?>{
    'id': fixture['id'],
    'round_trip': _sameGrid(grid, back),
    'back': back,
  };
}

bool _sameGrid(List<List<String>> left, List<List<String>> right) {
  if (left.length != right.length) {
    return false;
  }
  for (int i = 0; i < left.length; i++) {
    if (left[i].length != right[i].length) {
      return false;
    }
    for (int j = 0; j < left[i].length; j++) {
      if (left[i][j] != right[i][j]) {
        return false;
      }
    }
  }
  return true;
}

List<String> _strings(Object? raw) =>
    (raw! as List<Object?>).cast<String>();
