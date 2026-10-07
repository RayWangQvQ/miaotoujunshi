import 'dart:io';

import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

/// This package has one property worth guarding: **it has no platform.**
///
/// It exists because three ports had written the same platform-free modules three
/// times, and the duplication is what let them drift — Android's memory store kept
/// its undo stack in memory while the two desktop ports wrote it to the file, each
/// of the three refused a corrupt document in its own words, and two of them
/// accepted a malformed row that the third silently dropped. Sharing the module is
/// what removes the drift; a module here that reached a platform would put the
/// divergence straight back, because the first port whose platform answered
/// differently would grow a branch.
///
/// The rule the analyzer cannot state is the *negative* one: `dart:io` is not
/// forbidden because it is dangerous, but because a module that takes a path is a
/// module that has taken a platform decision, and this package is the place where
/// those decisions are not allowed to live.
void main() {
  late Map<Object?, Object?> document;
  late Directory package;

  setUpAll(() {
    package = Directory.current.absolute;
    final File pubspec = File('${package.path}/pubspec.yaml');
    expect(pubspec.existsSync(), isTrue, reason: 'run from the package directory');
    document = loadYaml(pubspec.readAsStringSync()) as Map<Object?, Object?>;
    expect(document['name'], 'miaotou_capabilities_shared');
  });

  test('nothing in lib/ imports a platform, Flutter or a platform package', () {
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
      reason: 'this package holds the half of the implementations that does not '
          'differ by platform. Reaching a platform from here is how the three '
          'copies drifted apart in the first place; the platform call belongs in '
          'the port package, behind the seam this package declares',
    );
  });

  test('the package declares no platform dependency', () {
    final Map<Object?, Object?> dependencies =
        (document['dependencies'] as Map<Object?, Object?>?) ??
            const <Object?, Object?>{};

    expect(
      dependencies.keys
          .map((Object? key) => '$key')
          .where((String name) => name.startsWith('miaotou_capabilities_')),
      isEmpty,
    );
    expect(dependencies.keys, isNot(contains('flutter')));
    expect(
      dependencies.keys,
      contains('miaotou_capabilities'),
      reason: 'the modules here implement the contract members; losing this edge '
          'would mean the shared half stopped answering to the interfaces',
    );
  });

  test('the arrow never inverts: no package above this one depends on it', () {
    // The contract and the domain are the two packages this one must never be
    // reachable from. `miaotou_capabilities` is the interface package it sits
    // under, and `miaotou_domain` is above the seam entirely (ADR-0009 decision
    // 1); either edge would mean a piece of a port had leaked upwards, which is
    // the direction ADR-0009 exists to forbid.
    for (final String neighbour in <String>[
      'miaotou_capabilities',
      'miaotou_domain',
    ]) {
      final File pubspec = File('${package.parent.path}/$neighbour/pubspec.yaml');
      expect(
        pubspec.existsSync(),
        isTrue,
        reason: 'expected a sibling package at ${pubspec.path}',
      );
      final Map<Object?, Object?> neighbourDocument =
          loadYaml(pubspec.readAsStringSync()) as Map<Object?, Object?>;
      final Map<Object?, Object?> dependencies =
          (neighbourDocument['dependencies'] as Map<Object?, Object?>?) ??
              const <Object?, Object?>{};
      expect(
        dependencies.keys,
        isNot(contains('miaotou_capabilities_shared')),
        reason: '$neighbour must not depend on the shared implementation bodies',
      );
    }
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
