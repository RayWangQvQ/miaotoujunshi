import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miaotou_capabilities/miaotou_capabilities.dart';
import 'package:miaotou_capabilities_macos/miaotou_capabilities_macos.dart';

/// The seam itself.
///
/// A method channel has no compiler. Rename a method on either side and the whole
/// port still builds, still analyses and still passes every test that does not
/// happen to call it — and then answers `MissingPluginException` to a user. So the
/// names are asserted here from both directions: the Dart calls a mocked handler,
/// and the Swift that has to implement those names is read off disk and checked.
void main() {
  test('the whole Swift module typechecks, not just each file', () {
    // The tests below read the Swift as text, and a per-file `swiftc -parse` reads
    // it as text too. Neither can see a type error, and this module carried five:
    // an optional `MiaotouPanel?` passed where an `NSWindow` was required, and four
    // `keychain(arguments) { … }` calls whose trailing closure bound to the
    // callback instead of the body. Both kinds are invisible to parsing and fatal
    // to a build, which is why the module was never typechecked as a whole and the
    // errors sat in committed code.
    //
    // So this runs the compiler over every file at once, which is the only form of
    // the check that sees across files — every one of those errors was in a file
    // that parsed perfectly on its own.
    const String sources = 'macos/miaotou_capabilities_macos/Sources/'
        'miaotou_capabilities_macos';
    final Directory source = Directory(sources);
    final List<String> files = <String>[
      for (final FileSystemEntity entity in source.listSync())
        if (entity is File && entity.path.endsWith('.swift')) entity.path,
    ]..sort();
    expect(files, isNotEmpty, reason: 'no Swift found at $sources — the path is '
        'wrong and this test would otherwise pass without compiling anything');

    final _Typecheck typecheck = _swiftcTypecheck(files);
    final ProcessResult? compiled = typecheck.compiled;
    if (compiled == null) {
      final String because = typecheck.skippedBecause;
      // Reported as well as handed to `markTestSkipped`. A skip that only exists
      // in the reporter's exit accounting is indistinguishable, to whoever reads
      // the log weeks later, from a test that was never in the file — and the
      // question this test raises ("does the module still compile?") deserves an
      // answer in the log even when the answer is "this platform cannot ask".
      //
      // `debugPrint` rather than `print` only because the lint forbids the
      // latter; both write to the test output, which is the point.
      //
      // The CI case prints its own reason. `flutter.yml` runs on
      // `ubuntu-latest`, where there is no `xcrun` and no macOS SDK at all, and
      // any push touching `app/**` reaches this file.
      debugPrint('skipping the Swift module typecheck: $because');
      markTestSkipped('no macOS SDK or Flutter framework to typecheck against '
          '($because)');
      return;
    }

    // Both halves, and neither alone is enough. The exit code says the compiler
    // failed; the text says *why*, and a bare non-zero would leave the reader
    // guessing whether the module broke or the invocation did. A syntax error and
    // a type error both land here — the first is what a per-file parse already
    // catches, the second is the whole reason this check runs the compiler over
    // every file at once.
    expect(
      compiled.exitCode,
      0,
      reason: 'the Swift compiler rejected the module, so `flutter build macos` '
          'cannot produce an .app. The compiler output is below.',
    );
    expect(
      '${compiled.stdout}${compiled.stderr}',
      isNot(contains('error:')),
      reason: 'the Swift module does not compile, so `flutter build macos` cannot '
          'produce an .app. The compiler output is above.',
    );
  });

  _channelTests();
}

/// What a typecheck attempt produced: a result, or the reason there is none.
///
/// A pair rather than a nullable [ProcessResult] because the skip reason has to
/// travel with the skip. A `null` return would force the caller to reconstruct
/// the reason by running the same probes again, and the reconstruction is what
/// drifts out of sync with the thing it is explaining.
typedef _Typecheck = ({ProcessResult? compiled, String skippedBecause});

/// The `swiftc -typecheck` result, or a skip saying why there is none.
///
/// A skip rather than a pass: "the module compiles" is a claim about the build,
/// and a test that reported success without compiling anything would be the same
/// class of mistake this test exists to catch.
///
/// ## Why the probes below cannot be allowed to throw
///
/// `Process.runSync` raises [ProcessException] when the executable does not
/// exist, and **only** returns a non-zero `exitCode` when it ran and failed.
/// Those are different failures, and a caller that checks `exitCode` alone is
/// checking the second while CI only ever produces the first: `flutter.yml` runs
/// on `ubuntu-latest`, where `xcrun` is absent, so the exception propagates out
/// of the test body and turns the whole suite red. Hence every probe here is
/// wrapped, and every wrapper answers with a reason naming what was missing.
///
/// The cost of getting this wrong is the exact asymmetry that matters: on a Mac
/// this test compiles Swift and fails loudly on a real error; on Linux it must
/// say why it could not and move on. Neither may be able to take the other down.
_Typecheck _swiftcTypecheck(List<String> files) {
  final String? sdk = _macosSdkPath();
  if (sdk == null) {
    return (
      compiled: null,
      skippedBecause: 'xcrun reported no usable macOS SDK '
          '(is this ${Platform.operatingSystem}?)',
    );
  }
  // The framework ships as an `.xcframework`; `-F` wants the directory that
  // contains the `.framework`, not the `.framework` itself.
  final String? framework = _flutterFrameworkSlice();
  if (framework == null) {
    return (
      compiled: null,
      skippedBecause: 'no FlutterMacOS.xcframework is cached under '
          '${Platform.environment['HOME']}/dev',
    );
  }
  try {
    return (
      compiled: Process.runSync(
        'xcrun',
        <String>[
          'swiftc',
          '-typecheck',
          '-sdk',
          sdk,
          '-target',
          'arm64-apple-macosx14.0',
          '-F',
          framework,
          ...files,
        ],
      ),
      skippedBecause: '',
    );
  } on ProcessException catch (error) {
    // `xcrun` answered `--show-sdk-path` a moment ago, so this is not the
    // missing-executable case above; it is a toolchain that cannot run a
    // compiler. Still a skip rather than a failure — a Mac with a broken Xcode
    // command line tools should report "could not compile", not "the module is
    // wrong", which it does not know.
    return (
      compiled: null,
      skippedBecause: 'xcrun could not run swiftc (${error.message})',
    );
  }
}

/// The active macOS SDK path, or null when this machine has none to offer.
///
/// The only probe whose answer decides whether the platform is eligible at all,
/// so it is the one that has to distinguish "did not run" from "ran and said no"
/// and survive both. [Platform.isMacOS] is checked first because it is free and
/// cannot be wrong: on Linux `xcrun` is not merely broken but absent, and the
/// platform check states that as a fact rather than inferring it from a failed
/// subprocess.
String? _macosSdkPath() {
  if (!Platform.isMacOS) {
    return null;
  }
  final ProcessResult sdk;
  try {
    sdk = Process.runSync('xcrun', <String>['--show-sdk-path']);
  } on ProcessException {
    // No `xcrun`: a stripped-down macOS install, or a CI image without Xcode
    // selected. Nothing can be compiled, and that is not this test failing.
    return null;
  }
  if (sdk.exitCode != 0) {
    return null;
  }
  final String path = sdk.stdout.toString().trim();
  // An empty path would be passed to `-sdk` and produce a confusing compiler
  // error rather than a skip, so it is refused here where it can be named.
  return path.isEmpty ? null : path;
}

/// The directory holding `FlutterMacOS.framework`, or null when it is not cached.
///
/// Found by looking for the SDK versions this repository is known to build with
/// rather than by shelling out to `flutter`, so the test does not depend on
/// resolving a toolchain — and a stale path here would be a test that silently
/// stops compiling, which is the failure mode it is here to prevent.
String? _flutterFrameworkSlice() {
  final String? home = Platform.environment['HOME'];
  if (home == null) {
    return null;
  }
  for (final String version in <String>['3.47.6', '3.35.6', '3.27.4']) {
    final Directory engine = Directory(
      '$home/dev/flutter-$version/bin/cache/artifacts/engine',
    );
    if (!engine.existsSync()) {
      continue;
    }
    // Three levels, and all three matter:
    //   engine/<platform>/FlutterMacOS.xcframework/<slice>/FlutterMacOS.framework
    // The framework is only found at the fourth, which is the level a
    // single-level-deep search misses — and a lookup that finds nothing is a
    // silent skip, so it is written out rather than collapsed.
    for (final FileSystemEntity platform in engine.listSync()) {
      if (platform is! Directory) {
        continue;
      }
      for (final FileSystemEntity bundle
          in Directory(platform.path).listSync()) {
        if (bundle is! Directory ||
            !bundle.path.endsWith('FlutterMacOS.xcframework')) {
          continue;
        }
        for (final FileSystemEntity slice
            in Directory(bundle.path).listSync()) {
          if (slice is! Directory) {
            continue;
          }
          for (final FileSystemEntity framework
              in Directory(slice.path).listSync()) {
            if (framework is Directory && framework.path.endsWith('.framework')) {
              // The directory *containing* the framework, which is what `-F` wants.
              return slice.path;
            }
          }
        }
      }
    }
  }
  return null;
}

/// The channel tests proper, split out only so the typecheck above can stand
/// first in the file: it is a different kind of check, and reading it as part of
/// the seam's story would be misleading.
void _channelTests() {
  group('the channel', () {
  TestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannel channel =
      MethodChannel(MethodChannelMacosNative.methodChannelName);
  final List<MethodCall> calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
      calls.add(call);
      switch (call.method) {
        case 'findTargetWindow':
          return '77';
        case 'capture':
          return <String, Object?>{
            'ok': true,
            'pixels': Uint8List.fromList(<int>[9, 8, 7, 6]),
            'width': 2,
            'height': 1,
            'scaleX': 2,
            'scaleY': 1,
            'originX': 10,
            'originY': 20,
          };
        case 'recognize':
          return <Object?>[
            <String, Object?>{
              'text': '你好',
              'confidence': 0.98,
              'left': 1.0,
              'top': 2.0,
              'right': 3.0,
              'bottom': 4.0,
            },
          ];
        case 'inject':
          return <String, Object?>{'verified': true, 'text': '好的'};
        case 'panelGeometry':
          return <String, Object?>{
            'screen': <String, Object?>{
              'left': 0.0, 'top': 0.0, 'right': 1440.0, 'bottom': 900.0,
            },
            'window': <String, Object?>{
              'left': 0.0, 'top': 0.0, 'right': 400.0, 'bottom': 600.0,
            },
          };
        case 'panel.hide':
          return true;
        case 'storage.resourceRoot':
          return '/Applications/miaotou_app.app/Contents/Resources';
        case 'storage.containerDirectory':
          return '/Users/someone/Library/Containers/com.miaotoujunshi/'
              'miaotouApp/Data/Library/Application Support/'
              'com.miaotoujunshi.miaotouApp';
        case 'keychain.read':
          return (calls.last.arguments! as Map<Object?, Object?>)['key'] == 'deepseek'
              ? 'sk-stored'
              : null;
        case 'keychain.keys':
          return <String>['deepseek', 'jev'];
        default:
          return null;
      }
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('the channel names are the ones the Swift registers', () {
    expect(MethodChannelMacosNative.methodChannelName, 'miaotoujunshi/macos');
    expect(MethodChannelMacosNative.eventChannelName, 'miaotoujunshi/macos/events');
  });

  test('a frame crosses the channel with its geometry intact', () async {
    final MethodChannelMacosNative native = MethodChannelMacosNative();

    final CaptureOutcome outcome =
        await native.capture(targetWindowId: '77');

    expect(calls.single.method, 'capture');
    expect((calls.single.arguments as Map<Object?, Object?>)['windowId'], '77');
    final CaptureFrame frame = (outcome as CaptureOk).frame;
    expect(frame.width, 2);
    expect(frame.height, 1);
    expect(frame.scaleX, 2);
    expect(frame.originY, 20);
    expect(frame.pixels, <int>[9, 8, 7, 6]);
    expect(frame.region.width, 1, reason: 'a point of bitmap is half a point of screen');
  });

  test('a refused capture is a value carrying the platform\'s own code', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async =>
            <String, Object?>{'ok': false, 'code': 3, 'message': '截屏失败：没有可截取的显示器'});

    final CaptureOutcome outcome = await MethodChannelMacosNative().capture();

    expect((outcome as CaptureFailed).code, 3);
    expect(outcome.message, contains('没有可截取的显示器'));
  });

  test('a recognised line crosses as text and a rectangle', () async {
    final List<OcrLine> lines = await MethodChannelMacosNative().recognize(
      CaptureFrame(
        pixels: Uint8List(4),
        width: 2,
        height: 1,
        scaleX: 1,
        scaleY: 1,
        originX: 0,
        originY: 0,
      ),
      languages: const <String>['zh-Hans'],
    );

    expect(lines.single.text, '你好');
    expect(lines.single.bounds, const ScreenRect(left: 1, top: 2, right: 3, bottom: 4));
  });

  test('every method the Dart calls is a case the Swift implements', () {
    final String swift = File(
      'macos/miaotou_capabilities_macos/Sources/miaotou_capabilities_macos/'
      'MiaotouMacosPlugin.swift',
    ).readAsStringSync();

    for (final String method in <String>[
      'findTargetWindow',
      'capture',
      'recognize',
      'inject',
      'panelGeometry',
      'panel.show',
      'panel.hide',
      'panel.restore',
      'panel.focusable',
      'storage.resourceRoot',
      'storage.containerDirectory',
      'keychain.read',
      'keychain.write',
      'keychain.delete',
      'keychain.keys',
    ]) {
      expect(
        swift,
        contains('case "$method"'),
        reason: 'the Dart side calls "$method"; a Swift that does not implement it '
            'answers FlutterMethodNotImplemented and nothing else would say so',
      );
    }
    expect(
      swift,
      contains('static let methodChannelName = "${MethodChannelMacosNative.methodChannelName}"'),
      reason: 'a renamed channel is a MissingPluginException on a machine where '
          'nobody is watching',
    );
  });

  test('the native half of this port cannot send anything', () {
    // The promise PRIVACY.md makes and the contract repeats: there is no member
    // that sends, and none may be added. These three are the ways a macOS
    // process can put a message in a chat — a synthesised keystroke, an
    // accessibility press, and writing the pasteboard and hoping.
    const String sources = 'macos/miaotou_capabilities_macos/Sources/'
        'miaotou_capabilities_macos';
    for (final String file in <String>[
      'AccessibilityDraft.swift',
      'ChatWindowCapture.swift',
      'FloatingPanelHost.swift',
      'MiaotouMacosPlugin.swift',
      'VisionTextReader.swift',
    ]) {
      final String source = File('$sources/$file').readAsStringSync();
      for (final String forbidden in <String>[
        'CGEvent',
        'AXUIElementPerformAction',
        'kAXPressAction',
        'NSPasteboard',
        'kCGEventKeyDown',
      ]) {
        expect(
          source,
          isNot(contains(forbidden)),
          reason: '$file reaches for $forbidden. A draft is written into an '
              'accessibility text area and read back; anything that could reach '
              'the return key is a send path, and this port must never grow one',
        );
      }
    }
  });
  });
}
