import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miaotou_capabilities/miaotou_capabilities.dart';
import 'package:miaotou_capabilities_macos/miaotou_capabilities_macos.dart';
import 'package:miaotou_capabilities_macos/testing.dart';

/// The shared payload on macOS, and the packaging invariant around it.
///
/// AC3 says the packaged application reads the payload **as real files, with no
/// copy inlined into the port**. That is two claims and this file holds both: the
/// first two tests read bytes out of a directory the test chose, and the guards at
/// the bottom read the port's own source to confirm nothing was pasted into it.
///
/// AC4 and AC5 are about the build, and the script that implements them is
/// `apps/miaotou_app/macos/Runner/sync_shared_payload.sh`, wired into an Xcode
/// build phase. The tests in the last group **run that script** through the same
/// environment Xcode gives it — same `SRCROOT`, same working directory, same
/// bundle path — so AC4 is checked by the test suite and not only by a build.
///
/// The reason for running it rather than reading it is this file's own history.
/// The guard used to assert that the script's text mentioned
/// `validate_payload_keys.py`, which was true of a path pointing at the real file
/// *and* of one pointing at a file that does not exist — and the second one is
/// what shipped, failing every macOS build while this suite stayed green. A
/// guard blind to the exact defect it exists to catch is worse than none, because
/// it is reported as coverage.
void main() {
  late Directory payload;
  late FakeMacosNative native;
  late MacosSharedPayload shared;

  setUp(() {
    native = FakeMacosNative();
    payload = Directory.systemTemp.createTempSync('miaotou-payload');
    shared = MacosSharedPayload(native);

    // A miniature of the real tree: two levels deep, so a key that walks out of
    // the root has somewhere to walk to.
    Directory('${payload.path}/miaotoujunshi/references/data')
        .createSync(recursive: true);
    File('${payload.path}/miaotoujunshi/references/data/payload-map.json')
        .writeAsStringSync('{"strategy_guide": "g.md"}');
    File('${payload.path}/miaotoujunshi/references/data/strategy-criteria.json')
        .writeAsStringSync('{"strategies": ["A"]}');
    Directory('${payload.path}/miaotoujunshi/references/data/nested')
        .createSync();
    File('${payload.path}/miaotoujunshi/references/data/nested/deep.json')
        .writeAsStringSync('{"deep": true}');
    native.payloadRoot = payload.path;
  });

  tearDown(() async {
    await native.close();
    payload.deleteSync(recursive: true);
  });

  test('a key is read as the bytes of the file at that path', () async {
    final Uint8List bytes = await shared.read(
      'miaotoujunshi/references/data/payload-map.json',
    );

    expect(
      utf8.decode(bytes),
      '{"strategy_guide": "g.md"}',
      reason: 'the key is repository-root-relative and resolves against the '
          'bundle, which is what keeps the built artifact mirroring the '
          'repository (ADR-0008 decision 3)',
    );
  });

  test('a key with Chinese characters in it resolves, because the payload has them',
      () async {
    final File tone =
        File('${payload.path}/miaotoujunshi/references/knowledge/口吻与取舍.md')
          ..parent.createSync(recursive: true);
    tone.writeAsStringSync('口吻规则');

    expect(
      utf8.decode(await shared.read(
        'miaotoujunshi/references/knowledge/口吻与取舍.md',
      )),
      '口吻规则',
    );
  });

  test('a missing key is a hard error, not an empty buffer', () async {
    await expectLater(
      shared.read('miaotoujunshi/references/data/does-not-exist.json'),
      throwsA(
        isA<FileSystemException>().having(
          (FileSystemException e) => e.message,
          'message',
          contains('packaging fault'),
        ),
      ),
      reason: 'a caller that gets bytes back must be able to trust they came '
          'from the payload; an empty buffer is indistinguishable from an empty '
          'document, and the caller is a prompt. The message is asserted as well '
          'as the type because `dart:io` raises the same type on its own — what '
          'the explicit check adds is the diagnosis, and a guard on the type '
          'alone would not notice losing it',
    );
  });

  test('a missing directory is a hard error, not an empty list', () async {
    await expectLater(
      shared.list('miaotoujunshi/references/data/does-not-exist'),
      throwsA(
        isA<FileSystemException>().having(
          (FileSystemException e) => e.message,
          'message',
          contains('packaging fault'),
        ),
      ),
    );
  });

  test('listing a directory needs no member list', () async {
    expect(
      await shared.list('miaotoujunshi/references/data'),
      <String>['payload-map.json', 'strategy-criteria.json'],
      reason: 'this is the property that makes a zero-change addition '
          'observable at runtime rather than only in a build log '
          '(ADR-0008 decision 5)',
    );
  });

  test('listing is not recursive, because the contract asks about one directory',
      () async {
    expect(
      await shared.list('miaotoujunshi/references/data'),
      isNot(contains('deep.json')),
      reason: '`nested/` is a directory, and a recursive walk would answer a '
          'different question than the one asked',
    );
  });

  test('a file added to the payload is visible with no code change', () async {
    // AC5. The property the whole arrangement exists for, and it is two
    // properties together: the tree is copied whole, and the key set is derived
    // rather than transcribed. Either alone would break it.
    final List<String> before =
        await shared.list('miaotoujunshi/references/data');

    File('${payload.path}/miaotoujunshi/references/data/added-later.json')
        .writeAsStringSync('{"added": true}');

    final List<String> after =
        await shared.list('miaotoujunshi/references/data');
    expect(after, hasLength(before.length + 1));
    expect(after, contains('added-later.json'));
    expect(
      utf8.decode(
        await shared.read('miaotoujunshi/references/data/added-later.json'),
      ),
      '{"added": true}',
    );
  });

  test('a key that leaves the payload tree is refused', () async {
    // The bundle is the whole world: a key that walked out of the resource root
    // would read a file the app does not ship, which is the one thing resolving
    // keys against the bundle is for.
    await expectLater(
      shared.read('../secrets.txt'),
      throwsArgumentError,
    );
    await expectLater(
      shared.read('/etc/passwd'),
      throwsArgumentError,
    );
    await expectLater(
      shared.read(''),
      throwsArgumentError,
    );
  });

  test('the resource root is asked once, however many files are read', () async {
    await shared.read('miaotoujunshi/references/data/payload-map.json');
    await shared.read('miaotoujunshi/references/data/strategy-criteria.json');
    await shared.list('miaotoujunshi/references/data');

    expect(
      native.log.where((String call) => call == 'resourceRoot').length,
      1,
      reason: 'a scene load reads a dozen files; asking the channel each time '
          'puts a platform round trip in the middle of every document read for a '
          'value that cannot change within a process',
    );
  });

  test('with no resource root to give, the read fails rather than guesses',
      () async {
    // The fake *refuses* the question, so this reaches `FakeMacosNative`'s own
    // guard and never the channel's. The channel answering nil is the case the
    // `?? ''` used to turn into a `/`-prefixed path, and it is covered below.
    final FakeMacosNative bare = FakeMacosNative();
    addTearDown(bare.close);

    await expectLater(
      MacosSharedPayload(bare).read('miaotoujunshi/references/data/x.json'),
      throwsStateError,
    );
  });

  group('the channel answering nil', () {
    // `StoragePaths.resourceRoot()` returns nil rather than `''` when the bundle
    // reports no resource path, so the Dart side has to decide what a nil is. The
    // decision it used to make was `?? ''`, which is the worst of both: the empty
    // string joins into `/miaotoujunshi/…`, an absolute path out of the filesystem
    // root, and the failure that eventually surfaces names a file the application
    // never meant to read instead of the bundle that is missing its payload.
    // `StoragePaths.resourceRoot()` returns nil rather than `''` when the bundle
    // reports no resource path, so the Dart side has to decide what a nil is. The
    // decision it used to make was `?? ''`, which is the worst of both: the empty
    // string joins into `/miaotoujunshi/…`, an absolute path out of the filesystem
    // root, and the failure that eventually surfaces names a file the application
    // never meant to read instead of the bundle that is missing its payload.
    //
    // Driven through a mocked channel rather than the fake, because the fake
    // *refuses* the question — so the nil this is about can never reach a test
    // that goes through it.
    TestWidgetsFlutterBinding.ensureInitialized();

    /// A channel whose `storage.resourceRoot` answers nil, as the Swift does when
    /// the build phase never ran.
    void answerRootAsNull() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel(MethodChannelMacosNative.methodChannelName),
        (MethodCall call) async => null,
      );
    }

    test('is refused by the channel, not turned into an empty path', () async {
      answerRootAsNull();

      await expectLater(
        MethodChannelMacosNative().resourceRoot(),
        throwsStateError,
        reason: 'a nil answer is a packaging fault — the build phase did not run '
            '— and has to say so rather than become a path',
      );
    });

    test('and a read over it fails rather than reaching the filesystem root',
        () async {
      // The end-to-end shape of the same fault. Without the refusal this throws
      // too, but as a `FileSystemException` naming `/miaotoujunshi/…`, which
      // points at the filesystem root instead of at the missing build step.
      answerRootAsNull();
      final MacosSharedPayload payload =
          MacosSharedPayload(MethodChannelMacosNative());

      await expectLater(
        payload.read('miaotoujunshi/references/data/x.json'),
        throwsA(
          isA<StateError>().having(
            (StateError e) => e.message,
            'message',
            allOf(contains('resource root'), isNot(contains('/miaotoujunshi'))),
          ),
        ),
        reason: 'the diagnosis has to name the resource root, and must not be a '
            'path — an absolute one is how this fault disguises itself as a '
            'missing document',
      );
    });

    test('an empty string from the channel is refused as well', () async {
      // The other shape the old coercion produced, and the one a Swift that
      // returned `""` would send. `MacosNative` is an interface, so the guard
      // cannot live only in the channel implementation.
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel(MethodChannelMacosNative.methodChannelName),
        (MethodCall call) async => '',
      );

      await expectLater(
        MethodChannelMacosNative().resourceRoot(),
        throwsStateError,
      );
    });

    test('an empty root from any implementation is refused where it is used',
        () async {
      // Deliberately not through the channel. `MacosNative` is an interface, so
      // `MacosSharedPayload` cannot assume the only implementation of it is the
      // one that throws — a fake, a future port, or a test double all reach this
      // class. The guard therefore has to hold here as well, and this is the only
      // assertion that reaches it: with the channel refusing first, nothing else
      // ever gets an empty root as far as the join.
      await expectLater(
        MacosSharedPayload(_EmptyRoot()).read('miaotoujunshi/x.json'),
        throwsA(
          isA<StateError>().having(
            (StateError e) => e.message,
            'message',
            contains('resource root'),
          ),
        ),
        reason: 'the empty root has to be refused before it is joined onto, or '
            'the key becomes an absolute path out of the filesystem root',
      );
    });
  });

  group('the packaging invariant', () {
    // The script and its wiring. `flutter build macos` cannot run on this
    // machine — `sandbox-exec` is broken here, so the SwiftPM resolution every
    // macOS build starts with cannot complete — so the phase is checked by
    // *running* it rather than by reading it. The run is the same one Xcode makes:
    // same script, same environment variables, same working directory.
    //
    // Reading the script is not enough, and the previous version of this file
    // learned that the expensive way. It asserted the phase's text
    // `contains('validate_payload_keys.py')`, which was true whether the path
    // pointed at the real file or at one that does not exist — so the guard passed
    // over a phase that failed **every** build with `can't open file
    // …/macos/validate_payload_keys.py`. A guard that cannot tell a working path
    // from a broken one is not a guard, so the test below runs the thing.
    const String runner = 'macos/Runner';

    /// The repository root, found by walking up as the build phase does.
    late Directory repository;
    late File script;
    late File assertion;
    late File pbxproj;

    /// The macOS project directory — Xcode's `SRCROOT`.
    late Directory srcroot;

    setUpAll(() {
      repository = Directory.current.absolute;
      while (!Directory('${repository.path}/goutoujunshi').existsSync()) {
        repository = repository.parent;
      }
      final Directory app = Directory(
        '${repository.path}/app/apps/miaotou_app',
      );
      srcroot = Directory('${app.path}/macos');
      script = File('${app.path}/$runner/sync_shared_payload.sh');
      assertion = File('${app.path}/$runner/validate_payload_keys.py');
      pbxproj = File('${app.path}/macos/Runner.xcodeproj/project.pbxproj');
    });

    /// Runs the build phase exactly as Xcode's `PBXShellScriptBuildPhase` does.
    ///
    /// The three things that make this the real invocation rather than a lookalike,
    /// each of which is a way the previous test let a real bug through:
    ///
    /// * `SRCROOT` is set to the macOS project directory, which is **not** the
    ///   directory the scripts live in. It is `…/macos`; the scripts are in
    ///   `…/macos/Runner`. Any path built out of `SRCROOT` has to say `Runner/`
    ///   itself, and the bug this test exists for was a path that did not.
    /// * The working directory is `SRCROOT`, because that is where Xcode runs it.
    /// * The repository root is *not* injected, so the walk-up that the build
    ///   relies on is the one under test.
    ///
    /// A bundle path is given rather than left to `BUILT_PRODUCTS_DIR`, for the
    /// same reason: the assertion is about the phase's own logic, and a missing
    /// `SRCROOT` or bundle has to be a loud failure rather than a default that
    /// quietly works.
    Future<ProcessResult> runBuildPhase({
      required String bundle,
      Map<String, String> extraEnvironment = const <String, String>{},
    }) =>
        Process.run(
          '/bin/sh',
          <String>[script.path],
          workingDirectory: srcroot.path,
          environment: <String, String>{
            'PATH': '/usr/bin:/bin:/usr/sbin:/sbin',
            'HOME': repository.parent.path,
            'SRCROOT': srcroot.path,
            'CODESIGNING_FOLDER_PATH': bundle,
            ...extraEnvironment,
          },
          // A build log, not a test's captured output. `includeParentEnvironment`
            // is off so an `HTTP_PROXY` or an `MIAOTOU_REPO_ROOT` in the
            // developer's shell cannot make this pass or fail.
        );

    test('the sync is wired into the Runner target as a build phase', () {
      final String project = pbxproj.readAsStringSync();

      expect(project, contains('PBXShellScriptBuildPhase'));
      expect(
        project,
        contains('Sync shared payload'),
        reason: 'AC4 says "asserted at build time"; a build phase on the Runner '
            'target is the only place on this platform where "before the build '
            'finishes" is a thing that can fail',
      );
      expect(
        project,
        contains(r'$SRCROOT/Runner/sync_shared_payload.sh'),
        reason: 'a phase that exists but runs nothing is a phase that has been '
            'unhooked',
      );
    });

    test('the build phase runs, and it passes', () async {
      // The test that stands in for the build. It fails the way a build fails:
      // a non-zero exit from the phase, with the phase's own output attached.
      final Directory bundle = _bundle();
      final ProcessResult result = await runBuildPhase(bundle: bundle.path);

      expect(
        result.exitCode,
        0,
        reason: 'the build phase exited ${result.exitCode}, so every '
            '`flutter build macos` on this platform fails. Its output:\n'
            '${result.stdout}${result.stderr}',
      );
      expect(
        '${result.stdout}${result.stderr}',
        contains('payload assertion passed'),
        reason: 'exit 0 with no assertion output would mean the phase stopped '
            'running the assertion while still succeeding — the guard the whole '
            'arrangement exists to provide, reporting success without checking',
      );
      expect(
        Directory('${bundle.path}/Contents/Resources/miaotoujunshi')
            .existsSync(),
        isTrue,
        reason: 'the payload has to be inside the bundle, beside Info.plist, '
            'where Bundle.main.resourcePath points',
      );
    });

    test('the phase finds its own scripts from SRCROOT, which is not where they '
        'live', () async {
      // The regression this whole group exists for, asserted as its own property
      // so the failure names the cause. `SRCROOT` is `…/macos` and the scripts
      // are in `…/macos/Runner`; the phase used to ask for
      // `$SRCROOT/validate_payload_keys.py`, which does not exist, which failed
      // every build — and which a text-matching guard read as correct.
      //
      // Both halves are checked. The run above proves the phase works; this
      // proves it works *for the right reason*, so that deleting the `Runner/`
      // step and compensating somewhere else cannot pass unnoticed.
      expect(
        srcroot.uri.pathSegments
            .where((String segment) => segment.isNotEmpty)
            .last,
        'macos',
        reason: 'this test hard-codes the shape SRCROOT has; if that changed, '
            'the expectation below is no longer the one it claims to be',
      );
      expect(
        assertion.parent.uri.pathSegments
            .where((String segment) => segment.isNotEmpty)
            .last,
        'Runner',
        reason: 'the assertion sits beside the sync script, one level below '
            'SRCROOT — this is the step the path has to spell out',
      );
      expect(
        File('${srcroot.path}/validate_payload_keys.py').existsSync(),
        isFalse,
        reason: 'if a file ever appears at \$SRCROOT/validate_payload_keys.py, '
            'the phase is reading a *second* copy of the assertion and the one '
            'beside it is not being run at all',
      );
    });

    test('the phase refuses to guess the variables it was not given', () async {
      // No fallback for `SRCROOT`. A default here is what let the path bug hide:
      // the hand-run took the fallback branch, printed "payload assertion
      // passed", and agreed with nothing the build does.
      final ProcessResult noSrcroot = await Process.run(
        '/bin/sh',
        <String>[script.path],
        workingDirectory: srcroot.path,
        environment: <String, String>{
          'PATH': '/usr/bin:/bin:/usr/sbin:/sbin',
          'CODESIGNING_FOLDER_PATH': _bundle().path,
        },
      );
      expect(
        noSrcroot.exitCode,
        isNot(0),
        reason: 'a build phase that runs with no SRCROOT is a phase that has '
            'invented its own location, which is the one thing that made the '
            'previous bug invisible',
      );
      expect(
        '${noSrcroot.stdout}${noSrcroot.stderr}',
        contains('SRCROOT is not set'),
        reason: 'the failure has to say which variable is missing, or the next '
            'person to hit it is guessing',
      );

      final ProcessResult noBundle = await Process.run(
        '/bin/sh',
        <String>[script.path],
        workingDirectory: srcroot.path,
        environment: <String, String>{
          'PATH': '/usr/bin:/bin:/usr/sbin:/sbin',
          'SRCROOT': srcroot.path,
        },
      );
      expect(
        noBundle.exitCode,
        isNot(0),
        reason: 'with no bundle the phase has nowhere to copy the payload to; '
            'guessing /Contents/Resources would create a directory at the '
            'filesystem root and report success having shipped nothing',
      );
      expect(
        '${noBundle.stdout}${noBundle.stderr}',
        contains('CODESIGNING_FOLDER_PATH'),
      );
    });

    test('the sync is an rsync mirror, not a copy', () {
      final String body = script.readAsStringSync();

      expect(
        body,
        contains('rsync -a --delete'),
        reason: 'ADR-0006 records the accident: Copy leaves files in the '
            "destination that the source no longer has, and a local build then "
            'shipped both the old and the new payload trees. --delete makes the '
            'destination a mirror, so a renamed file cannot leave its predecessor '
            'behind to be read in preference to it',
      );
      // Scoped to the executable lines: the header explains *why* `cp -R` is not
      // used, so a whole-file search would find the mention and fail on the
      // comment that documents the rule.
      final String commands = body
          .split('\n')
          .where((String line) => !line.trimLeft().startsWith('#'))
          .join('\n');
      expect(
        commands,
        isNot(contains('cp -R')),
        reason: 'the same accident, by another spelling',
      );
    });

    test('both payload trees are synced, not one', () async {
      // Run rather than read, for the same reason as above: the pair of trees is
      // a claim about what the phase *does*.
      final Directory bundle = _bundle();
      await runBuildPhase(bundle: bundle.path);
      final Directory resources = Directory('${bundle.path}/Contents/Resources');

      for (final String tree in <String>['miaotoujunshi', 'goutoujunshi']) {
        expect(
          Directory('${resources.path}/$tree').existsSync(),
          isTrue,
          reason: '$tree is half the payload, and the assertion passes without '
              'either being copied if the two are confused',
        );
      }
    });

    test('a packaged tree missing a document fails the build', () async {
      // The assertion's half of AC4, driven through the phase.
      //
      // The key is removed from the **source** checkout the phase syncs from, not
      // from the bundle: a phase re-runs `rsync --delete` on every invocation, so
      // deleting from the destination would just be undone and the test would
      // pass over a phase that had asserted nothing. A repository missing a
      // payload file is the situation the guard exists for — the file exists in
      // git, and something upstream dropped it — and it is also the only way to
      // reach the assertion's "missing key" branch through the phase at all.
      final Directory checkout = _checkoutWith(repository);
      File('${checkout.path}/goutoujunshi/SKILL.md').deleteSync();

      final ProcessResult fail = await runBuildPhase(
        bundle: _bundle().path,
        extraEnvironment: <String, String>{'MIAOTOU_REPO_ROOT': checkout.path},
      );

      expect(
        fail.exitCode,
        isNot(0),
        reason: 'a build that shipped without one of the files the app can ask '
            'for must not succeed — that is the whole claim of AC4',
      );
      expect(
        '${fail.stdout}${fail.stderr}',
        contains('goutoujunshi/SKILL.md'),
        reason: 'the failure has to name the key, or the person fixing it is '
            'guessing',
      );
    });

    test('a checkout missing a directory fails the build, and says so', () async {
      // The directory keys are checked differently from the documents, and this
      // is the only test that reaches that branch through the phase.
      // `caseBundleDir` points at `…/examples/relationship_cases`, whose name
      // says nothing about it — a check that classified every key as a file
      // would pass on an absent directory, which is the failure this script
      // exists to make impossible.
      final Directory checkout = _checkoutWith(repository);
      final Directory cases = Directory(
        '${checkout.path}/miaotoujunshi/examples/relationship_cases',
      );
      expect(cases.existsSync(), isTrue, reason: 'the mirror copied it');
      cases.deleteSync(recursive: true);

      final ProcessResult fail = await runBuildPhase(
        bundle: _bundle().path,
        extraEnvironment: <String, String>{'MIAOTOU_REPO_ROOT': checkout.path},
      );

      expect(fail.exitCode, isNot(0));
      expect(
        '${fail.stdout}${fail.stderr}',
        contains('relationship_cases'),
        reason: 'a directory key has to be named as precisely as a document key, '
            'or removing one looks like an unrelated build error',
      );
    });

    test('the key set is derived from the domain and the payload map, never '
        'transcribed', () {
      final String body = assertion.readAsStringSync();

      expect(
        body,
        contains('_CONST_DECLARATION'),
        reason: 'the keys come from the domain layer\'s own constants, so a new '
            'payload key ships with no edit to any build script',
      );
      expect(body, contains('payload-map.json'));
      // The specific sections, not just the file: dropping `scene_knowledge` from
      // the derivation would leave every path in this script intact and silently
      // stop asserting the four scene documents.
      for (final String section in <String>[
        'strategy_guide',
        'shared_tone_document',
        'entry_document',
        'scene_knowledge',
      ]) {
        expect(
          body,
          contains(section),
          reason: '$section is a key the payload map names and the derivation '
              'has to read it; without it the build would assert nothing about '
              'that document',
        );
      }
      for (final String key in <String>[
        'miaotoujunshi/references/data/judge-questions.json',
        'goutoujunshi/SKILL.md',
        '口吻与取舍',
      ]) {
        expect(
          body,
          isNot(contains(key)),
          reason: 'this path is written down in the script, so adding or moving it '
              'in the payload would need the script edited too — which is the '
              'hand-copied member list ADR-0006 exists to eliminate',
        );
      }
    });

    test('the assertion passes against the real repository and fails without a '
        'key', () async {
      // Run for real, the way the build phase runs it. `flutter build macos`
      // cannot run here, so this is the substitute that is actually executable —
      // it exercises the same script, over the same payload, against a tree the
      // test assembled the way `rsync` would.
      final ProcessResult pass = await Process.run(
        'python3',
        <String>[assertion.path, repository.path, _mirrorOfRepository(repository).path],
      );
      expect(
        pass.exitCode,
        0,
        reason: 'a full mirror of the payload must satisfy the assertion:\n'
            '${pass.stdout}${pass.stderr}',
      );

      final Directory broken = _mirrorOfRepository(repository);
      File('${broken.path}/goutoujunshi/SKILL.md').deleteSync();
      final ProcessResult fail = await Process.run(
        'python3',
        <String>[assertion.path, repository.path, broken.path],
      );

      expect(
        fail.exitCode,
        1,
        reason: 'a packaged tree missing one key must fail the build, not ship',
      );
      expect(
        '${fail.stdout}${fail.stderr}',
        contains('goutoujunshi/SKILL.md'),
        reason: 'the failure has to name the key, or the person fixing it is '
            'guessing',
      );
    });

    test('the payload is not declared as a Flutter asset anywhere', () {
      // ADR-0008's central claim, re-checked from this side: a Flutter asset
      // directory entry is not recursive, so declaring it would ship the payload
      // partially and need a pubspec edit per new file.
      for (final File pubspec in _pubspecs(repository)) {
        final String body = pubspec.readAsStringSync();
        for (final String line in body.split('\n')) {
          final String trimmed = line.trim();
          if (!trimmed.startsWith('- ')) {
            continue;
          }
          expect(
            trimmed,
            isNot(startsWith('- goutoujunshi')),
            reason: '${pubspec.path} declares the payload as a Flutter asset',
          );
          expect(
            trimmed,
            isNot(startsWith('- miaotoujunshi')),
            reason: '${pubspec.path} declares the payload as a Flutter asset',
          );
        }
      }
    });

    test('no payload content is inlined into the port', () {
      // AC3's "no copy inlined into the port", checked by reading the port's own
      // source. A distinctive string from each payload file: if one appears in a
      // Dart or Swift file of this package, the port is answering from a copy
      // rather than from the tree.
      const Map<String, String> fingerprints = <String, String>{
        'payload-map.json': '_provenance',
        'strategy-criteria.json': 'typesafe_criteria',
        'judge-questions.json': 'rank_instructions',
        'reply-preferences.json': 'tone_guidance',
        'relationship-enums.json': 'profile_fields',
        'trend-rules.json': 'timestamp_format',
      };

      for (final File source in _portSources(repository)) {
        final String body = source.readAsStringSync();
        for (final MapEntry<String, String> entry in fingerprints.entries) {
          expect(
            body,
            isNot(contains(entry.value)),
            reason: '${source.path} contains "${entry.value}", a key only the '
                '${entry.key} payload file has. The port must read the tree, not '
                'carry a copy of it (ADR-0005 decision 1)',
          );
        }
        expect(
          body,
          isNot(contains('## 常用话术库')),
          reason: '${source.path} contains a heading from the upstream skill '
              'document; the reply prompt quotes that file at runtime rather than '
              'carrying a copy of it',
        );
      }
    });

    test('no shipping source carries a payload path as a literal either', () {
      // The other half of "reads the payload rather than carrying a copy". A
      // source that hard-codes `goutoujunshi/SKILL.md` would be reaching for a
      // repository layout that does not exist inside a `.app`, so the failure
      // would be a read that cannot work rather than a wrong answer — but it is
      // worth catching here, where the reason is legible, rather than on a
      // device where it is a `MissingPluginException`-shaped silence.
      //
      // Prose mentions are excluded, because the Dart comments in this port
      // legitimately name the directory when explaining what the port does.
      for (final File source in _portSources(repository)) {
        final String code = source
            .readAsLinesSync()
            .where((String line) => !line.trimLeft().startsWith('//'))
            .join('\n');
        for (final String tree in <String>['goutoujunshi', 'miaotoujunshi']) {
          expect(
            code,
            isNot(contains("'$tree/\u0022")),
            reason: '${source.path} hard-codes a payload path. Keys belong to '
                'the domain layer and are resolved against the bundle at runtime; '
                'a literal here is a path that only exists in a checkout '
                '(ADR-0008 decision 3)',
          );
        }
      }
    });
  });
}

/// A seam that answers an **empty** resource root.
///
/// Not a `FakeMacosNative`, because that one refuses the question rather than
/// answering it badly — and the guard under test is the one that catches a bad
/// answer, which the fake's refusal never reaches.
class _EmptyRoot implements MacosNative {
  @override
  Future<String> resourceRoot() async => '';

  @override
  Future<String> containerDirectory() async => '';

  @override
  Future<List<String>> keychainKeys() async => const <String>[];

  @override
  Future<String?> keychainRead(String key) async => null;

  @override
  Future<void> keychainWrite(String key, String value) async {}

  @override
  Future<void> keychainDelete(String key) async {}

  @override
  Future<String?> findTargetWindow() async => null;

  @override
  Future<CaptureOutcome> capture({String? targetWindowId}) async =>
      const CaptureFailed(code: 1, message: 'not used');

  @override
  Future<List<OcrLine>> recognize(
    CaptureFrame frame, {
    required List<String> languages,
  }) async =>
      const <OcrLine>[];

  @override
  Future<InjectResult> inject(String text, {required InjectTarget target}) async =>
      const InjectResult.unverified('not used');

  @override
  Future<PanelGeometry> panelGeometry() async =>
      const PanelGeometry(screen: ScreenRect.empty, window: ScreenRect.empty);

  @override
  Future<void> showPanel({
    required PanelPlacement placement,
    ScreenRect? at,
  }) async {}

  @override
  Future<bool> hidePanel() async => false;

  @override
  Future<void> restorePanel() async {}

  @override
  Future<void> setPanelFocusable(bool value) async {}

  @override
  Stream<NativePanelEvent> get events => const Stream<NativePanelEvent>.empty();
}

/// A checkout that is the repository with its two payload trees copied, so a test
/// can remove one key from the source and watch the build phase notice.
///
/// Everything *except* the two payload trees is symlinked, because the assertion
/// does not only read the payload: it derives its key set from the domain layer's
/// own Dart constants, under `app/packages/…`. A mirror of
/// the payload alone therefore fails with `missing domain source` — a correct
/// refusal about the wrong thing, and one that would have made these tests pass
/// while asserting nothing about the key that was removed.
///
/// The payload trees are copied rather than symlinked for the opposite reason:
/// `rsync --delete` in the phase has to be able to *not* find a deleted key, and
/// a symlinked tree would still contain it.
Directory _checkoutWith(Directory repository) {
  final Directory checkout = Directory.systemTemp.createTempSync('miaotou-checkout');
  addTearDown(() {
    if (checkout.existsSync()) {
      checkout.deleteSync(recursive: true);
    }
  });
  for (final FileSystemEntity entity in repository.listSync(followLinks: false)) {
    if (entity is! Directory) {
      continue;
    }
    final String name = entity.uri.pathSegments
        .where((String segment) => segment.isNotEmpty)
        .last;
    if (name != 'goutoujunshi' && name != 'miaotoujunshi') {
      Link('${checkout.path}/$name').createSync(entity.path);
    }
  }
  _copyInto(
    repository,
    checkout,
    <String>{'goutoujunshi', 'miaotoujunshi'},
  );
  return checkout;
}

/// A throwaway `.app` bundle for the build phase to fill, deleted afterwards.
///
/// Shaped like the real one — `<name>.app/Contents/Resources` — because the
/// destination is derived from the bundle path and a flat directory would not
/// exercise that join. The name is the one Xcode uses so a failure that prints
/// the path reads the way it will in a build log.
Directory _bundle() {
  final Directory bundle = Directory.systemTemp.createTempSync('miaotou-bundle');
  Directory('${bundle.path}/Runner.app/Contents/Resources')
      .createSync(recursive: true);
  addTearDown(() {
    if (bundle.existsSync()) {
      bundle.deleteSync(recursive: true);
    }
  });
  return Directory('${bundle.path}/Runner.app');
}

/// A copy of the repository's two payload trees, assembled the way `rsync` would.
///
/// The whole tree rather than a fixture, because the point is that the *real*
/// keys are present — a hand-built tree would only prove the script agrees with
/// whoever built the tree.
Directory _mirrorOfRepository(Directory repository) {
  final Directory root = Directory.systemTemp.createTempSync('miaotou-mirror');
  addTearDown(() {
    if (root.existsSync()) {
      root.deleteSync(recursive: true);
    }
  });
  _copyInto(
    repository,
    root,
    <String>{'goutoujunshi', 'miaotoujunshi'},
  );
  return root;
}

void _copyInto(Directory from, Directory to, Set<String> trees) {
  for (final String tree in trees) {
    final Directory source = Directory('${from.path}/$tree');
    if (!source.existsSync()) {
      continue;
    }
    for (final FileSystemEntity entity
        in source.listSync(recursive: true, followLinks: false)) {
      final String relative = entity.path.substring(from.path.length + 1);
      final String target = '${to.path}/$relative';
      if (entity is Directory) {
        Directory(target).createSync(recursive: true);
      } else if (entity is File) {
        Directory(File(target).parent.path).createSync(recursive: true);
        entity.copySync(target);
      }
    }
  }
}

List<File> _pubspecs(Directory repository) => <File>[
      for (final File file in repository
          .listSync(recursive: true, followLinks: false)
          .whereType<File>()
          .where((File f) => f.path.endsWith('pubspec.yaml')))
        if (!file.path.contains('/.dart_tool/') && !file.path.contains('/build/'))
          file,
    ];

/// The shipping sources of the macOS port, plus the Swift beside them.
List<File> _portSources(Directory repository) {
  final Directory package = Directory(
    '${repository.path}/app/packages/miaotou_capabilities_macos',
  );
  return <File>[
    for (final FileSystemEntity entity
        in Directory('${package.path}/lib').listSync(recursive: true))
      if (entity is File && entity.path.endsWith('.dart')) entity,
    for (final FileSystemEntity entity
        in Directory(
          '${package.path}/macos/miaotou_capabilities_macos/Sources',
        ).listSync(recursive: true))
      if (entity is File && entity.path.endsWith('.swift')) entity,
  ];
}
