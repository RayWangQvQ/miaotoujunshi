import 'dart:convert';
import 'dart:typed_data';

import 'package:miaotou_capabilities/miaotou_capabilities.dart';
import 'package:miaotou_domain/miaotou_domain.dart';
import 'package:test/test.dart';

import 'support/repo_payload.dart';

/// The trend module, and the two things about it worth defending.
///
/// The first is that a candle is a **message balance**: an `other` message adds
/// one, a `me` message subtracts one, and no amount of shape makes it a
/// relationship score. The ports each said so in a different sentence; here it is
/// said once and asserted.
///
/// The second is that the CSV contract now has **two** directions. The three
/// ports only imported — a user brought a chat export in and looked at the chart.
/// The export is new, so the round trip is the thing that needs proving, and the
/// shape that round-trips is the candle table rather than the conversation.
void main() {
  late SharedMaterial material;
  late TrendRules rules;

  setUpAll(() async {
    material = await loadRealMaterial();
    rules = TrendRules.parse(await material.text(trendRulesPath));
  });

  Uint8List bytes(String text) => utf8.encode(text);

  Trend chat(String text, {String title = '导入的聊天记录'}) =>
      readChatCsv(bytes(text), rules: rules, title: title);

  /// A candle reduced to the fields anyone can compare, since [Candle] carries
  /// no `==` of its own.
  List<Object?> shape(Candle candle) => <Object?>[
        candle.date,
        candle.open,
        candle.high,
        candle.low,
        candle.close,
        candle.mine,
        candle.other,
        candle.events,
      ];

  List<List<Object?>> shapes(Iterable<Candle> candles) =>
      <List<Object?>>[for (final Candle candle in candles) shape(candle)];

  group('the contract', () {
    test('comes from the payload rather than from a constant in the code', () {
      expect(rules.columns, <String>['timestamp', 'sender', 'message']);
      expect(rules.senders, <String>['me', 'other']);
      expect(rules.timestampFormat, 'YYYY-MM-DD HH:MM:SS');
      expect(rules.maxBytes, 4000000);
      expect(rules.maxMessages, 20000);
      expect(rules.maxEventChars, 160);
      expect(rules.metric, messageBalanceMetric);
      expect(rules.metricNote, contains('not a relationship quality score'));
    });

    test('refuses a contract that stopped naming both senders', () {
      // The balance counts `other` up and `me` down. Without both words every
      // message would count the same way, silently.
      expect(
        () => TrendRules.parse(jsonEncode(<String, Object?>{
          'columns': rules.columns,
          'senders': <String>['me', 'her'],
          'timestamp_format': rules.timestampFormat,
          'max_bytes': rules.maxBytes,
          'max_messages': rules.maxMessages,
          'max_event_chars': rules.maxEventChars,
          'metric': rules.metric,
          'metric_note': rules.metricNote,
        })),
        throwsA(isA<DomainException>().having(
          (DomainException error) => error.message,
          'message',
          contains('senders'),
        )),
      );
    });
  });

  group('a chat CSV', () {
    test('is a message balance, not a relationship probability', () {
      // The existing suite's first expectation, restated: four messages over two
      // days, and the two days do not even out.
      final Trend trend = chat('timestamp,sender,message,event\n'
          '2026-08-01 10:00:00,me,早,\n'
          '2026-08-01 10:01:00,other,早上好,主动接话\n'
          '2026-08-01 10:02:00,other,今天有空吗,\n'
          '2026-08-03 12:00:00,me,周末见,\n');

      expect(trend.messages, 4);
      expect(trend.candles, hasLength(2));

      final Candle first = trend.candles.first;
      expect(<int>[first.open, first.high, first.low, first.close],
          <int>[0, 1, -1, 1]);
      expect(<Object?>[first.mine, first.other, first.events],
          <Object?>[1, 2, <String>['主动接话']]);

      final Candle last = trend.candles.last;
      expect(<int>[last.open, last.high, last.low, last.close], <int>[1, 1, 0, 0]);
      expect(<int>[last.mine, last.other], <int>[1, 0]);
    });

    test('opens each day where the last one closed', () {
      final Trend trend = chat('timestamp,sender,message\n'
          '2026-08-01 10:00:00,other,一\n'
          '2026-08-01 10:01:00,other,二\n'
          '2026-08-02 10:00:00,me,三\n'
          '2026-08-03 10:00:00,other,四\n');
      expect(<int>[for (final Candle candle in trend.candles) candle.open],
          <int>[0, 2, 1]);
      expect(<int>[for (final Candle candle in trend.candles) candle.close],
          <int>[2, 1, 2]);
    });

    test('skips a day with no messages instead of drawing a calendar', () {
      final Trend trend = chat('timestamp,sender,message\n'
          '2026-08-01 10:00:00,other,一\n'
          '2026-08-09 10:00:00,other,二\n');
      expect(<String>[for (final Candle candle in trend.candles) candle.date],
          <String>['2026-08-01', '2026-08-09']);
    });

    test('allows extra columns', () {
      final Trend trend = chat('timestamp,sender,message,note\n'
          '2026-08-01 10:00:00,me,早,备注\n');
      expect(trend.candles.single.mine, 1);
    });

    test('refuses a sender that is not me or other', () {
      // ADR-0015: the CSV is the one place the user states who is who, and the
      // ports that guessed from bubble alignment disagreed with each other.
      for (final String sender in <String>['unknown', 'them', '对方', 'ME']) {
        expect(
          () => chat('timestamp,sender,message\n2026-08-01 10:00:00,$sender,你好\n'),
          throwsA(isA<DomainException>().having(
            (DomainException error) => error.message,
            'message',
            contains('sender'),
          )),
          reason: 'accepted $sender',
        );
      }
    });

    test('refuses a time that runs backwards', () {
      expect(
        () => chat('timestamp,sender,message\n'
            '2026-08-02 10:00:00,me,你好\n'
            '2026-08-01 10:00:00,other,你好\n'),
        throwsA(isA<DomainException>().having(
          (DomainException error) => error.message,
          'message',
          contains('升序'),
        )),
      );
    });

    test('refuses a header without the three columns', () {
      expect(
        () => chat('when,sender,message\n2026-08-01 10:00:00,me,你好\n'),
        throwsA(isA<DomainException>().having(
          (DomainException error) => error.message,
          'message',
          allOf(contains('timestamp'), contains('sender'), contains('message')),
        )),
      );
    });

    test('refuses a time that is not a timestamp', () {
      expect(
        () => chat('timestamp,sender,message\nyesterday,me,你好\n'),
        throwsA(isA<DomainException>().having(
          (DomainException error) => error.message,
          'message',
          contains('timestamp'),
        )),
      );
    });

    test('refuses a bare date, because the contract names a format with a time',
        () {
      expect(
        () => chat('timestamp,sender,message\n2026-08-01,me,你好\n'),
        throwsA(isA<DomainException>()),
      );
    });

    test('refuses a day that does not exist instead of rolling it forward', () {
      // `DateTime.parse` reads `2026-02-30` as March 2. Accepting that would put
      // a candle on a date the conversation never had, which is the quietest
      // possible way to be wrong about a timeline.
      expect(
        () => chat('timestamp,sender,message\n2026-02-30 10:00:00,me,你好\n'),
        throwsA(isA<DomainException>().having(
          (DomainException error) => error.message,
          'message',
          contains('timestamp'),
        )),
      );
      expect(
        () => chat('timestamp,sender,message\n2026-08-01 24:00:00,me,你好\n'),
        throwsA(isA<DomainException>()),
      );
    });

    test('reads the value a short row is missing as missing', () {
      // Python's DictReader returned None for a column the row did not have, and
      // the report was about the missing value. Android refused the row outright;
      // that stricter reading is the divergence this convergence drops.
      expect(
        () => chat('timestamp,sender,message\n2026-08-01 10:00:00,me\n'),
        throwsA(isA<DomainException>().having(
          (DomainException error) => error.message,
          'message',
          contains('空消息'),
        )),
      );
    });

    test('refuses a file that holds nothing but a header', () {
      expect(
        () => chat('timestamp,sender,message\n'),
        throwsA(isA<DomainException>().having(
          (DomainException error) => error.message,
          'message',
          contains('没有可分析'),
        )),
      );
    });

    test('refuses a file past the byte ceiling, before parsing it', () {
      expect(
        () => readChatCsv(
          Uint8List(rules.maxBytes + 1),
          rules: rules,
        ),
        throwsA(isA<DomainException>().having(
          (DomainException error) => error.message,
          'message',
          contains('${rules.maxBytes ~/ 1000000} MB'),
        )),
      );
    });

    test('refuses more messages than the ceiling', () {
      final StringBuffer text = StringBuffer('timestamp,sender,message\n');
      for (int index = 0; index <= rules.maxMessages; index++) {
        text.write('2026-08-01 10:00:00,me,你好\n');
      }
      expect(
        () => chat(text.toString()),
        throwsA(isA<DomainException>().having(
          (DomainException error) => error.message,
          'message',
          contains('${rules.maxMessages}'),
        )),
      );
    });

    test('refuses an annotation past its ceiling, naming the ceiling', () {
      final String tooLong = '字' * (rules.maxEventChars + 1);
      expect(
        () => chat('timestamp,sender,message,event\n'
            '2026-08-01 10:00:00,me,你好,$tooLong\n'),
        throwsA(isA<DomainException>().having(
          (DomainException error) => error.message,
          'message',
          contains('${rules.maxEventChars}'),
        )),
      );
      final String atCeiling = '字' * rules.maxEventChars;
      expect(
        chat('timestamp,sender,message,event\n'
            '2026-08-01 10:00:00,me,你好,$atCeiling\n'),
        isA<Trend>(),
      );
    });

    test('refuses an annotation that holds a line break', () {
      // One annotation is one line. This is what makes the export's newline
      // separator invertible, so it is enforced at the only producer of events.
      expect(
        () => chat('timestamp,sender,message,event\n'
            '2026-08-01 10:00:00,me,你好,"第一行\n第二行"\n'),
        throwsA(isA<DomainException>().having(
          (DomainException error) => error.message,
          'message',
          contains('换行'),
        )),
      );
    });

    test('carries the title and the source it was given', () {
      final Trend trend = chat('timestamp,sender,message\n'
          '2026-08-01 10:00:00,me,你好\n', title: '导入记录 · 聊天');
      expect(trend.title, '导入记录 · 聊天');
      expect(trend.source, '');
      expect(trend.note, '');
      expect(trend.metric, messageBalanceMetric);
    });
  });

  group('the export', () {
    test('round-trips a table built from a real chat, exactly', () {
      final Trend trend = chat('timestamp,sender,message,event\n'
          '2026-08-01 10:00:00,me,早,\n'
          '2026-08-01 10:01:00,other,早上好,主动接话\n'
          '2026-08-01 10:02:00,other,今天有空吗,\n'
          '2026-08-03 12:00:00,me,周末见,见过面\n');
      // Negative balances are in here on purpose: a day the user wrote less is
      // how the ceiling is reached, and it is the case a signed-int round trip
      // has to survive.
      expect(trend.candles.first.low, lessThan(0));

      final List<Candle> back =
          readCandleCsv(writeCandleCsv(trend.candles), rules: rules);
      expect(shapes(back), shapes(trend.candles));
    });

    test('keeps annotations that need quoting', () {
      final List<Candle> candles = <Candle>[
        const Candle(
          date: '2026-08-01',
          open: 0,
          high: 2,
          low: -1,
          close: 1,
          mine: 3,
          other: 4,
          events: <String>['带,逗号', '带"引号"', '多个'],
        ),
      ];
      expect(shapes(readCandleCsv(writeCandleCsv(candles), rules: rules)),
          shapes(candles));
    });

    test('writes the day table with its own header, not the chat header', () {
      final Trend trend = chat('timestamp,sender,message\n'
          '2026-08-01 10:00:00,me,你好\n');
      final String text = utf8.decode(writeCandleCsv(trend.candles));
      expect(text.split('\n').first, candleTableColumns.join(','));
      expect(text, startsWith('date,open,high,low,close,mine,other,event\n'));
    });

    test('reads a trimmed table where the optional columns are gone', () {
      final List<Candle> candles = readCandleCsv(
        bytes('date,open,high,low,close\n2026-08-01,0,1,-1,0\n'),
        rules: rules,
      );
      expect(candles.single.mine, 0);
      expect(candles.single.other, 0);
      expect(candles.single.events, isEmpty);
    });

    test('refuses a candle whose low is above its high', () {
      expect(
        () => readCandleCsv(
          bytes('date,open,high,low,close\n2026-08-01,0,1,2,0\n'),
          rules: rules,
        ),
        throwsA(isA<DomainException>().having(
          (DomainException error) => error.message,
          'message',
          contains('开高低收'),
        )),
      );
    });

    test('refuses a table that repeats a day or runs backwards', () {
      for (final String body in <String>[
        'date,open,high,low,close\n2026-08-01,0,1,0,1\n2026-08-01,1,2,1,2\n',
        'date,open,high,low,close\n2026-08-02,0,1,0,1\n2026-08-01,1,2,1,2\n',
      ]) {
        expect(
          () => readCandleCsv(bytes(body), rules: rules),
          throwsA(isA<DomainException>().having(
            (DomainException error) => error.message,
            'message',
            contains('递增'),
          )),
          reason: 'accepted $body',
        );
      }
    });

    test('refuses a table without the candle columns', () {
      expect(
        () => readCandleCsv(
          bytes('timestamp,sender,message\n2026-08-01 10:00:00,me,你好\n'),
          rules: rules,
        ),
        throwsA(isA<DomainException>().having(
          (DomainException error) => error.message,
          'message',
          contains('date'),
        )),
      );
    });

    test('refuses to write a break inside an annotation', () {
      // Writing it would come home as two annotations, which is a silent edit to
      // the user's own data. Both readers already forbid it, so this can only
      // fire on a candle assembled by hand.
      expect(
        () => writeCandleCsv(<Candle>[
          const Candle(
            date: '2026-08-01',
            open: 0,
            high: 1,
            low: 0,
            close: 1,
            events: <String>['第一行\n第二行'],
          ),
        ]),
        throwsA(isA<DomainException>().having(
          (DomainException error) => error.message,
          'message',
          contains('换行'),
        )),
      );
    });
  });

  group('the synthetic cases', () {
    test('are five, with distinct ids and real chats behind them', () async {
      final List<DemoCase> cases = await readDemoCases(material);
      expect(cases, hasLength(5));
      expect(<String>{for (final DemoCase item in cases) item.id}, hasLength(5));
      for (final DemoCase item in cases) {
        expect(item.id, isNotEmpty);
        expect(item.title, isNotEmpty);
        expect(item.chat, endsWith('.csv'));
      }
    });

    test('load with illustrative candles, merged events and the expected note',
        () async {
      for (final DemoCase item in await readDemoCases(material)) {
        final Trend trend = await readDemoCase(material, item.id, rules: rules);
        expect(trend.messages, greaterThan(0));
        expect(trend.candles, isNotEmpty);
        expect(trend.title, contains('合成示例'));
        expect(trend.metric, syntheticEventIndexMetric);
        expect(trend.note, isNotEmpty);
        expect(trend.source, '$caseBundleDir/${item.chat}');

        // The illustrative candles are hand-set on a 0..100 scale, and every one
        // of them has to be a candle: low ≤ open, close ≤ high.
        for (final Candle candle in trend.candles) {
          expect(candle.low, greaterThanOrEqualTo(0));
          expect(candle.high, lessThanOrEqualTo(100));
          expect(candle.low <= candle.open && candle.open <= candle.high, isTrue);
          expect(candle.low <= candle.close && candle.close <= candle.high, isTrue);
        }
        for (int index = 1; index < trend.candles.length; index++) {
          expect(
            trend.candles[index].date.compareTo(trend.candles[index - 1].date),
            greaterThan(0),
          );
        }

        // The chats carry no `event` column, so every annotation on screen came
        // from the manifest. That is the merge macOS did and the other two ports
        // skipped.
        final Trend chatOnly = readChatCsv(
          utf8.encode(await material.text('$caseBundleDir/${item.chat}')),
          rules: rules,
        );
        expect(
          <int>[for (final Candle candle in chatOnly.candles) candle.events.length]
              .fold(0, (int sum, int value) => sum + value),
          0,
          reason: 'the bundled chats are expected to have no event column',
        );
        expect(
          trend.candles.any((Candle candle) => candle.events.isNotEmpty),
          isTrue,
          reason: 'the manifest key events were not merged',
        );
      }
    });

    test('refuse a case id the manifest does not have', () async {
      await expectLater(
        readDemoCase(material, 'no_such_case', rules: rules),
        throwsA(isA<DomainException>().having(
          (DomainException error) => error.message,
          'message',
          contains('没有这个合成案例'),
        )),
      );
    });

    test('refuse candles that do not line up with the chat', () async {
      // The illustrative candles are hand-written, so they can disagree with the
      // chat they describe. There is no second bundle holding such a
      // disagreement, so one is manufactured from the real bundle here.
      await expectLater(
        demoFromKline(
          'mutual_warming',
          (List<Object?> rows) => rows.removeLast(),
        ),
        throwsA(isA<DomainException>().having(
          (DomainException error) => error.message,
          'message',
          contains('不匹配'),
        )),
      );
    });

    test('refuse a candle that does not open where the last one closed', () async {
      await expectLater(
        demoFromKline('mutual_warming', (List<Object?> rows) {
          final List<Object?> second = (rows[1]! as List).cast<Object?>();
          // 60 is a well-formed candle on this row, but 54 is where the previous
          // day closed — so only the chain rule can refuse it.
          rows[1] = <Object?>[second[0], 60, second[2], second[3], second[4]];
        }),
        throwsA(isA<DomainException>().having(
          (DomainException error) => error.message,
          'message',
          contains('开高低收'),
        )),
      );
    });

    test('refuse a candle off the illustrative scale', () async {
      await expectLater(
        demoFromKline('mutual_warming', (List<Object?> rows) {
          final List<Object?> first = (rows[0]! as List).cast<Object?>();
          rows[0] = <Object?>[first[0], first[1], 140, first[3], first[4]];
        }),
        throwsA(isA<DomainException>().having(
          (DomainException error) => error.message,
          'message',
          contains('开高低收'),
        )),
      );
    });
  });
}

/// Loads one synthetic case from the real bundle with its candle table edited.
Future<Trend> demoFromKline(
  String caseId,
  void Function(List<Object?> rows) edit,
) async {
  final SharedMaterial material = await SharedMaterial.load(_EditedPayload(
    RepoSharedPayload(findRepositoryRoot().path),
    '$caseBundleDir/demo_kline.json',
    (String text) {
      final Map<String, Object?> root =
          (jsonDecode(text) as Map).cast<String, Object?>();
      final Map<String, Object?> cases =
          (root['cases']! as Map).cast<String, Object?>();
      edit((cases[caseId]! as List).cast<Object?>());
      return jsonEncode(root);
    },
  ));
  return readDemoCase(
    material,
    caseId,
    rules: TrendRules.parse(await material.text(trendRulesPath)),
  );
}

/// The real repository payload, with one file edited on the way out.
final class _EditedPayload implements SharedPayload {
  _EditedPayload(this._inner, this._path, this._edit);

  final SharedPayload _inner;
  final String _path;
  final String Function(String text) _edit;

  @override
  Future<Uint8List> read(String repoRelativePath) async {
    final Uint8List bytes = await _inner.read(repoRelativePath);
    return repoRelativePath == _path
        ? utf8.encode(_edit(utf8.decode(bytes)))
        : bytes;
  }

  @override
  Future<List<String>> list(String repoRelativeDir) =>
      _inner.list(repoRelativeDir);
}
