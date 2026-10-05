import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miaotou_app/src/panel/protocol.dart';
import 'package:miaotou_app/src/runtime/model_settings.dart';
import 'package:miaotou_app/src/runtime/panel_settings.dart';
import 'package:miaotou_app/src/shell/destination.dart';
import 'package:miaotou_capabilities/miaotou_capabilities.dart';
import 'package:miaotou_capabilities/testing.dart';

import 'support/harness.dart';

/// The panel's fill is a setting now, and the two halves of that sentence are
/// what these tests are about: where the value is kept, and how a slider in the
/// main window reaches a panel that is drawn by a second engine.
///
/// ADR-0020 decides both. The value lives in [Preferences] under `panel.` and
/// nowhere else — the panel engine has no store to read — and the slider writes
/// it on its own rather than through the settings page's save button, because
/// that path rebuilds a [ModelSettings] from `defaults` and would take four
/// analysis fields with it.
void main() {
  group('the appearance value', () {
    test('is clamped to the range rather than refused', () {
      expect(
        PanelAppearance.percent(5).opacity,
        PanelAppearance.minOpacity,
        reason: 'the floor is the ball: at zero the fill and the handle drawn '
            'with it would both disappear',
      );
      expect(PanelAppearance.percent(900).opacity, PanelAppearance.maxOpacity);
      expect(PanelAppearance.percent(60).opacity, 60);
      expect(PanelAppearance.percent(60).fillAlpha, closeTo(0.6, 0.0001));
    });

    test('the default is what an untouched panel paints', () {
      expect(const PanelAppearance().opacity, PanelAppearance.defaultOpacity);
    });

    test('equality is the percentage, so a push of the same value is a no-op', () {
      expect(
        const PanelAppearance(opacity: 60),
        PanelAppearance.percent(60),
        reason: 'the session drops a re-publish of the value it already holds, '
            'and that is only correct if two equal percentages are equal',
      );
      expect(
        const PanelAppearance(opacity: 60) == const PanelAppearance(opacity: 61),
        isFalse,
      );
    });
  });

  group('the panel settings', () {
    test('an untouched store is the default and no placement at all', () async {
      final PanelSettings settings = await PanelSettings.load(
        InMemoryPreferences(),
      );

      expect(settings.appearance.opacity, PanelAppearance.defaultOpacity);
      expect(
        settings.placement,
        isNull,
        reason: 'null is not (0, 0): the ports pick their own first-run corner, '
            'and telling them to go to the origin would park the panel in the '
            'top-left on every machine that has never dragged it',
      );
    });

    test('both keys survive a write and a read', () async {
      final InMemoryPreferences preferences = InMemoryPreferences();
      await PanelSettings.saveAppearance(
        preferences,
        const PanelAppearance(opacity: 55),
      );
      await PanelSettings.savePlacement(
        preferences,
        const PanelPlacement(anchor: PanelAnchor.free, dx: 12.5, dy: 340),
      );

      final PanelSettings settings = await PanelSettings.load(preferences);
      expect(settings.appearance.opacity, 55);
      expect(settings.placement?.anchor, PanelAnchor.free);
      expect(settings.placement?.dx, 12.5);
      expect(
        settings.placement?.dy,
        340,
        reason: 'a fraction survives because the placement is one JSON value; '
            'the Preferences contract has no number type that could hold it',
      );
    });

    test('the placement is one key, not one per port', () async {
      final InMemoryPreferences preferences = InMemoryPreferences();
      await PanelSettings.savePlacement(
        preferences,
        const PanelPlacement(anchor: PanelAnchor.topRight),
      );

      expect(await preferences.keys(), <String>[PanelSettings.placementKey]);
    });

    test('an out-of-range stored value comes back clamped', () async {
      final InMemoryPreferences preferences = InMemoryPreferences(
        values: <String, Object>{PanelSettings.appearanceKey: 5},
      );

      expect(
        (await PanelSettings.load(preferences)).appearance.opacity,
        PanelAppearance.minOpacity,
        reason: 'the range is this build\'s; a value from one that allowed more '
            'is still a percentage and the panel can still be painted with it',
      );
    });

    test('a placement this codebase could not have written is refused', () {
      expect(
        () => PanelSettings.decodePlacement('{"anchor":"middle","dx":0,"dy":0}'),
        throwsFormatException,
        reason:
            'falling back to the default would move the panel to a corner the '
            'user did not choose, silently and unobservably',
      );
      expect(
        () => PanelSettings.decodePlacement('not json at all'),
        throwsFormatException,
      );
      expect(
        () =>
            PanelSettings.decodePlacement('{"anchor":"free","dx":null,"dy":0}'),
        throwsFormatException,
      );
    });
  });

  group('the settings slider', () {
    testWidgets('dragging previews at the panel and letting go writes it', (
      WidgetTester tester,
    ) async {
      final AppHarness harness = AppHarness();
      await pumpApplication(tester, harness);

      final List<PanelAppearance> previewed = <PanelAppearance>[];
      final StreamSubscription<PanelAppearance> previews = harness
          .session
          .panel
          .appearances
          .listen(previewed.add);
      addTearDown(previews.cancel);

      harness.window.navigate(ShellDestination.settings);
      await tester.pumpAndSettle();

      final Finder slider = find.byKey(const Key('settings-panel-opacity'));
      expect(
        tester.widget<Slider>(slider).value,
        PanelAppearance.defaultOpacity.toDouble(),
        reason: 'a store nobody has written opens on the panel\'s own default',
      );

      // Driven by hand rather than with [WidgetTester.drag], because the claim
      // is about the middle of the gesture: the panel takes the new value while
      // the finger is still down, and only the release writes anything.
      final TestGesture gesture = await tester.startGesture(
        tester.getCenter(slider),
      );
      await gesture.moveBy(const Offset(-2000, 0));
      await tester.pump();

      expect(
        previewed,
        isNotEmpty,
        reason: 'the panel is a second window painted by a second engine, so '
            'previewing means pushing the value at it rather than rebuilding a '
            'widget in here',
      );
      expect(previewed.last.opacity, PanelAppearance.minOpacity);
      expect(
        await harness.capabilities.preferences.getInt(
          PanelSettings.appearanceKey,
        ),
        isNull,
        reason: 'a drag that is still happening is not a decision yet',
      );

      await gesture.up();
      await tester.pumpAndSettle();

      expect(
        await harness.capabilities.preferences.getInt(
          PanelSettings.appearanceKey,
        ),
        PanelAppearance.minOpacity,
        reason: 'letting go is what writes it; there is no save button for this',
      );
    });

    testWidgets('and it leaves the analysis fields alone', (
      WidgetTester tester,
    ) async {
      final AppHarness harness = AppHarness();
      await harness.capabilities.preferences
          .setString('analysis.goal', '先接住情绪');
      await pumpApplication(tester, harness);

      harness.window.navigate(ShellDestination.settings);
      await tester.pumpAndSettle();
      await tester.drag(
        find.byKey(const Key('settings-panel-opacity')),
        const Offset(-1000, 0),
      );
      await tester.pumpAndSettle();

      expect(
        await harness.capabilities.preferences.getString('analysis.goal'),
        '先接住情绪',
        reason: 'the slider writes its own key. A slider wired through the '
            'settings page\'s save path would blank goal/tone/length/'
            'candidateCount on the way past, because that path rebuilds a '
            'ModelSettings from defaults',
      );
    });
  });
}
