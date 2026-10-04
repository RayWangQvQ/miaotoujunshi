import 'dart:io';

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
}
