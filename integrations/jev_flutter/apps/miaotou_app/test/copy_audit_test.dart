import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miaotou_app/src/design/copy.dart';
import 'package:miaotou_app/src/shell/destination.dart';

import 'support/harness.dart';

/// "Every page uses them", proved rather than intended.
///
/// The instrument is a copy whose every string is one marker, and a content
/// whose every string is the same marker. Render a page with both and every
/// string a person can read is the marker — so a string that is *not* the marker
/// is a string that did not come from the copy file. That is the whole test, and
/// it is why `AppCopy` is a map rather than a class of getters: a test has to be
/// able to replace all of it at once.
///
/// Two surfaces are deliberately outside this audit:
///
/// * **The capability report** renders the contract's own identifiers —
///   `screenCapture.findTargetWindow`, `InMemoryScreenCapture`. Those are names
///   in `miaotou_capabilities`, not prose, and translating them would hide what
///   they point at.
/// * **The domain's rendered sentences** (`intentConfidenceLabel` and the
///   strategy rendering) travel with the domain, because they are part of what
///   the model is told. #11's rule is that copy a page writes lives in
///   `design/copy.dart`; it does not claim the domain's own strings, and the
///   detail page therefore leaves the confidence line to #12.
void main() {
  const String marker = '·';

  testWidgets('every string on the four pages comes from the copy', (
    WidgetTester tester,
  ) async {
    final AppHarness harness = AppHarness();
    await pumpApplication(
      tester,
      harness,
      copy: AppCopy.sentinel(marker),
      content: sentinelContent(marker),
    );

    for (final ShellDestination destination in ShellDestination.navigable) {
      harness.window.navigate(destination);
      await tester.pumpAndSettle();

      final List<String> strays = <String>[
        for (final String text in renderedTexts(tester))
          if (!text.contains(marker)) text,
      ];

      expect(
        strays,
        isEmpty,
        reason: 'on ${destination.name} these strings did not come from '
            'AppCopy: $strays. A literal in a page is a second source of truth '
            'for what the screen says, and the three ports had three of them',
      );
    }
  });

  testWidgets('the gallery is built from the copy too', (
    WidgetTester tester,
  ) async {
    final AppHarness harness = AppHarness();
    await pumpApplication(
      tester,
      harness,
      copy: AppCopy.sentinel(marker),
      content: sentinelContent(marker),
    );

    // Settings, then the first entry in it, which is the gallery. By type and
    // order rather than by text: with a sentinel copy there is no text to find.
    harness.window.navigate(ShellDestination.settings);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(ListTile).first);
    await tester.pumpAndSettle();

    final List<String> strays = <String>[
      for (final String text in renderedTexts(tester))
        if (!text.contains(marker)) text,
    ];

    expect(strays, isEmpty,
        reason: 'the gallery samples come from copy keys rather than from '
            'literals in gallery_page.dart, so that the audit has no hole: '
            '$strays');
  });
}
