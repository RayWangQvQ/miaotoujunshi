import 'dart:convert';
import 'dart:typed_data';

import 'csv.dart';
import 'errors.dart';
import 'shared_material.dart';

/// The CSV contract and its limits.
///
/// Read at runtime like the other payload files, because the limits are shared
/// with the three ports while the code that applies them is now shared too
/// (ADR-0006, ADR-0009).
const String trendRulesPath = 'miaotoujunshi/references/data/trend-rules.json';

/// The synthetic case bundle: the manifest, five chats, the illustrative candles.
///
/// It sits in the payload rather than in any port, because all three ports offer
/// the same five cases and macOS was the only one that had put the files beside
/// its own module. A case file is therefore read through the shared-material
/// capability like every other payload file — and a missing one is a hard error,
/// which is what keeps a forgotten packaging entry from turning into an empty
/// picker (ADR-0008).
const String caseBundleDir = 'miaotoujunshi/examples/relationship_cases';

/// The metric a candle built from a real conversation carries.
const String messageBalanceMetric = 'message_balance';

/// The metric the bundled cases carry: hand-set OHLC, not a computed balance.
const String syntheticEventIndexMetric = 'synthetic_event_index';

/// The two sender tokens, and which way each one moves the balance.
///
/// They are spelled here rather than derived from [TrendRules.senders] because
/// the direction is not a property of the list: the payload's own `metric_note`
/// defines the balance in terms of these two words. [TrendRules.parse] refuses a
/// contract that has stopped naming them, so the literals cannot go stale
/// silently.
const String senderMe = 'me';
const String senderOther = 'other';

/// The columns the exported candle table carries, in order.
const List<String> candleTableColumns = <String>[
  'date',
  'open',
  'high',
  'low',
  'close',
  'mine',
  'other',
  'event',
];

/// True when four numbers are a well-formed candle.
///
/// The rule is one function because both readers need it — the conversation
/// import never produces a malformed candle, but a candle table read back from
/// disk could be edited by hand — and because "low ≤ open, close ≤ high" is the
/// only thing that makes a drawn candle mean anything. The *wording* of the
/// refusal stays at each call site, which is what the payload asks for: it
/// carries the limits, not the sentences.
bool isWellFormedCandle({
  required int open,
  required int high,
  required int low,
  required int close,
}) =>
    low <= open && low <= close && open <= high && close <= high && low <= high;

/// The CSV contract, as read from the payload.
///
/// Everything the reader enforces comes from here rather than from a constant in
/// this file: the column names it requires, the two sender tokens, the message
/// and event ceilings, and the byte ceiling. That is what keeps the three ports
/// from drifting apart on a number nobody remembered to change.
final class TrendRules {
  const TrendRules({
    required this.columns,
    required this.senders,
    required this.timestampFormat,
    required this.maxBytes,
    required this.maxMessages,
    required this.maxEventChars,
    required this.metric,
    required this.metricNote,
  });

  /// The columns a chat CSV must have. Extra columns are allowed.
  final List<String> columns;

  /// The only sender values accepted, as the file must spell them.
  final List<String> senders;

  /// The format a timestamp must be written in, for the refusal that names it.
  final String timestampFormat;

  final int maxBytes;
  final int maxMessages;
  final int maxEventChars;

  /// The name of the metric this contract describes.
  final String metric;

  /// The sentence that says what the metric is not. Travels with the data so a
  /// caller cannot render a chart without having been handed the disclaimer.
  final String metricNote;

  /// Parses the contract file.
  static TrendRules parse(String text) {
    final Map<String, Object?> rules = _object(jsonDecode(text), 'trend-rules.json');
    final List<String> senders = _strings(rules['senders'], 'senders', 'trend-rules.json');
    // The balance counts `other` up and `me` down. A contract that stopped
    // naming both would make every message count the same way, silently and in
    // the wrong direction, so it is refused at the read rather than at the chart.
    if (!senders.contains(senderMe) || !senders.contains(senderOther)) {
      throw const DomainException(
          'trend-rules.json 的 senders 必须同时包含 me 和 other：消息收支的方向就是按这两个词定义的');
    }
    return TrendRules(
      columns: _strings(rules['columns'], 'columns', 'trend-rules.json'),
      senders: senders,
      timestampFormat: _string(rules['timestamp_format'], 'timestamp_format', 'trend-rules.json'),
      maxBytes: _int(rules['max_bytes'], 'max_bytes', 'trend-rules.json'),
      maxMessages: _int(rules['max_messages'], 'max_messages', 'trend-rules.json'),
      maxEventChars: _int(rules['max_event_chars'], 'max_event_chars', 'trend-rules.json'),
      metric: _string(rules['metric'], 'metric', 'trend-rules.json'),
      metricNote: _string(rules['metric_note'], 'metric_note', 'trend-rules.json'),
    );
  }
}

/// One day's candle.
///
/// The shape is macOS's, which is the superset: the Windows and Android ports
/// each carried a strict subset of it. `mine` and `other` are the per-side counts
/// the summary line needs, and `events` is the annotation column, which only
/// macOS read.
///
/// **It is a message balance and not a relationship score.** An `other` message
/// adds one, a `me` message subtracts one. Every string in the payload that
/// describes this number says so, and so does [TrendRules.metricNote].
final class Candle {
  const Candle({
    required this.date,
    required this.open,
    required this.high,
    required this.low,
    required this.close,
    this.mine = 0,
    this.other = 0,
    this.events = const <String>[],
  });

  /// The day, as `YYYY-MM-DD`. One candle per day, which is why both readers
  /// refuse a table that repeats a date.
  final String date;

  /// The balance as the day opened, which is the previous day's [close].
  final int open;

  final int high;
  final int low;

  /// The balance as the day closed.
  final int close;

  /// How many `me` messages the day had.
  final int mine;

  /// How many `other` messages the day had.
  final int other;

  /// Annotations attached to this day, from the CSV's `event` column or from a
  /// synthetic case's key events. They are shown and they never enter the
  /// arithmetic: the candle is built from message directions alone.
  final List<String> events;

  /// How many messages this day's candle was built from.
  int get count => mine + other;

  /// The same candle with some fields replaced, used while a day is being built.
  Candle copyWith({
    int? open,
    int? high,
    int? low,
    int? close,
    int? mine,
    int? other,
    List<String>? events,
  }) =>
      Candle(
        date: date,
        open: open ?? this.open,
        high: high ?? this.high,
        low: low ?? this.low,
        close: close ?? this.close,
        mine: mine ?? this.mine,
        other: other ?? this.other,
        events: events ?? this.events,
      );
}

/// A trend: the candles plus the little that is known about where they came from.
final class Trend {
  const Trend({
    required this.title,
    required this.candles,
    required this.source,
    this.note = '',
    this.metric = messageBalanceMetric,
  });

  final String title;
  final List<Candle> candles;

  /// Where it came from. A payload-relative path for a bundled case, or whatever
  /// the application passes for a file the user picked — the domain never learns
  /// what a file system is.
  final String source;

  /// What the shape is expected to show, for the synthetic cases. Empty for a
  /// user's own CSV, and empty means exactly "nothing is being claimed about
  /// this", not "unknown".
  final String note;

  /// [messageBalanceMetric] or [syntheticEventIndexMetric].
  final String metric;

  /// How many messages the whole trend was built from.
  int get messages =>
      candles.fold(0, (int total, Candle candle) => total + candle.count);
}

/// One synthetic case: an id, a title, and the chat file it reads.
final class DemoCase {
  const DemoCase({required this.id, required this.title, required this.chat});

  final String id;
  final String title;

  /// The chat file's name inside [caseBundleDir].
  final String chat;
}

/// Reads a chat CSV — `timestamp,sender,message`, sorted ascending — into a trend.
///
/// It takes bytes rather than a path because the domain has no file system
/// (ADR-0009): the application picks the file and reads it, and everything the
/// ports did *after* the read happens here, once. Taking bytes is also what keeps
/// the size ceiling and the encoding refusal inside the single implementation
/// instead of in each of three apps.
///
/// **Nothing is inferred.** A sender must already be `me` or `other`: all three
/// ports required that on the CSV path, and the case bundle's own README says why
/// — the two sides are fixed and must not be re-guessed from bubble side or tone.
/// The CSV is the one place the user states it, so it is the one place it is
/// taken from. A day that shows no messages does not become a candle either, so
/// the x axis is days with evidence rather than a calendar.
Trend readChatCsv(
  Uint8List bytes, {
  required TrendRules rules,
  String title = '导入的聊天记录',
  String source = '',
}) {
  final List<List<String>> rows = parseCsvGrid(_decode(bytes, rules, '聊天 CSV'));
  if (rows.length < 2) {
    throw const DomainException('聊天 CSV 没有可分析的聊天记录');
  }

  final List<String> header =
      rows.first.map((String cell) => cell.trim()).toList(growable: false);
  final List<int> positions = <int>[
    for (final String column in rules.columns) header.indexOf(column),
  ];
  if (positions.any((int index) => index < 0)) {
    throw DomainException(
        '聊天 CSV 需要包含 ${rules.columns.length} 列：${rules.columns.join(',')}');
  }
  final int eventColumn = header.indexOf('event');

  // Counted before the walk, because the ceiling exists to stop the walk.
  if (rows.length - 1 > rules.maxMessages) {
    throw DomainException('聊天记录超过 ${rules.maxMessages} 条，请缩小时间范围');
  }

  final List<Candle> candles = <Candle>[];
  int balance = 0;
  DateTime? previous;

  for (final List<String> row in rows.skip(1)) {
    final DateTime at = _timestamp(_cell(row, positions[0]).trim(), rules);
    if (previous != null && at.isBefore(previous)) {
      throw const DomainException('聊天时间没有按升序排列');
    }
    previous = at;

    final String sender = _cell(row, positions[1]).trim();
    if (!rules.senders.contains(sender)) {
      throw DomainException(
          'sender 只接受 ${rules.senders.join('／')}；请先确认双方身份');
    }
    if (_cell(row, positions[2]).trim().isEmpty) {
      throw const DomainException('存在空消息，请先核对导出文件');
    }

    final String date = at.toIso8601String().substring(0, 10);
    if (candles.isEmpty || candles.last.date != date) {
      candles.add(Candle(
        date: date,
        open: balance,
        high: balance,
        low: balance,
        close: balance,
      ));
    }
    balance += sender == senderOther ? 1 : -1;

    final Candle current = candles.last;
    final List<String> events = <String>[...current.events];
    if (eventColumn >= 0) {
      final String event = _cell(row, eventColumn).trim();
      if (event.isNotEmpty) {
        if (event.length > rules.maxEventChars) {
          throw DomainException(
              '事件标注过长，请控制在 ${rules.maxEventChars} 字以内');
        }
        // One annotation is one line. Refusing a break here is what lets the
        // export join a day's events with a line break and read them back
        // unchanged, so the round trip is exact rather than nearly exact.
        if (event.contains('\n') || event.contains('\r')) {
          throw const DomainException('事件标注不能包含换行');
        }
        events.add(event);
      }
    }

    candles[candles.length - 1] = current.copyWith(
      high: balance > current.high ? balance : current.high,
      low: balance < current.low ? balance : current.low,
      close: balance,
      mine: current.mine + (sender == senderMe ? 1 : 0),
      other: current.other + (sender == senderOther ? 1 : 0),
      events: events,
    );
  }

  return Trend(title: title, candles: candles, source: source);
}

/// Writes a trend's candles as the table [readCandleCsv] reads back.
///
/// **This direction is new.** The three ports only ever imported: a user brought
/// a chat export in and looked at the chart. Export is being added here because
/// the chart's own data should be able to leave the application — and because a
/// contract with only one direction cannot be shown to round-trip.
///
/// The table is the *computed* shape, not the chat's. Import and export are not
/// inverses of each other and cannot be: a conversation does not survive being
/// reduced to daily balances, because the dates collapse and every message's text
/// is gone. What round-trips exactly is a candle table, and the test says so.
Uint8List writeCandleCsv(Iterable<Candle> candles) {
  final List<Candle> all = candles.toList(growable: false);
  for (final Candle candle in all) {
    // The writer refuses what it could not write back. A break inside an
    // annotation would come home as two annotations, which is a silent edit to
    // the user's data; both readers already enforce one line per annotation, so
    // this can only fire on a candle assembled by hand.
    if (candle.events.any((String event) =>
        event.contains('\n') || event.contains('\r'))) {
      throw const DomainException('事件标注不能包含换行：同一天的多个标注以换行分隔');
    }
  }
  final String text = writeCsvGrid(<List<String>>[
    candleTableColumns,
    for (final Candle candle in all)
      <String>[
        candle.date,
        '${candle.open}',
        '${candle.high}',
        '${candle.low}',
        '${candle.close}',
        '${candle.mine}',
        '${candle.other}',
        // A day's annotations travel as one quoted multi-line field. That is
        // ordinary RFC 4180 — a quoted field may hold a line break — and it is
        // why readChatCsv refuses an annotation that contains one.
        candle.events.join('\n'),
      ],
  ]);
  return utf8.encode(text);
}

/// Reads back a candle table written by [writeCandleCsv].
///
/// `date,open,high,low,close` are required; `mine`, `other` and `event` are
/// optional, so a table someone trimmed by hand still reads as long as the
/// candle itself is intact.
List<Candle> readCandleCsv(Uint8List bytes, {required TrendRules rules}) {
  final List<List<String>> rows = parseCsvGrid(_decode(bytes, rules, 'K 线 CSV'));
  if (rows.length < 2) {
    throw const DomainException('K 线 CSV 没有可读的 K 线');
  }

  final List<String> header =
      rows.first.map((String cell) => cell.trim()).toList(growable: false);
  const List<String> required = <String>['date', 'open', 'high', 'low', 'close'];
  if (required.any((String column) => !header.contains(column))) {
    throw DomainException('K 线 CSV 需要包含 ${required.join(',')} 列');
  }
  final int eventColumn = header.indexOf('event');
  final int mineColumn = header.indexOf('mine');
  final int otherColumn = header.indexOf('other');

  final List<Candle> candles = <Candle>[];
  for (final List<String> row in rows.skip(1)) {
    // Days, capped by the same ceiling as messages: it is the same promise about
    // how much a single import may cost, and a table of days is bounded by it.
    if (candles.length >= rules.maxMessages) {
      throw DomainException('K 线超过 ${rules.maxMessages} 天，请缩小时间范围');
    }
    final String date = _date(_cell(row, header.indexOf('date')).trim());
    final int open = _integer(row, header.indexOf('open'), 'open', date);
    final int high = _integer(row, header.indexOf('high'), 'high', date);
    final int low = _integer(row, header.indexOf('low'), 'low', date);
    final int close = _integer(row, header.indexOf('close'), 'close', date);
    if (!isWellFormedCandle(open: open, high: high, low: low, close: close)) {
      throw DomainException('K 线 $date 的开高低收不正确：最低应不高于开收，最高应不低于开收');
    }
    if (candles.isNotEmpty && candles.last.date.compareTo(date) >= 0) {
      throw const DomainException('K 线日期必须严格递增：一天只有一根');
    }
    candles.add(Candle(
      date: date,
      open: open,
      high: high,
      low: low,
      close: close,
      mine: _optionalInteger(row, mineColumn, 0, 'mine', date),
      other: _optionalInteger(row, otherColumn, 0, 'other', date),
      events: eventColumn < 0
          ? const <String>[]
          : <String>[
              for (final String event
                  in _cell(row, eventColumn).split('\n'))
                if (event.trim().isNotEmpty) event.trim(),
            ],
    ));
  }
  return candles;
}

/// The synthetic cases the trend page offers before a user has a CSV of their own.
///
/// The list comes from the payload's manifest rather than from a constant here,
/// so adding a case is a payload change and the picker follows it.
Future<List<DemoCase>> readDemoCases(SharedMaterial material) async {
  final List<Object?> entries = _array(
      (await _manifest(material))['cases'], 'cases', 'manifest.json');
  return <DemoCase>[
    for (final Object? entry in entries) _demoCase(_object(entry, 'manifest.json')),
  ];
}

/// Loads one synthetic case: its chat, its illustrative candles, its key events.
///
/// All three parts are used, which is the macOS port's shape and the superset of
/// the other two. Windows and Android drew the illustrative candles on their own
/// and stopped there; macOS also merged the manifest's `key_events` into the
/// candles and refused a bundle whose candles did not line up with the chat. That
/// check is the valuable half: the illustrative candles are hand-written, so
/// without it a case could show a shape its own chat does not support, and the
/// page's whole claim is that the shape rests on the evidence.
Future<Trend> readDemoCase(
  SharedMaterial material,
  String caseId, {
  required TrendRules rules,
}) async {
  final Map<String, Object?> manifest = await _manifest(material);
  final List<Object?> entries = _array(manifest['cases'], 'cases', 'manifest.json');
  final Map<String, Object?>? entry = _findCase(entries, caseId);
  if (entry == null) {
    throw const DomainException('没有这个合成案例');
  }

  final String chatFile = _string(entry['csv'], 'csv', 'manifest.json');
  final String chatPath = '$caseBundleDir/$chatFile';
  final Trend trend = readChatCsv(
    utf8.encode(await material.text(chatPath)),
    rules: rules,
    title: '${_string(entry['title'], 'title', 'manifest.json')} · 合成示例',
    source: chatPath,
  );

  final Map<String, Object?> illustrative =
      _object(await _json(material, '$caseBundleDir/demo_kline.json'), 'demo_kline.json');
  final Object? rows =
      _object(illustrative['cases'], 'demo_kline.json')[caseId];
  if (rows == null) {
    throw const DomainException('没有这个合成案例的 K 线');
  }
  final List<Object?> candles = _array(rows, caseId, 'demo_kline.json');
  if (candles.length != trend.candles.length) {
    throw const DomainException('合成 K 线与聊天日期不匹配');
  }

  final Map<String, List<String>> events = <String, List<String>>{};
  for (final Object? raw in _array(entry['key_events'], 'key_events', 'manifest.json')) {
    final Map<String, Object?> event = _object(raw, 'manifest.json');
    final String at = _string(event['at'], 'at', 'manifest.json');
    events
        .putIfAbsent(at.substring(0, 10), () => <String>[])
        .add(_string(event['evidence'], 'evidence', 'manifest.json'));
  }

  final List<Candle> merged = <Candle>[];
  int? previousClose;
  for (int index = 0; index < candles.length; index++) {
    final List<Object?> row = _array(candles[index], caseId, 'demo_kline.json');
    if (row.length != 5) {
      throw const DomainException('合成 K 线的每根应是 日期,开,高,低,收 五个值');
    }
    final Candle source = trend.candles[index];
    final String date = _string(row[0], caseId, 'demo_kline.json');
    final int open = _int(row[1], caseId, 'demo_kline.json');
    final int high = _int(row[2], caseId, 'demo_kline.json');
    final int low = _int(row[3], caseId, 'demo_kline.json');
    final int close = _int(row[4], caseId, 'demo_kline.json');
    if (date != source.date ||
        (previousClose != null && open != previousClose) ||
        low < 0 ||
        high > 100 ||
        !isWellFormedCandle(open: open, high: high, low: low, close: close)) {
      throw const DomainException('合成 K 线开高低收格式不正确');
    }
    merged.add(source.copyWith(
      open: open,
      high: high,
      low: low,
      close: close,
      events: <String>[...source.events, ...?events[date]],
    ));
    previousClose = close;
  }

  return Trend(
    title: trend.title,
    candles: merged,
    source: trend.source,
    note: _string(entry['expected_pattern'], 'expected_pattern', 'manifest.json'),
    metric: syntheticEventIndexMetric,
  );
}

Future<Map<String, Object?>> _manifest(SharedMaterial material) async =>
    _object(await _json(material, '$caseBundleDir/manifest.json'), 'manifest.json');

/// The manifest row whose `id` is [caseId], or null.
Map<String, Object?>? _findCase(List<Object?> entries, String caseId) {
  for (final Object? raw in entries) {
    final Map<String, Object?> entry = _object(raw, 'manifest.json');
    if (entry['id'] == caseId) {
      return entry;
    }
  }
  return null;
}

DemoCase _demoCase(Map<String, Object?> entry) => DemoCase(
      id: _string(entry['id'], 'id', 'manifest.json'),
      title: _string(entry['title'], 'title', 'manifest.json'),
      chat: _string(entry['csv'], 'csv', 'manifest.json'),
    );

Future<Object?> _json(SharedMaterial material, String path) async =>
    jsonDecode(await material.text(path));

/// Decodes bytes, enforcing the size ceiling and refusing a broken encoding.
///
/// The size is checked on the bytes rather than on the decoded text because that
/// is what the ceiling has always meant — it exists so a mis-picked file is
/// rejected before it is parsed, and a file's size is not a property of its
/// characters.
String _decode(Uint8List bytes, TrendRules rules, String label) {
  if (bytes.length > rules.maxBytes) {
    throw DomainException(
        '$label 超过 ${rules.maxBytes ~/ 1000000} MB，请缩小时间范围后重试');
  }
  try {
    return utf8.decode(bytes);
  } on FormatException {
    throw DomainException('$label 无法读取，请检查编码、列名和时间格式');
  }
}

/// A cell, or the empty string when the row is shorter than the header.
///
/// Tolerating a short row is deliberate: Python's `DictReader` returns `None` for
/// a column the row does not have, and the ports that read CSVs that way went on
/// to report the *missing value* — "存在空消息", "timestamp 需要 …" — which is a
/// better sentence than "这一行太短". Android refused the row outright, and that
/// stricter reading is the one divergence this convergence drops.
String _cell(List<String> row, int index) =>
    index >= 0 && index < row.length ? row[index] : '';

/// A `YYYY-MM-DD HH:MM:SS` timestamp, or the refusal that names the format.
///
/// The shape is checked before the parse and the fields are compared back after
/// it, because `DateTime.parse` rolls an impossible value into the next unit: it
/// reads `2026-02-30` as March 2 and `24:00:00` as the next midnight. A timestamp
/// that names a day that does not exist is not a timestamp, and accepting it
/// would put a candle on a date the conversation never had.
DateTime _timestamp(String value, TrendRules rules) {
  final RegExpMatch? match = _timestampShape.firstMatch(value);
  if (match == null) {
    throw DomainException('timestamp 需要 ${rules.timestampFormat} 格式');
  }
  final DateTime parsed = DateTime.parse(
      '${match[1]}-${match[2]}-${match[3]}T${match[4]}:${match[5]}:${match[6]}');
  final bool intact = parsed.year == int.parse(match[1]!) &&
      parsed.month == int.parse(match[2]!) &&
      parsed.day == int.parse(match[3]!) &&
      parsed.hour == int.parse(match[4]!) &&
      parsed.minute == int.parse(match[5]!) &&
      parsed.second == int.parse(match[6]!);
  if (!intact) {
    throw DomainException('timestamp 需要 ${rules.timestampFormat} 格式');
  }
  return parsed;
}

/// A `YYYY-MM-DD` date, refused if it is not one.
String _date(String value) {
  final RegExpMatch? match = _dateShape.firstMatch(value);
  if (match == null ||
      DateTime.parse(value).toIso8601String().substring(0, 10) != value) {
    throw DomainException('K 线日期需要 YYYY-MM-DD 格式：$value');
  }
  return value;
}

int _integer(List<String> row, int index, String column, String date) {
  final int? value = int.tryParse(_cell(row, index).trim());
  if (value == null) {
    throw DomainException('K 线 $date 的 $column 不是整数');
  }
  return value;
}

int _optionalInteger(
    List<String> row, int index, int fallback, String column, String date) {
  if (index < 0 || _cell(row, index).trim().isEmpty) {
    return fallback;
  }
  return _integer(row, index, column, date);
}

final RegExp _timestampShape =
    RegExp(r'^(\d{4})-(\d{2})-(\d{2})[ T](\d{2}):(\d{2}):(\d{2})$');

final RegExp _dateShape = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');

Map<String, Object?> _object(Object? raw, String file) {
  if (raw is! Map) {
    throw DomainException('跨端公用文件 $file 格式不正确：期望一个 JSON 对象，得到 ${raw.runtimeType}');
  }
  return raw.cast<String, Object?>();
}

List<Object?> _array(Object? raw, String what, String file) {
  if (raw is! List) {
    throw DomainException('跨端公用文件 $file 的 $what 格式不正确：期望一个数组，得到 ${raw.runtimeType}');
  }
  return raw.cast<Object?>();
}

String _string(Object? raw, String what, String file) {
  if (raw is! String) {
    throw DomainException('跨端公用文件 $file 的 $what 格式不正确：期望一个字符串，得到 ${raw.runtimeType}');
  }
  return raw;
}

int _int(Object? raw, String what, String file) {
  if (raw is! int) {
    throw DomainException('跨端公用文件 $file 的 $what 格式不正确：期望一个整数，得到 ${raw.runtimeType}');
  }
  return raw;
}

List<String> _strings(Object? raw, String what, String file) => <String>[
      for (final Object? item in _array(raw, what, file)) _string(item, what, file),
    ];
