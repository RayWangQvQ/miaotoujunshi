/// CSV, as RFC 4180, implemented once for the whole application.
///
/// Dart's core libraries have no CSV reader and no CSV writer, so this could not
/// be a port of one function: it had to be written somewhere. Where it is written
/// matters, because the three ports brought three answers. The two Python ports
/// used the standard library's `csv` module, which quietly covers the hard cases;
/// Android has no equivalent, so `core/TrendData.kt` hand-wrote a parser, and in
/// doing so became the only port that had to **state** the rules. What follows is
/// that parser's rules, generalised, because they are the standard ones and
/// because a rule that is written down can be tested:
///
/// * A field may be quoted with `"`. Inside a quoted field a comma, a line break
///   and a doubled `""` (meaning one literal `"`) are all ordinary characters.
/// * A quote opens a quoted field only **at the start of a field**. A bare `"`
///   inside unquoted text stays a literal quote, which is what Python's reader
///   does; Android toggled on any quote and so read `a"b` as `ab`.
/// * A row ends at CRLF, LF or CR, and a file may begin with a UTF-8 BOM. The
///   material this repository ships is checked in by hand and has been edited on
///   three operating systems, so a reader that only accepted LF would be a reader
///   that only accepted the author's machine.
/// * A row whose fields are all blank is not a row. Python's `DictReader` skips a
///   truly empty line; this also skips a line of bare commas, because the
///   alternative is to report "存在空消息" about a line that holds nothing.
///
/// This file knows nothing about chats or candles. It is the layer both of them
/// sit on, which is the whole of what "one implementation" means here.
library;

import 'errors.dart';

/// Parses CSV text into rows of fields.
///
/// Quotes are removed and escapes resolved: what comes back is the values. A
/// quote left open is refused rather than closed at the end of the file, because
/// guessing where it was meant to end would silently swallow every row after it.
List<List<String>> parseCsvGrid(String text) {
  final String source = text.startsWith('\uFEFF') ? text.substring(1) : text;
  final List<List<String>> rows = <List<String>>[];
  final List<String> row = <String>[];
  final StringBuffer field = StringBuffer();
  bool quoted = false;
  int index = 0;

  void endField() {
    row.add(field.toString());
    field.clear();
  }

  void endRow() {
    endField();
    if (row.any((String value) => value.trim().isNotEmpty)) {
      rows.add(List<String>.of(row));
    }
    row.clear();
  }

  while (index < source.length) {
    final String character = source[index];
    if (quoted) {
      if (character != '"') {
        field.write(character);
        index += 1;
      } else if (index + 1 < source.length && source[index + 1] == '"') {
        field.write('"');
        index += 2;
      } else {
        quoted = false;
        index += 1;
      }
      continue;
    }
    if (character == '"' && field.length == 0) {
      quoted = true;
      index += 1;
    } else if (character == ',') {
      endField();
      index += 1;
    } else if (character == '\r' || character == '\n') {
      if (character == '\r' &&
          index + 1 < source.length &&
          source[index + 1] == '\n') {
        index += 1;
      }
      endRow();
      index += 1;
    } else {
      field.write(character);
      index += 1;
    }
  }

  if (quoted) {
    throw const DomainException('CSV 引号没有闭合');
  }
  if (field.length > 0 || row.isNotEmpty) {
    endRow();
  }
  return rows;
}

/// Writes rows of fields as CSV text.
///
/// Rows are separated by `\n`, the line break this repository's own CSVs use, so
/// an exported file looks like the material it sits beside. A quoted field may
/// hold a line break of its own, which is why the reader has to accept all three
/// endings even though the writer only emits one.
String writeCsvGrid(Iterable<List<String>> rows) {
  final StringBuffer out = StringBuffer();
  for (final List<String> row in rows) {
    for (int index = 0; index < row.length; index++) {
      if (index > 0) {
        out.write(',');
      }
      out.write(_field(row[index]));
    }
    out.write('\n');
  }
  return out.toString();
}

/// One field, quoted only when it has to be.
///
/// Quoting every field would be legal and would make every exported file
/// harder to read by hand, which matters because this file is meant to be opened
/// in a spreadsheet *and* looked at in an editor.
String _field(String value) {
  final bool needsQuotes = value.contains(',') ||
      value.contains('"') ||
      value.contains('\n') ||
      value.contains('\r');
  if (!needsQuotes) {
    return value;
  }
  return '"${value.replaceAll('"', '""')}"';
}
