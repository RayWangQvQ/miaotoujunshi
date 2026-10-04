import 'package:flutter_test/flutter_test.dart';
import 'package:miaotou_capabilities/miaotou_capabilities.dart';
import 'package:miaotou_capabilities_macos/miaotou_capabilities_macos.dart';
import 'package:miaotou_capabilities_macos/testing.dart';



/// The three properties #14 asks for that are statements about **order**.
///
/// A capture that photographs the panel analyses the panel as if the user had
/// said it; a restore that does not happen leaves a panel that vanished; a
/// restore that happens when it should not puts back a window the user closed.
/// None of the three is visible in a return value, so the fake records the calls
/// it received in the order they arrived and these tests read that list.
void main() {
  late FakeMacosNative native;
  late MacosFloatingPanel panel;
  late MacosScreenCapture capture;
  late CapturePacing pacing;
  DateTime now = DateTime(2026, 10, 4, 12);

  setUp(() {
    now = DateTime(2026, 10, 4, 12);
    native = FakeMacosNative();
    panel = MacosFloatingPanel(native);
    pacing = CapturePacing(clock: () => now);
    capture = MacosScreenCapture(native, panel, pacing: pacing);
  });

  test('the panel leaves the screen before the frame and comes back after', () async {
    native.panelUp = true;

    final CaptureOutcome outcome = await capture.capture(targetWindowId: '77');

    expect(outcome, isA<CaptureOk>());
    expect(
      native.log,
      <String>['hide', 'capture:77', 'restore'],
      reason: 'a window captured with the panel on top of it returns the panel',
    );
    expect(native.panelUp, isTrue, reason: 'the panel must be given back');
  });

  test('a failed capture still gives the panel back', () async {
    native.panelUp = true;
    native.captureOutcome = const CaptureFailed(code: 2, message: '窗口不在了');

    final CaptureOutcome outcome = await capture.capture(targetWindowId: '77');

    expect((outcome as CaptureFailed).code, 2);
    expect(native.log, containsAllInOrder(<String>['hide', 'capture:77', 'restore']));
    expect(native.panelUp, isTrue);
  });

  test('a panel that was already down is not brought back', () async {
    native.panelUp = false;

    await capture.capture(targetWindowId: '77');

    expect(native.log, <String>['hide', 'capture:77']);
    expect(
      native.panelUp,
      isFalse,
      reason: 'restoring a panel the user closed would be a window that reappears '
          'by itself',
    );
  });

  test('a throttled capture neither hides the panel nor reaches the system', () async {
    native.panelUp = true;
    await capture.capture(targetWindowId: '77');
    native.log.clear();

    final CaptureOutcome second = await capture.capture(targetWindowId: '77');

    expect((second as CaptureFailed).code, CapturePacing.throttledCode);
    expect(native.log, isEmpty);
    expect(native.panelUp, isTrue, reason: 'the first capture brought it back, and '
        'the second must not have taken it away');
  });

  test('the window the caller chose is the window that is captured', () async {
    native.panelUp = true;
    await capture.capture(targetWindowId: '4242');
    expect(native.log, contains('capture:4242'));

    // And the handle is found once, not re-asked per frame: this port's chat
    // application keeps several windows of the same size, and re-choosing makes
    // the target jump between conversations.
    native.log.clear();
    now = now.add(const Duration(seconds: 1));
    final String? handle = await capture.findTargetWindow();
    now = now.add(const Duration(seconds: 1));
    await capture.capture(targetWindowId: handle);
    expect(native.log, <String>['findTargetWindow', 'hide', 'capture:77', 'restore']);
  });

  test('a draft goes to the named window, and only a read-back counts as landing',
      () async {
    final MacosTextInject inject = MacosTextInject(native);
    native.injectResult = const InjectResult.unverified('写入后没读到内容');

    final InjectResult unverified = await inject.inject(
      '好的，马上',
      target: const InjectTarget(windowId: '77'),
    );

    expect(unverified.verifiedLanding, isFalse);
    expect(native.log, <String>['inject:77']);
    expect(native.injectedText, '好的，马上');
  });

  test('a drag is snapped, remembered and put back where it belongs', () async {
    native.panelUp = true;
    final Stream<PanelEvent> events = panel.events;
    final List<PanelEvent> seen = <PanelEvent>[];
    final sub = events.listen(seen.add);

    native.emit(
      NativePanelDragged(
        window: const ScreenRect(left: 1200, top: 200, right: 1240, bottom: 240),
        screen: const ScreenRect(left: 0, top: 0, right: 1440, bottom: 900),
      ),
    );
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(seen.single, isA<PanelDragged>());
    expect((seen.single as PanelDragged).x, 1400, reason: '100 from the right edge');
    expect(
      native.log.last,
      'show:at',
      reason: 'the snap has to be applied to the window, not merely reported',
    );
    await sub.cancel();
  });

  test('the panel is focusable on request and inert otherwise', () async {
    await panel.setFocusable(true);
    expect(native.focusable, isTrue);
    await panel.setFocusable(false);
    expect(native.focusable, isFalse);
  });
}
