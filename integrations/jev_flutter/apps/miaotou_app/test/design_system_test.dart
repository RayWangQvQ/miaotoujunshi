import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:miaotou_app/src/design/colors.dart';
import 'package:miaotou_app/src/design/copy.dart';
import 'package:miaotou_app/src/design/spacing.dart';
import 'package:miaotou_app/src/design/theme.dart';

/// The three things #11 says must exist once, and the three ways they stop
/// existing once.
///
/// "Colour semantics, spacing and copy keys exist once and every page uses them"
/// is easy to intend and easy to break: a page reaches for `Colors.red`, or for
/// `EdgeInsets.all(12)`, or for a Chinese string that felt too small to be worth
/// a key, and the drift the migration exists to remove starts again in the new
/// codebase. The first two tests here check the tokens themselves; the last four
/// read every file under `lib/` and refuse the shortcuts.
///
/// A source scan is the right instrument for this and not a lazy one: the
/// property is about where a value is *written*, and no amount of pumping
/// widgets can see the difference between a colour that came from the palette
/// and a colour that happens to be the same number.
void main() {
  late Directory package;

  setUpAll(() {
    package = Directory.current.absolute;
    expect(File('${package.path}/pubspec.yaml').existsSync(), isTrue,
        reason: 'run from the application directory');
  });

  group('the palette', () {
    test('the values a reader must not confuse are not the same value', () {
      final AppColors colors = AppColors.light();
      final List<String> collapsed = <String>[];

      for (final (String a, String b) in AppColors.distinctPairs) {
        if (colors.byName(a) == colors.byName(b)) {
          collapsed.add('$a == $b');
        }
      }

      expect(collapsed, isEmpty,
          reason: 'each of these pairs is two different statements; a reader '
              'who sees them as one colour cannot tell a rising balance from a '
              'failed step, or my line from theirs');
    });

    test('the theme carries the palette, so a page cannot invent one', () {
      expect(buildTheme().extension<AppColors>(), isA<AppColors>(),
          reason: 'AppColors.of throws without it, and a page that silently '
              'fell back to a default would be a page nobody chose the colour of');
    });
  });

  group('the spacing scale', () {
    test('is one ordered set of steps', () {
      final List<double> steps = <double>[
        AppSpacing.xs,
        AppSpacing.s,
        AppSpacing.m,
        AppSpacing.l,
        AppSpacing.xl,
        AppSpacing.xxl,
        AppSpacing.xxxl,
      ];
      for (int i = 1; i < steps.length; i++) {
        expect(steps[i], greaterThan(steps[i - 1]),
            reason: 'a scale whose steps are out of order is two scales');
      }
    });

    test('the two breakpoints are ordered', () {
      expect(AppBreakpoint.extendedRail, greaterThan(AppBreakpoint.rail));
    });
  });

  group('the copy', () {
    test('every key has a string, and none is empty', () {
      final List<String> holes = <String>[
        for (final CopyKey key in CopyKey.values)
          if (!AppCopy.zh.keys.contains(key) ||
              AppCopy.zh.text(key).trim().isEmpty)
            key.name,
      ];

      expect(holes, isEmpty,
          reason: 'a key with no string is a page that falls back to a literal, '
              'and an empty string is a label the reader has to guess');
    });

    test('the sentinel covers every key with the marker', () {
      const String marker = '·';
      final AppCopy copy = AppCopy.sentinel(marker);

      expect(copy.keys.toSet(), CopyKey.values.toSet());
      expect(copy.values.toSet(), <String>{marker},
          reason: 'the audit replaces every string with one marker; a key left '
              'out would be an unmarked string on the page and invisible to it');
    });

    test('a copy that is missing a key says so rather than returning empty', () {
      const AppCopy partial = AppCopy(<CopyKey, String>{CopyKey.appTitle: 'x'});

      expect(() => partial.text(CopyKey.navDetail), throwsStateError);
    });
  });

  group('nothing in lib/ reaches past the design directory', () {
    test('no Chinese string literal outside design/copy.dart', () {
      final List<String> offenders = <String>[];
      // A quoted run containing a Han character, in either quote style.
      final RegExp cjk = RegExp(
        r"'[^'\n]*[\u4e00-\u9fff][^'\n]*'" r'|"[^"\n]*[\u4e00-\u9fff][^"\n]*"',
      );

      for (final File file in _dartFiles(Directory('${package.path}/lib'))) {
        if (file.path.endsWith('design/copy.dart')) {
          continue;
        }
        offenders.addAll(_linesMatching(file, cjk));
      }

      expect(offenders, isEmpty,
          reason: 'a string a person reads has one home, and it is '
              'design/copy.dart; a literal here is a second source of truth '
              'for what the screen says');
    });

    test('no raw colour outside design/', () {
      final List<String> offenders = <String>[];
      // `AppColors.of` is the point of the palette and must not match; the
      // character before `Colors` is the way to tell the two apart.
      final RegExp raw = RegExp(r'[^A-Za-z](?:Colors\.|Color\(0x)');

      for (final File file in _dartFiles(Directory('${package.path}/lib'))) {
        if (file.path.contains('/design/')) {
          continue;
        }
        offenders.addAll(_linesMatching(file, raw));
      }

      expect(offenders, isEmpty,
          reason: 'a colour written at the point of use is a decision nobody '
              'can audit; ask AppColors for the role instead');
    });

    test('no raw inset outside design/', () {
      final List<String> offenders = <String>[];
      final RegExp raw = RegExp(r'EdgeInsets[A-Za-z]*\(\s*\d');

      for (final File file in _dartFiles(Directory('${package.path}/lib'))) {
        if (file.path.contains('/design/')) {
          continue;
        }
        offenders.addAll(_linesMatching(file, raw));
      }

      expect(offenders, isEmpty,
          reason: 'padding by number is padding by accident; AppSpacing exists '
              'so the gap between two cards is one decision');
    });

    test('no platform branching outside the capability registry', () {
      final List<String> offenders = <String>[];
      final RegExp platform = RegExp(r'Platform\.|defaultTargetPlatform|dart:io');

      for (final File file in _dartFiles(Directory('${package.path}/lib'))) {
        if (file.path.endsWith('capability_registry.dart')) {
          continue;
        }
        offenders.addAll(_linesMatching(file, platform));
      }

      expect(offenders, isEmpty,
          reason: 'the layout follows the window, not the port; a page that '
              'asks which platform it is on is a page the three ports will '
              'grow three answers for (ADR-0009)');
    });
  });
}

/// Every offending line of one file, as `path:line: text`, so a failure tells
/// you where to look rather than that something is somewhere.
List<String> _linesMatching(File file, RegExp pattern) {
  final List<String> lines = _stripComments(file.readAsStringSync()).split('\n');
  final List<String> found = <String>[];
  for (int i = 0; i < lines.length; i++) {
    if (pattern.hasMatch(lines[i])) {
      found.add('${file.path}:${i + 1}: ${lines[i].trim()}');
    }
  }
  return found;
}

List<File> _dartFiles(Directory directory) {
  if (!directory.existsSync()) {
    return const <File>[];
  }
  return <File>[
    for (final FileSystemEntity entity in directory.listSync(recursive: true))
      if (entity is File && entity.path.endsWith('.dart')) entity,
  ]..sort((File a, File b) => a.path.compareTo(b.path));
}

/// Comments out, so that a Chinese phrase quoted in a doc comment is not read as
/// a string literal. Block comments go first, then line comments.
String _stripComments(String source) {
  final String noBlocks = source.replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '');
  return noBlocks
      .split('\n')
      .map((String line) => line.replaceAll(RegExp(r'//.*'), ''))
      .join('\n');
}
