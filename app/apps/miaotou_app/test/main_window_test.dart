import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miaotou_app/src/shell/destination.dart';
import 'package:miaotou_app/src/shell/detail_page.dart';
import 'package:miaotou_app/src/shell/gallery_page.dart';
import 'package:miaotou_app/src/shell/knowledge_page.dart';
import 'package:miaotou_app/src/shell/main_window.dart';
import 'package:miaotou_app/src/shell/settings_page.dart';
import 'package:miaotou_app/src/shell/trend_page.dart';

import 'support/harness.dart';

/// The main window: four routes in one widget, a shape that follows the width,
/// and a session that outlives both.
///
/// ADR-0012 is the source of all three, and each of them is a claim about
/// *ownership* rather than about drawing — which is why they are asserted here
/// rather than looked at: "the session is still running" is invisible on screen,
/// and "this is a route" is invisible unless somebody checks that no second
/// window was created.
void main() {
  test('the four product surfaces are the navigable destinations', () {
    expect(
      ShellDestination.navigable.map((ShellDestination d) => d.name).toList(),
      <String>['detail', 'trend', 'knowledge', 'settings'],
      reason: 'ADR-0012 names exactly these four as routes in the main window; '
          'a fifth is a page, and a missing one is a window waiting to happen',
    );
  });

  testWidgets('each destination is a page inside the one window', (
    WidgetTester tester,
  ) async {
    final AppHarness harness = AppHarness();
    await pumpApplication(tester, harness);

    // One navigator, and one scaffold: a route, not a window.
    expect(find.byType(Navigator), findsOneWidget);

    final List<Type> pages = <Type>[
      DetailPage,
      TrendPage,
      KnowledgePage,
      SettingsPage,
    ];

    for (int i = 0; i < ShellDestination.navigable.length; i++) {
      harness.window.navigate(ShellDestination.navigable[i]);
      await tester.pumpAndSettle();

      expect(find.byType(Scaffold), findsOneWidget,
          reason: '${ShellDestination.navigable[i].name} must be a body inside '
              'the shell, not a scaffold of its own: two scaffolds is two '
              'app bars, and ADR-0012 gives only the ball and the panel a window');
      expect(find.byType(pages[i]), findsOneWidget,
          reason: '${ShellDestination.navigable[i].name} did not render its '
              'page, so the destination and the route have drifted apart');
    }
  });

  testWidgets('tapping the navigation moves the page', (
    WidgetTester tester,
  ) async {
    final AppHarness harness = AppHarness();
    await pumpApplication(tester, harness);

    expect(find.byType(DetailPage), findsOneWidget,
        reason: 'the shell starts on the detail page');

    await tester.tap(find.text('走势'));
    await tester.pumpAndSettle();
    expect(find.byType(TrendPage), findsOneWidget);
    expect(harness.window.destination, ShellDestination.trend);

    await tester.tap(find.text('知识库'));
    await tester.pumpAndSettle();
    expect(find.byType(KnowledgePage), findsOneWidget);
  });

  testWidgets('settings opens the gallery as a pushed route', (
    WidgetTester tester,
  ) async {
    final AppHarness harness = AppHarness();
    await pumpApplication(tester, harness);

    harness.window.navigate(ShellDestination.settings);
    await tester.pumpAndSettle();
    await tester.tap(find.text('组件陈列'));
    await tester.pumpAndSettle();

    expect(find.byType(GalleryPage), findsOneWidget,
        reason: 'the gallery is a route in this window like everything else');
    // Pushing does not move the destination: the page underneath is settings,
    // and the same page twice in one navigator is a bug a reader would see as a
    // back button that does nothing.
    expect(harness.window.destination, ShellDestination.settings);
  });

  testWidgets('closing the window hides it and leaves the session running', (
    WidgetTester tester,
  ) async {
    final AppHarness harness = AppHarness();
    await pumpApplication(tester, harness);

    expect(harness.window.visible, isTrue);
    expect(find.byType(MainWindowShell), findsOneWidget);

    harness.window.requestClose();
    await tester.pumpAndSettle();

    // A hidden window renders nothing at all, which is what "closed" means once
    // the ball is still on top of the chat.
    expect(find.byType(Scaffold), findsNothing);
    expect(harness.window.visible, isFalse);

    // The two numbers the criterion is written in: the session is up, and
    // nothing has been torn down.
    expect(harness.session.running, isTrue);
    expect(harness.endCount, 0,
        reason: 'closing the window must not end the session; the capture loop, '
            'the credentials and the panel live in the session, not in the '
            'widget that was just hidden (ADR-0012 decision 1)');

    // Even taking the whole tree away changes nothing, which is the proof that
    // the session is not owned by a widget: a `State` that held it would end it
    // in `dispose`.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    expect(harness.session.running, isTrue);
    expect(harness.endCount, 0);
    expect(harness.session.capabilities.describe().length, 11,
        reason: 'the capability set is still whole');

    // The one path that does end it.
    await harness.session.end();
    expect(harness.session.running, isFalse);
    expect(harness.endCount, 1);

    // And it ends once: a second quit must not tear down twice.
    await harness.session.end();
    expect(harness.endCount, 1);
  });

  testWidgets('a hidden window can be shown again', (
    WidgetTester tester,
  ) async {
    final AppHarness harness = AppHarness();
    await pumpApplication(tester, harness);

    harness.window.requestClose();
    await tester.pumpAndSettle();
    expect(find.byType(Scaffold), findsNothing);

    harness.window.requestShow();
    await tester.pumpAndSettle();
    expect(find.byType(Scaffold), findsOneWidget);
    expect(harness.session.running, isTrue);
    expect(harness.endCount, 0);
  });

  testWidgets('narrow: the navigation is a bar along the bottom', (
    WidgetTester tester,
  ) async {
    final AppHarness harness = AppHarness();
    await pumpApplication(tester, harness, size: const Size(420, 900));

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
    expect(find.byType(DetailPage), findsOneWidget,
        reason: 'the page itself does not change with the width; only the '
            'navigation around it does');
  });

  testWidgets('medium: the navigation is a rail with icons only', (
    WidgetTester tester,
  ) async {
    final AppHarness harness = AppHarness();
    await pumpApplication(tester, harness, size: const Size(800, 900));

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(tester.widget<NavigationRail>(find.byType(NavigationRail)).extended,
        isFalse);
    expect(find.byType(NavigationBar), findsNothing);
  });

  testWidgets('wide: the same rail, with its labels', (
    WidgetTester tester,
  ) async {
    final AppHarness harness = AppHarness();
    await pumpApplication(tester, harness, size: const Size(1400, 900));

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(tester.widget<NavigationRail>(find.byType(NavigationRail)).extended,
        isTrue);
    expect(find.byType(NavigationBar), findsNothing);
  });
}
