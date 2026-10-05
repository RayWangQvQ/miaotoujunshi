import 'package:flutter_test/flutter_test.dart';
import 'package:miaotou_capabilities/miaotou_capabilities.dart';

/// Snapping a dragged window to an edge, and remembering where it was.
///
/// The tie case and the "explicit offset beats memory" case are the two that a
/// plausible-looking implementation gets wrong, so both are here rather than one
/// happy path.
void main() {
  const ScreenRect screen = ScreenRect(left: 0, top: 0, right: 1440, bottom: 900);
  const ScreenRect ball = ScreenRect(left: 400, top: 300, right: 440, bottom: 340);

  group('the edge is chosen by distance, not by which half the window is in', () {
    test('a window nearer the left edge goes flush left', () {
      expect(
        EdgeSnap.snap(ball, screen),
        const ScreenRect(left: 0, top: 300, right: 40, bottom: 340),
      );
    });

    test('a window nearer the right edge goes flush right', () {
      final ScreenRect right = ball.translatedBy(1000, 0);
      expect(
        EdgeSnap.snap(right, screen),
        const ScreenRect(left: 1400, top: 300, right: 1440, bottom: 340),
      );
    });

    test('exactly in the middle resolves left, so the snap reads as a continuation',
        () {
      final ScreenRect centred = const ScreenRect(left: 700, top: 0, right: 740, bottom: 40);
      expect(EdgeSnap.snap(centred, screen).left, 0);
    });

    test('a window dragged above or below the screen is pulled back inside it', () {
      expect(EdgeSnap.snap(ball.translatedBy(0, -400), screen).top, 0);
      expect(EdgeSnap.snap(ball.translatedBy(0, 700), screen).bottom, 900);
    });

    test('a screen with no area is not something to snap against', () {
      expect(EdgeSnap.snap(ball, ScreenRect.empty), ball);
    });

    test('a window larger than the screen is clamped rather than hanging off it',
        () {
      final ScreenRect huge = const ScreenRect(left: -50, top: 0, right: 4000, bottom: 40);
      final ScreenRect snapped = EdgeSnap.snap(huge, screen);
      expect(snapped.width, lessThanOrEqualTo(screen.width));
      expect(snapped.left, greaterThanOrEqualTo(screen.left));
      expect(snapped.right, lessThanOrEqualTo(screen.right));
    });
  });

  group('the position is remembered for as long as the process lives', () {
    const PanelPlacement free = PanelPlacement(anchor: PanelAnchor.free);

    test('an explicit free position is snapped and kept', () {
      final PanelPositionMemory memory = PanelPositionMemory();
      final ScreenRect? at = memory.resolve(
        placement: const PanelPlacement(anchor: PanelAnchor.free, dx: 340, dy: 300),
        screen: screen,
        size: const ScreenRect(left: 0, top: 0, right: 40, bottom: 40),
      );
      expect(at, isNotNull);
      expect(at!.left, 0, reason: '1340 from the left is nearer than 100 from the right');
      expect(memory.remembered, at);
    });

    test('a bare free placement falls back to where the panel was', () {
      final PanelPositionMemory memory = PanelPositionMemory();
      expect(
        memory.resolve(placement: free, screen: screen, size: ball),
        isNull,
        reason: 'nothing remembered yet, so the native side places it',
      );
      memory.remember(const ScreenRect(left: 1400, top: 10, right: 1440, bottom: 50));
      expect(
        memory.resolve(placement: free, screen: screen, size: ball)?.left,
        1400,
      );
    });

    test('a corner anchor is never overridden by the memory', () {
      final PanelPositionMemory memory = PanelPositionMemory();
      memory.remember(const ScreenRect(left: 1400, top: 10, right: 1440, bottom: 50));
      expect(
        memory.resolve(
          placement: const PanelPlacement(anchor: PanelAnchor.topLeft),
          screen: screen,
          size: ball,
        ),
        isNull,
        reason: 'the anchor is a decision somebody made on purpose. Replacing it '
            'with wherever the window happened to be would make the anchor '
            'untestable, which is the only property it has',
      );
    });
  });
}
