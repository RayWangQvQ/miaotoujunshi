import 'package:flutter_test/flutter_test.dart';
import 'package:miaotou_capabilities/miaotou_capabilities.dart';

/// Keeping a dragged window inside the screen, and remembering where it was.
///
/// The panel no longer snaps to an edge: a drag ends where the finger left it,
/// and only the clamp below stops it from being carried off-screen. What used
/// to be the tie case and the "explicit offset beats memory" case are still the
/// two a plausible-looking implementation gets wrong, so both are here.
void main() {
  const ScreenRect screen = ScreenRect(left: 0, top: 0, right: 1440, bottom: 900);
  const ScreenRect ball = ScreenRect(left: 400, top: 300, right: 440, bottom: 340);

  group('the window stays where it was dropped', () {
    test('a window well inside the screen is untouched', () {
      expect(
        EdgeSnap.snap(ball, screen),
        const ScreenRect(left: 400, top: 300, right: 440, bottom: 340),
      );
    });

    test('a window hanging off the left edge is pulled back flush', () {
      final ScreenRect offLeft = const ScreenRect(left: -60, top: 300, right: -20, bottom: 340);
      expect(
        EdgeSnap.snap(offLeft, screen),
        const ScreenRect(left: 0, top: 300, right: 40, bottom: 340),
      );
    });

    test('a window hanging off the right edge is pulled back flush', () {
      final ScreenRect offRight = const ScreenRect(left: 1500, top: 300, right: 1540, bottom: 340);
      expect(
        EdgeSnap.snap(offRight, screen),
        const ScreenRect(left: 1400, top: 300, right: 1440, bottom: 340),
      );
    });

    test('a window dragged above or below the screen is pulled back inside it', () {
      expect(EdgeSnap.snap(ball.translatedBy(0, -400), screen).top, 0);
      expect(EdgeSnap.snap(ball.translatedBy(0, 700), screen).bottom, 900);
    });

    test('a screen with no area is not something to clamp against', () {
      expect(EdgeSnap.snap(ball, ScreenRect.empty), ball);
    });

    test('a window larger than the screen is clamped rather than hanging off it',
        () {
      final ScreenRect huge = const ScreenRect(left: -50, top: 0, right: 4000, bottom: 40);
      final ScreenRect clamped = EdgeSnap.snap(huge, screen);
      expect(clamped.width, lessThanOrEqualTo(screen.width));
      expect(clamped.left, greaterThanOrEqualTo(screen.left));
      expect(clamped.right, lessThanOrEqualTo(screen.right));
    });
  });

  group('the position is remembered for as long as the process lives', () {
    const PanelPlacement free = PanelPlacement(anchor: PanelAnchor.free);

    test('an explicit free position is clamped and kept', () {
      final PanelPositionMemory memory = PanelPositionMemory();
      final ScreenRect? at = memory.resolve(
        placement: const PanelPlacement(anchor: PanelAnchor.free, dx: 340, dy: 300),
        screen: screen,
        size: const ScreenRect(left: 0, top: 0, right: 40, bottom: 40),
      );
      expect(at, isNotNull);
      expect(at!.left, 340, reason: 'the drop point is kept, not snapped to a wall');
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
