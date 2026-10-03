import 'dart:io';

import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

/// ADR-0009 gives the domain package one property worth guarding: **it has no
/// platform.**
///
/// The property is what makes the whole split pay. A domain that could reach a
/// platform would sprout `if (Platform.isAndroid)` the first time a port behaved
/// differently, and the contract would stop being the only place the three ports
/// differ. And a domain with no platform is testable with `dart test` in
/// milliseconds, on any machine, with no device attached — which is the only
/// reason the business logic can have a fast test suite at all.
///
/// The two tests below turn that sentence into something the compiler and the
/// analyzer are not already enforcing.
void main() {
  late Map<Object?, Object?> document;
  late Directory package;

  setUpAll(() {
    package = Directory.current.absolute;
    final File pubspec = File('${package.path}/pubspec.yaml');
    expect(pubspec.existsSync(), isTrue, reason: 'run from the package directory');
    document = loadYaml(pubspec.readAsStringSync()) as Map<Object?, Object?>;
    expect(document['name'], 'miaotou_domain');
  });

  test('nothing in lib/ imports a platform or a platform package', () {
    const List<String> forbiddenLibraries = <String>[
      'package:flutter/',
      'dart:io',
      'dart:ui',
      'dart:ffi',
    ];
    const List<String> platformPackages = <String>[
      'package:miaotou_capabilities_android/',
      'package:miaotou_capabilities_macos/',
      'package:miaotou_capabilities_windows/',
    ];

    final List<String> offenders = <String>[];
    for (final File file in _dartFiles(Directory('${package.path}/lib'))) {
      final List<String> lines = file.readAsLinesSync();
      for (int i = 0; i < lines.length; i++) {
        final String line = lines[i].trimLeft();
        if (!line.startsWith('import ') && !line.startsWith('export ')) {
          continue;
        }
        for (final String needle in <String>[
          ...forbiddenLibraries,
          ...platformPackages,
        ]) {
          if (line.contains("'$needle") || line.contains('"$needle')) {
            offenders.add('${file.path}:${i + 1}  $line');
          }
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'the domain decides; the platform layer observes and acts. A '
          'platform need here is a capability the contract is missing, and the '
          'fix belongs in miaotou_capabilities (ADR-0009)',
    );
  });

  test('the package declares no platform dependency', () {
    final Map<Object?, Object?> dependencies =
        (document['dependencies'] as Map<Object?, Object?>?) ??
            const <Object?, Object?>{};

    expect(
      dependencies.keys.map((Object? key) => '$key').where(
            (String name) => name.startsWith('miaotou_capabilities_'),
          ),
      isEmpty,
    );
    expect(dependencies.keys, isNot(contains('flutter')));
    expect(
      dependencies.keys,
      contains('miaotou_capabilities'),
      reason: 'the domain consumes the contract; that edge is the point of the '
          'split, and losing it would mean the domain stopped using the seam',
    );
  });
}

List<File> _dartFiles(Directory directory) {
  if (!directory.existsSync()) {
    return const <File>[];
  }
  final List<File> files = <File>[
    for (final FileSystemEntity entity in directory.listSync(recursive: true))
      if (entity is File && entity.path.endsWith('.dart')) entity,
  ]..sort((File a, File b) => a.path.compareTo(b.path));
  return files;
}
