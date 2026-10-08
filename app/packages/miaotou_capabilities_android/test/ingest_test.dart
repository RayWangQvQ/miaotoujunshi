import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miaotou_capabilities/miaotou_capabilities.dart';
import 'package:miaotou_capabilities_android/miaotou_capabilities_android.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannel control = MethodChannel(
    MethodChannelAndroidIngestNative.controlChannelName,
  );

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(control, null);
  });

  test('uses the specified ingest and control channel names', () {
    expect(
      MethodChannelAndroidIngestNative.ingestChannelName,
      'miaotou/ingest',
    );
    expect(
      MethodChannelAndroidIngestNative.controlChannelName,
      'miaotou/control',
    );
  });

  test('control channel preserves missing conversation parts', () async {
    final List<MethodCall> calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(control, (MethodCall call) async {
          calls.add(call);
          return null;
        });

    final MethodChannelAndroidIngestNative native =
        MethodChannelAndroidIngestNative();
    await native.bindConversation(
      const ConversationRef(packageName: 'com.tencent.mobileqq'),
    );
    await native.setOverlayFlag(AndroidOverlayFlag.focusable, true);
    await native.restoreAfterCapture();

    expect(calls[0].method, 'bindConversation');
    expect(calls[0].arguments, <String, Object?>{
      'packageName': 'com.tencent.mobileqq',
    });
    expect(calls[1].method, 'setOverlayFlag');
    expect(calls[1].arguments, <String, Object?>{
      'flag': 'focusable',
      'value': true,
    });
    expect(calls[2].method, 'restore');
  });

  test('capture decodes pixels and window geometry', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(control, (MethodCall call) async {
          expect(call.method, 'capture');
          expect(call.arguments, <String, Object?>{'targetWindowId': '42'});
          return <String, Object?>{
            'ok': true,
            'pixels': Uint8List.fromList(<int>[1, 2, 3]),
            'width': 30,
            'height': 40,
            'scaleX': 2.0,
            'scaleY': 2.5,
            'originX': 5.0,
            'originY': 7.0,
          };
        });

    final CaptureOutcome outcome = await MethodChannelAndroidIngestNative()
        .capture(targetWindowId: '42');

    expect(outcome, isA<CaptureOk>());
    final CaptureFrame frame = (outcome as CaptureOk).frame;
    expect(frame.pixels, <int>[1, 2, 3]);
    expect(frame.region, const ScreenRect.fromLTWH(5, 7, 15, 16));
  });

  test('tree reader consumes pushed snapshots without polling', () async {
    final StreamController<AndroidIngestEvent> events =
        StreamController<AndroidIngestEvent>();
    final _FakeIngestNative native = _FakeIngestNative(events.stream);
    final AndroidUiTreeReader reader = AndroidUiTreeReader(native);
    final ChatUiSnapshot snapshot = ChatUiSnapshot(
      conversation: const ConversationRef(
        packageName: 'com.tencent.mobileqq',
        title: '张三',
      ),
      lines: const <ChatLine>[ChatLine(speaker: Speaker.other, text: '你好')],
      capturedAt: DateTime.utc(2026, 10, 5),
    );

    final Future<ChatUiSnapshot> pushed = reader.snapshots.first;
    events.add(AndroidSnapshotEvent(snapshot));

    expect(await pushed, same(snapshot));
    expect(native.readCount, 0);
    await events.close();
  });

  test('tree reader publishes conversation-only changes', () async {
    final StreamController<AndroidIngestEvent> events =
        StreamController<AndroidIngestEvent>();
    final AndroidUiTreeReader reader = AndroidUiTreeReader(
      _FakeIngestNative(events.stream),
    );
    const ConversationRef conversation = ConversationRef(
      packageName: 'com.ss.android.lark',
      appName: '飞书',
      title: '另一个会话',
    );

    final Future<ChatUiSnapshot> pushed = reader.snapshots.first;
    events.add(
      const AndroidConversationEvent(
        current: conversation,
        bound: null,
        readOnly: true,
      ),
    );

    final ChatUiSnapshot snapshot = await pushed;
    expect(snapshot.conversation, conversation);
    expect(
      snapshot.conversation.appName,
      '飞书',
      reason:
          'the service resolves the name while it has the Context and the '
          'reference carries it across (ADR-0028)',
    );
    expect(snapshot.lines, isEmpty);
    await events.close();
  });
}

final class _FakeIngestNative implements AndroidIngestNative {
  _FakeIngestNative(this.events);

  @override
  final Stream<AndroidIngestEvent> events;
  int readCount = 0;

  @override
  Future<ChatUiSnapshot?> readActiveChat() async {
    readCount++;
    return null;
  }

  @override
  Future<void> bindConversation(ConversationRef conversation) async {}

  @override
  Future<CaptureOutcome> capture({String? targetWindowId}) async =>
      const CaptureFailed(code: -1, message: 'unused');

  @override
  Future<String?> findTargetWindow() async => null;

  @override
  Future<void> hideForCapture() async {}

  @override
  Future<InjectResult> inject(
    String text, {
    required InjectTarget target,
  }) async => const InjectResult.unverified('unused');

  @override
  Future<List<OcrLine>> recognize(
    CaptureFrame frame, {
    required List<String> languages,
  }) async => const <OcrLine>[];

  @override
  Future<void> restoreAfterCapture() async {}

  @override
  Future<void> setOverlayFlag(AndroidOverlayFlag flag, bool value) async {}
}
