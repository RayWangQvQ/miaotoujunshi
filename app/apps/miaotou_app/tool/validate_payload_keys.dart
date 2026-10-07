// Assert every payload key the app can request is present in a built tree.
//
// The shared payload reaches a packaged application by being copied **whole**,
// and this script is what makes the copy trustworthy. It answers one question:
//
//     is every key the material interface can ask for actually inside the tree?
//
// ADR-0008 states the failure this replaces: the old macOS guard compared an
// allowlist against the files the runtime read, so a new payload file was
// invisible until a user pressed a button. The failure mode degraded from "the
// package step fails" to "the user presses a button and nothing happens", and
// this is the replacement for it.
//
// ## Why this is Dart and not Python
// ---------------------------------------------------------------------------
//
// ADR-0027. All three platform builds run this assertion — macOS from its sync
// build phase, Windows from the packaging step, Android from the Gradle task that
// fills `assets/` — and it used to run on Python 3, a runtime nothing else in this
// product asks for and one that has to be installed before anything can be
// packaged. Dart is already there: it is the language the app is written in, and
// the SDK arrives with Flutter. The assertion is now run by the SDK that builds
// the app, so the build has no interpreter to install.
//
// ## Why the key set is derived, never transcribed
// ---------------------------------------------------------------------------
//
// The keys are read from two places, neither of which is a hand-written list:
//
// * the domain layer's own constants, parsed out of the Dart source — the
//   alternative is a second copy of a path, and a second copy is exactly how
//   `references/` and `examples/` ended up with four disagreeing member lists in
//   ADR-0006;
// * `payload-map.json` itself, which is the single source for scene-to-file
//   selection (ADR-0006 decision 4).
//
// Transcribing either into this script would reintroduce the drift the derivation
// removes, so a guard test asserts the derivation is what runs.
//
// ## Usage
//
//     dart tool/validate_payload_keys.dart <repository-root> <packaged-root>
//
// `packaged-root` is the directory the payload tree was copied into — for macOS,
// `.app/Contents/Resources`. Exits non-zero and prints one line per missing key.

import 'dart:convert';
import 'dart:io';

// The Dart constants that are payload keys, as `const String name = 'value';`.
// The expression is anchored on the declaration so a mention of the name in a
// doc comment or a call site cannot be mistaken for the declaration itself.
final RegExp _constDeclaration = RegExp(
  r"^const\s+String\s+(\w*Path|\w*Dir)\s*=\s*'([^']+)'\s*;",
  multiLine: true,
);

// A file requested below a directory key, as `$caseBundleDir/manifest.json`.
final RegExp _directoryLiteralRead = RegExp(r'\$(\w*Dir)/([A-Za-z0-9_.-]+)');

// `SharedPayload.read` answers bytes and `SharedPayload.list` answers names, so a
// key is either a file or a directory and the assertion has to know which.
//
// The name is the only thing that tells them apart: `caseBundleDir` points at
// `…/examples/relationship_cases`, whose last path segment says nothing about it.
// Matching the *value* would classify every one of these keys as a file, and a
// file key asserted with a directory check would pass on an empty folder — which
// is the failure this whole script exists to make impossible.
final RegExp _keyIsDirectory = RegExp(r'Dir$');

// The files whose declarations are keys. Every one of them is a constant the
// domain reads the payload through; a file not listed here contributes no keys,
// and the guard test asserts the list is complete against what the domain reads.
// Relative to the **pub workspace root**, not the repository root: that is where
// the Dart sources live, and walking up from a build directory would have to know
// how deep the app sits inside the repository.
const String _workspace = 'app';

const List<String> _domainSources = <String>[
  '$_workspace/packages/miaotou_domain/lib/src/shared_material.dart',
  '$_workspace/packages/miaotou_domain/lib/src/relationship.dart',
  '$_workspace/packages/miaotou_domain/lib/src/trend.dart',
];

// `payload-map.json` holds the scene selection. Its own values are keys; the
// `_provenance` member is prose about the file and is not one.
const List<String> _mapStringKeys = <String>[
  'strategy_guide',
  'shared_tone_document',
  'entry_document',
];
const List<String> _mapMapKeys = <String>['scene_knowledge'];

const String _payloadMap = 'miaotoujunshi/references/data/payload-map.json';

// The tree cannot be judged at all, as opposed to judged and found short.
class _Failure implements Exception {
  const _Failure(this.message);

  final String message;

  @override
  String toString() => message;
}

// Every source and payload file, read as text.
//
// CRLF is folded to LF because Python's text mode did that implicitly and
// ADR-0027 moved this file without moving its behaviour: a checkout on Windows and
// one on macOS have to derive the same key set.
String _read(File file) => file.readAsStringSync().replaceAll('\r\n', '\n');

// A path below the repository root, always with `/` separators, so a build-log
// line reads the same on every platform.
String _relative(Directory repository, String path) {
  final String prefix = '${repository.path}/';
  return path.startsWith(prefix)
      ? path.substring(prefix.length).replaceAll('\\', '/')
      : path;
}

// The payload keys the domain layer declares as constants, and their kind.
//
// Parsed from the Dart source rather than listed here, so that adding a payload
// key to the domain is picked up by the next build with no edit to this file.
// That is the whole difference between this and the allowlist ADR-0008 retired.
//
// A source file that yields no key is a **failure**, not an empty result: it means
// the pattern above stopped matching the Dart it reads, and a script that silently
// asserts nothing is worse than no script, because the build goes green over a
// guard that is no longer running.
Map<String, bool> _domainConstantKeys(Directory repository) {
  final Map<String, bool> keys = <String, bool>{};
  for (final String relative in _domainSources) {
    final File source = File('${repository.path}/$relative');
    if (!source.existsSync()) {
      throw _Failure('missing domain source: $relative');
    }
    final Map<String, bool> found = <String, bool>{
      for (final RegExpMatch match in _constDeclaration.allMatches(_read(source)))
        match.group(2)!: _keyIsDirectory.hasMatch(match.group(1)!),
    };
    if (found.isEmpty) {
      throw _Failure(
        '$relative declares no payload-path constants; the pattern in '
        'validate_payload_keys.dart no longer matches the Dart it reads, so this '
        'script would silently assert nothing',
      );
    }
    keys.addAll(found);
  }
  return keys;
}

// Every path `payload-map.json` names.
//
// Read from the file rather than from a transcription of it, which is what makes
// a scene added to the payload ship without a build edit — and, here, be
// *asserted* without a build edit too.
Set<String> _payloadMapKeys(Directory repository) {
  final File path = File('${repository.path}/$_payloadMap');
  if (!path.existsSync()) {
    throw _Failure('missing $_payloadMap');
  }
  final Object? document = jsonDecode(_read(path));
  if (document is! Map<String, dynamic>) {
    throw _Failure('$_payloadMap does not hold a JSON object');
  }

  final Set<String> keys = <String>{};
  for (final String name in _mapStringKeys) {
    final Object? value = document[name];
    if (value == null) {
      throw _Failure("$_payloadMap has no '$name'");
    }
    if (value is! String) {
      throw _Failure("$_payloadMap: '$name' is not a string");
    }
    keys.add(value);
  }

  for (final String name in _mapMapKeys) {
    final Object? section = document[name];
    if (section == null) {
      throw _Failure("$_payloadMap has no '$name'");
    }
    if (section is! Map<String, dynamic>) {
      throw _Failure("$_payloadMap: '$name' is not an object");
    }
    // A scene with no document would be a scene that analyses against nothing,
    // and an empty value here would be a key of '' that every tree "has".
    for (final MapEntry<String, dynamic> scene in section.entries) {
      final Object? value = scene.value;
      if (value is! String || value.isEmpty) {
        throw _Failure("$_payloadMap: scene '${scene.key}' names no document");
      }
      keys.add(value);
    }
  }
  return keys;
}

// Files requested below a directory key, including manifest-driven names.
Set<String> _directoryMemberKeys(Directory repository) {
  final Set<String> keys = <String>{};
  final List<File> manifests = <File>[];
  for (final String relative in _domainSources) {
    final String text = _read(File('${repository.path}/$relative'));
    final Map<String, String> directories = <String, String>{
      for (final RegExpMatch match in _constDeclaration.allMatches(text))
        if (_keyIsDirectory.hasMatch(match.group(1)!))
          match.group(1)!: match.group(2)!,
    };
    for (final RegExpMatch match in _directoryLiteralRead.allMatches(text)) {
      final String? directory = directories[match.group(1)];
      if (directory == null) {
        continue;
      }
      final String key = '$directory/${match.group(2)}';
      keys.add(key);
      if (match.group(2) == 'manifest.json') {
        manifests.add(File('${repository.path}/$key'));
      }
    }
  }

  for (final File manifest in manifests) {
    final Object? document = jsonDecode(_read(manifest));
    final Object? cases =
        document is Map<String, dynamic> ? document['cases'] : null;
    if (cases is! List) {
      throw _Failure('${_relative(repository, manifest.path)} has no cases array');
    }
    for (int index = 0; index < cases.length; index++) {
      final Object? entry = cases[index];
      final Object? csv =
          entry is Map<String, dynamic> ? entry['csv'] : null;
      if (csv is! String || csv.isEmpty) {
        throw _Failure(
          '${_relative(repository, manifest.path)} case $index names no csv',
        );
      }
      keys.add('${_relative(repository, manifest.parent.path)}/$csv');
    }
  }
  return keys;
}

// Every key the material interface can request, mapped to "is a directory".
//
// A map rather than a set because the directory keys have to be checked
// differently, and returning a bare set would push that choice onto the caller.
Map<String, bool> _requiredKeys(Directory repository) {
  final Map<String, bool> keys = _domainConstantKeys(repository);
  // The map's own values are all documents, so a collision with a `Dir` constant
  // is a contradiction rather than a merge — say so instead of picking one.
  for (final String value in _payloadMapKeys(repository)) {
    if (keys[value] == true) {
      throw _Failure(
        '$value is declared as a directory constant and named by $_payloadMap as '
        'a document',
      );
    }
    keys[value] = false;
  }
  for (final String value in _directoryMemberKeys(repository)) {
    keys[value] = false;
  }
  return keys;
}

// The required keys with nothing at that path under [packaged].
List<String> _missingKeys(Map<String, bool> required, Directory packaged) {
  final List<String> ordered = required.keys.toList()..sort();
  final List<String> missing = <String>[];
  for (final String key in ordered) {
    final FileSystemEntityType type =
        FileSystemEntity.typeSync('${packaged.path}/$key');
    final bool present = required[key]!
        ? type == FileSystemEntityType.directory
        : type == FileSystemEntityType.file;
    if (!present) {
      missing.add(key);
    }
  }
  return missing;
}

int _run(List<String> arguments) {
  if (arguments.length != 2) {
    stderr.writeln(
      'usage: dart tool/validate_payload_keys.dart <repository-root> '
      '<packaged-root>',
    );
    return 2;
  }
  final Directory repository = Directory(arguments[0]).absolute;
  final Directory packaged = Directory(arguments[1]).absolute;
  try {
    if (!packaged.existsSync()) {
      throw _Failure('not a directory: ${packaged.path}');
    }
    final Map<String, bool> required = _requiredKeys(repository);
    final List<String> missing = _missingKeys(required, packaged);
    if (missing.isNotEmpty) {
      stderr.writeln(
        'payload assertion failed: ${missing.length} key(s) the app can request '
        'are not in the packaged tree:',
      );
      for (final String key in missing) {
        stderr.writeln('  missing: $key');
      }
      return 1;
    }
    stdout.writeln('payload assertion passed: ${required.length} keys present');
    return 0;
  } on _Failure catch (error) {
    stderr.writeln('payload assertion failed: ${error.message}');
    return 2;
  }
}

void main(List<String> arguments) {
  // `exitCode` rather than `exit()`: the VM flushes both streams on the way out,
  // and a build phase that reads the assertion's output needs it to be there.
  exitCode = _run(arguments);
}
