import 'package:miaotou_domain/miaotou_domain.dart';
import 'package:test/test.dart';

/// CSV is where the three ports quietly disagreed, so it is tested on its own
/// rather than only through the trend reader.
///
/// The two Python ports used the standard library's `csv` module and never had to
/// think about quoting; Android had no module and hand-wrote a parser. That makes
/// the edge cases below the ones nobody had a test for: each is a line where two
/// implementations would have chosen differently, and the choice is now written
/// down.
void main() {
  group('parsing', () {
    test('reads plain rows', () {
      expect(parseCsvGrid('a,b\nc,d\n'), <List<String>>[
        <String>['a', 'b'],
        <String>['c', 'd'],
      ]);
    });

    test('keeps a comma inside a quoted field', () {
      expect(parseCsvGrid('a,"b,c"\n'), <List<String>>[
        <String>['a', 'b,c'],
      ]);
    });

    test('reads a doubled quote as one literal quote', () {
      expect(parseCsvGrid('a,"say ""hi"""\n'), <List<String>>[
        <String>['a', 'say "hi"'],
      ]);
    });

    test('keeps a line break inside a quoted field', () {
      // This is the case the export depends on: a day's annotations travel as one
      // quoted field whose separator is a newline.
      expect(parseCsvGrid('a,"one\ntwo",c\n'), <List<String>>[
        <String>['a', 'one\ntwo', 'c'],
      ]);
    });

    test('accepts CRLF, bare CR and LF as row ends', () {
      const List<String> rows = <String>['a,b\r\n', 'a,b\r', 'a,b\n'];
      for (final String text in rows) {
        expect(parseCsvGrid(text), <List<String>>[
          <String>['a', 'b'],
        ], reason: 'rejected ${text.replaceAll('\r', r'\r').replaceAll('\n', r'\n')}');
      }
    });

    test('drops a UTF-8 BOM, the way utf-8-sig did', () {
      expect(parseCsvGrid('\uFEFFa,b\n'), <List<String>>[
        <String>['a', 'b'],
      ]);
    });

    test('does not invent a row for the trailing newline', () {
      expect(parseCsvGrid('a,b\nc,d\n\n'), hasLength(2));
    });

    test('treats an all-blank row as no row at all', () {
      // Python's DictReader skipped a truly empty line but reported a line of
      // bare commas as a row of empty values; Android skipped both. Skipping both
      // is the choice, because "存在空消息" is the wrong sentence for a line that
      // simply holds nothing.
      expect(parseCsvGrid('a,b\n\n,\n   \n'), <List<String>>[
        <String>['a', 'b'],
      ]);
      // A row with any content on it is a row, spaces and all — the callers trim,
      // this layer does not.
      expect(parseCsvGrid('a,b\n c \n'), <List<String>>[
        <String>['a', 'b'],
        <String>[' c '],
      ]);
    });

    test('keeps a quote that is not at the start of a field as a literal', () {
      // Android toggled on any quote and read `a"b` as `ab`.
      expect(parseCsvGrid('a"b\n'), <List<String>>[
        <String>['a"b'],
      ]);
      expect(parseCsvGrid('"a"b\n'), <List<String>>[
        <String>['ab'],
      ]);
    });

    test('refuses a quote left open rather than closing it at the end', () {
      // Closing it silently would swallow every row after it into one field.
      expect(
        () => parseCsvGrid('a,"b\nc,d\n'),
        throwsA(isA<DomainException>()),
      );
    });

    test('keeps a row whose last field is empty', () {
      expect(parseCsvGrid('a,b,\n'), <List<String>>[
        <String>['a', 'b', ''],
      ]);
    });
  });

  group('writing', () {
    test('quotes only the fields that need it', () {
      expect(writeCsvGrid(<List<String>>[
        <String>['a', 'b'],
      ]), 'a,b\n');
      expect(writeCsvGrid(<List<String>>[
        <String>['a,b', 'c'],
      ]), '"a,b",c\n');
      expect(writeCsvGrid(<List<String>>[
        <String>['say "hi"'],
      ]), '"say ""hi"""\n');
      expect(writeCsvGrid(<List<String>>[
        <String>['one\ntwo'],
      ]), '"one\ntwo"\n');
    });

    test('writes the line break this repository\'s own CSVs use', () {
      expect(writeCsvGrid(<List<String>>[
        <String>['a'],
        <String>['b'],
      ]), 'a\nb\n');
    });
  });

  group('round trip', () {
    test('every awkward field survives being written and read back', () {
      final List<List<String>> rows = <List<String>>[
        <String>['plain', 'with,comma', 'with "quote"'],
        <String>['with\nbreak', '', ' trailing '],
        <String>['",\n"', 'a"b', '\uFEFFnot-a-bom'],
      ];
      expect(parseCsvGrid(writeCsvGrid(rows)), rows);
    });
  });
}
