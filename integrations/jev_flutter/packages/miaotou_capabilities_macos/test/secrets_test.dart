import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// AC1 — "credentials are held by the system keychain rather than a plaintext
/// file" — and the two properties that make it hold on macOS specifically.
///
/// The behavioural half of AC1 is in `storage_test.dart`, where a secret is
/// written and every file in the container is searched for it. This file is the
/// half no behaviour test can reach: **the Keychain is reached through
/// `Security.framework`, and a secret in a sandboxed app cannot be reached any
/// other way.** Whether the Swift sets the one attribute that decides whether
/// the user is prompted, and whether the listing path can return a value at all,
/// are statements about source code. They are asserted here by reading it, the
/// same technique `native_channel_test.dart` uses for the method names.
/// A Swift file's **code**, with its `//` comments removed.
///
/// These guards are about what the program does, and several of the rules they
/// check are explained in the very comments that would otherwise trip them: the
/// Keychain file says in prose that it does not shell out to `security`, and the
/// paths file says in prose that it does not hard-code a home directory. A guard
/// that could not tell a mention from a use would be a guard somebody eventually
/// disables.
String _code(String path) => File(path)
    .readAsLinesSync()
    .where((String line) => !line.trimLeft().startsWith('//'))
    .join('\n');

void main() {
  const String sources = 'macos/miaotou_capabilities_macos/Sources/'
      'miaotou_capabilities_macos';

  // The three Swift files these guards read, comments already stripped.
  String keychain() => _code('$sources/KeychainStore.swift');
  String paths() => _code('$sources/StoragePaths.swift');
  String plugin() => _code('$sources/MiaotouMacosPlugin.swift');

  group('the Keychain is the system Keychain', () {
    test('every query asks for the data protection keychain', () {
      expect(
        keychain(),
        contains('kSecUseDataProtectionKeychain'),
        reason: 'macOS 10.15+ requires this attribute for an app to use the data '
            'protection keychain. Without it a macOS app reads the *file-based* '
            'login keychain, and every access from a sandboxed app raises an '
            'authorisation dialog — the user would be asked to allow the app to '
            'read its own key, on every read',
      );
      // Set in `baseQuery`, so it cannot be forgotten by a new call site.
      expect(
        keychain(),
        contains('private static func baseQuery'),
        reason: 'the attribute belongs in the one place every query is built '
            'from, because forgetting it at a call site does not fail to '
            'compile — it produces an app that prompts',
      );

      // And it has to be in *both* places it appears, not just one. `keys()`
      // builds its own literal rather than deriving from `baseQuery`, so an
      // attribute present in only one of them is a query that prompts.
      final int queries = 'kSecClass as String: kSecClassGenericPassword'
          .allMatches(keychain()).length;
      final int guarded = RegExp(
        r'kSecUseDataProtectionKeychain',
      ).allMatches(keychain()).length;
      expect(
        guarded,
        greaterThanOrEqualTo(queries),
        reason: 'every query in the file carries the attribute, and there are '
            '$queries of them',
      );
    });

    test('the keychain is not reached by running `security`', () {
      // The frozen Python port's mechanism
      // (`integrations/jev_mac/credentials.py`) shells out to
      // /usr/bin/security. A sandboxed app cannot: the binary is not on the
      // allowed surface, and a subprocess would not inherit the framework's
      // grant anyway.
      for (final String file in <String>[
        'KeychainStore.swift',
        'StoragePaths.swift',
        'MiaotouMacosPlugin.swift',
      ]) {
        final String body = _code('$sources/$file');
        for (final String forbidden in <String>[
          '/usr/bin/security',
          'Process(',
          'Process.run',
          'NSTask',
          'executableURL',
        ]) {
          expect(
            body,
            isNot(contains(forbidden)),
            reason: '$file reaches for $forbidden. A sandboxed app cannot spawn '
                'it, and a secret on a command line or in a child process is a '
                'secret in a process listing',
          );
        }
      }
    });

    test('a secret never becomes a string in a log or a print', () {
      expect(
        keychain(),
        isNot(contains('print(')),
        reason: 'a print of a query dictionary would put a secret in the log, and '
            'the log is a file a user can read and a support bundle collects',
      );
      expect(
        keychain(),
        isNot(contains('os_log')),
        reason: 'same reason: the unified log is readable by anyone with the '
            'machine, and a secret does not belong in it',
      );
    });
  });

  group('keys() cannot return a value', () {
    test('the listing query asks for attributes and not for data', () {
      final String body = _code('$sources/KeychainStore.swift');
      final int listing = body.indexOf('static func keys()');
      final int end = body.indexOf('private static func baseQuery');
      expect(listing, greaterThan(0), reason: 'the function moved or was renamed');
      final String query = body.substring(listing, end);

      expect(
        query,
        contains('kSecReturnAttributes'),
        reason: 'attributes are what carries the account name, which is the key',
      );
      expect(
        query,
        isNot(contains('kSecReturnData')),
        reason: 'this is the whole privacy property of SecretStore.keys(): a '
            'settings screen must be able to say which providers are configured '
            'without being able to obtain the key. Asking for data here would '
            'make the secret reachable from a method whose entire job is to list '
            'names, and the contract says "names only, never values"',
      );
      expect(
        query,
        contains('kSecMatchLimitAll'),
        reason: 'one item would be a list of one; the settings screen has three '
            'providers',
      );
      expect(query, contains('kSecAttrAccount'));
    });

    test('the listing maps only the account, and sorts', () {
      final String body = _code('$sources/KeychainStore.swift');
      final int listing = body.indexOf('static func keys()');
      final String query =
          body.substring(listing, body.indexOf('private static func baseQuery'));

      expect(
        query,
        contains(r'$0[kSecAttrAccount as String] as? String'),
        reason: 'the account is the key the caller passed and nothing else comes '
            'back',
      );
      expect(query, contains('.sorted()'));
    });

    test('no member anywhere returns every stored value at once', () {
      // The interface has four members and exactly one of them returns a value by
      // key. There is no `all()`, no `dump()`, no `values()`. That absence is the
      // property, and it is only observable from the seam's declaration.
      for (final String file in <String>[
        '$sources/KeychainStore.swift',
        'lib/src/native.dart',
        'lib/src/secrets.dart',
      ]) {
        final String body = _code(file);
        for (final String forbidden in <String>[
          'func all(',
          'func values(',
          'func dump(',
          'Future<List<String>> keychainValues',
        ]) {
          expect(
            body,
            isNot(contains(forbidden)),
            reason: '$file offers a bulk read. A settings screen would then have '
                'a method that hands it every secret while deciding what to show',
          );
        }
      }
    });
  });

  group('the two directories', () {
    test('the resource root comes from the bundle, not from a hard-coded path', () {
      final String body = paths();

      expect(
        body,
        contains('Bundle.main.resourcePath'),
        reason: 'a packaged app has no repository above it; this is the only '
            'thing that knows where the bundle is',
      );
      expect(
        body,
        isNot(contains('/Users/')),
        reason: 'a path under a user name would work on the author\'s machine '
            'and nowhere else',
      );
    });

    test('the container is the application support directory, not a guess', () {
      final String body = paths();

      expect(
        body,
        contains('.applicationSupportDirectory'),
        reason: 'under the sandbox the home directory is not writable, and this '
            'is the location the system documents for exactly this use',
      );
      expect(
        _code('$sources/StoragePaths.swift'),
        isNot(contains('NSHomeDirectory')),
        reason: 'a path under the home directory is the hard-coded alternative, '
            'and it is what the upstream Python store did. The directory *name* '
            'is still a quoted constant, so the guard is for the lookup rather '
            'than for quotes',
      );
    });

    test('a directory with no resource root is an error, not an empty string', () {
      // The Dart side does `?? ''`, so a `nil` here would resolve every payload
      // key against the process's working directory — and the resulting error
      // would name a file rather than the bundle, which is the wrong diagnosis
      // for a packaging fault.
      final String pluginBody = plugin();

      expect(
        pluginBody,
        contains('case "storage.resourceRoot"'),
      );
      expect(
        pluginBody,
        contains('no_resource_root'),
        reason: 'a bundle that reports no resource path is a build that did not '
            'run the sync phase, and saying so is the difference between a '
            'packaging fault and a missing document',
      );
    });

    test('the container directory is created by the system call, not afterwards',
        () {
      // `create: true` in the same call. Creating it in Dart would be testable,
      // but creating it *here* means the directory exists before any store can be
      // handed the path, so there is no window in which a write fails for want of
      // a directory that was about to appear.
      expect(paths(), contains('create: true'));
    });
  });

  group('the wiring', () {
    test('the plugin dispatches the keychain off the main thread', () {
      // `SecItem*` is a synchronising IPC call to `securityd`, and a sandboxed
      // app's first access can block long enough for the watchdog in
      // `CapturePacing` to notice. On the main thread it would also stall the
      // panel.
      final String body = plugin();

      expect(
        body,
        contains('DispatchQueue.global'),
        reason: 'a keychain round trip on the main thread is a dropped frame in '
            'the panel, and on first access it is a visible stall',
      );
      expect(
        body,
        contains('DispatchQueue.main.async'),
        reason: 'and the answer has to come back on the thread the channel '
            'expects to be written from',
      );
    });

    test('the podspec and Package.swift still declare the same platform floor', () {
      // Not #15's change, and asserted because the new files are compiled under
      // it: `kSecUseDataProtectionKeychain` needs 10.15 and the floor is 14.0 for
      // `SCScreenshotManager`, so both declarations have to stay as they are.
      final String podspec =
          File('macos/miaotou_capabilities_macos.podspec').readAsStringSync();
      final String package =
          File('macos/miaotou_capabilities_macos/Package.swift')
              .readAsStringSync();

      expect(podspec, contains("s.platform = :osx, '14.0'"));
      expect(package, contains('.macOS("14.0")'));
    });

    test('the new sources are inside the podspec glob, or they will not compile',
        () {
      // A new file that the podspec's `source_files` does not match is a plugin
      // that builds on the Swift Package Manager path and fails on the CocoaPods
      // one — and the failure is a missing symbol, not a missing file.
      final String podspec =
          File('macos/miaotou_capabilities_macos.podspec').readAsStringSync();

      expect(
        podspec,
        contains(r'Sources/miaotou_capabilities_macos/**/*.swift'),
        reason: 'the glob has to reach into Sources/ recursively or a new file '
            'is silently not part of the CocoaPods build',
      );
      // And the files are where the glob says.
      for (final String name in <String>['KeychainStore.swift', 'StoragePaths.swift']) {
        expect(
          File('$sources/$name').existsSync(),
          isTrue,
          reason: '$name is referenced by the plugin and by these guards',
        );
      }
    });
  });
}
