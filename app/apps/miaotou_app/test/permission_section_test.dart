import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miaotou_app/src/design/copy.dart';
import 'package:miaotou_app/src/design/theme.dart';
import 'package:miaotou_app/src/shell/permission_section.dart';
import 'package:miaotou_app/src/widgets/status_badge.dart';
import 'package:miaotou_capabilities/miaotou_capabilities.dart';
import 'package:miaotou_capabilities/testing.dart';

/// ADR-0021's surface, tested without a device.
///
/// The retired Kotlin port's 权限设置 section was three hand-written cards in an
/// `Activity`, and the reason it took a device to find out whether it worked was
/// that it *was* an `Activity`. The two facts this section is built on are both
/// values — what `Permissions.read` answered, and what `openSettings` was asked
/// for — so both can be pinned here: the state a user cannot reach without a
/// real ROM (「勾了但没起起来」) and the four ways a port can fail to answer.
void main() {
  const PermissionReport grantBoth = PermissionReport(
    accessibility: PermissionState.ready,
    overlay: PermissionState.ready,
  );

  group('the three rows', () {
    testWidgets('each permission states its own state', (
      WidgetTester tester,
    ) async {
      await _pump(
        tester,
        InMemoryPermissions(
          report: const PermissionReport(
            accessibility: PermissionState.ready,
            overlay: PermissionState.off,
          ),
        ),
      );

      // Two badges rather than one: a user who has granted one of the two needs
      // to be told which one, and a single ready/not-ready line cannot say it.
      expect(find.byType(StatusBadge), findsNWidgets(2));
      expect(
        _badgeText(tester, 'permission-accessibility-state'),
        AppCopy.zh.text(CopyKey.settingsPermissionStateReady),
      );
      expect(
        _badgeText(tester, 'permission-overlay-state'),
        AppCopy.zh.text(CopyKey.settingsPermissionStateOff),
      );
    });

    testWidgets('ticked but not bound is named, not reported as off', (
      WidgetTester tester,
    ) async {
      // The state ADR-0018's device run was in: the switch is on, the service is
      // not bound, and a boolean would call this 「未开启」 to a user looking at
      // the switch they just turned on.
      await _pump(
        tester,
        InMemoryPermissions(
          report: const PermissionReport(
            accessibility: PermissionState.inactive,
            overlay: PermissionState.ready,
          ),
        ),
      );

      expect(
        _badgeText(tester, 'permission-accessibility-state'),
        AppCopy.zh.text(CopyKey.settingsPermissionStateInactive),
      );
      expect(
        find.text(AppCopy.zh.text(CopyKey.settingsPermissionStateOff)),
        findsNothing,
      );
      expect(
        _badgeTone(tester, 'permission-accessibility-state'),
        StatusTone.caution,
        reason: 'the switch is on and the service still is not running, which is '
            'the one thing here that is wrong rather than merely unset',
      );
    });

    testWidgets('the autostart row is prose and nothing else', (
      WidgetTester tester,
    ) async {
      await _pump(tester, InMemoryPermissions(report: grantBoth));

      final Finder row = find.byKey(const Key('permission-autostart'));
      expect(row, findsOneWidget);
      expect(
        find.descendant(of: row, matching: find.byType(StatusBadge)),
        findsNothing,
        reason: 'it would report a state no portable API can read (ADR-0021 '
            'decision 7)',
      );
      expect(
        find.descendant(of: row, matching: find.byType(OutlinedButton)),
        findsNothing,
        reason: 'the vendor table that would make it a real jump is recorded as '
            'deferred, so this row must not pretend to be one',
      );
      expect(
        find.text(AppCopy.zh.text(CopyKey.settingsPermissionAutostartHint)),
        findsOneWidget,
      );
    });
  });

  group('the jump', () {
    testWidgets('each row opens its own page and no other', (
      WidgetTester tester,
    ) async {
      final InMemoryPermissions permissions = InMemoryPermissions(
        report: grantBoth,
      );
      await _pump(tester, permissions);

      await tester.tap(find.byKey(const Key('permission-overlay-open')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('permission-accessibility-open')));
      await tester.pumpAndSettle();

      expect(permissions.opened, <PermissionKind>[
        PermissionKind.overlay,
        PermissionKind.accessibility,
      ]);
    });

    testWidgets('the button is there even when the state says ready', (
      WidgetTester tester,
    ) async {
      // Not hidden on a granted permission: `inactive` needs the page as much as
      // `off` does — more, because the switch already looks on — and this widget
      // deciding otherwise would be it second-guessing a state it only just read.
      await _pump(tester, InMemoryPermissions(report: grantBoth));

      expect(find.byKey(const Key('permission-accessibility-open')), findsOneWidget);
      expect(find.byKey(const Key('permission-overlay-open')), findsOneWidget);
    });

    testWidgets('a jump that fails says so', (WidgetTester tester) async {
      // Reads fine and cannot open: the state is readable and the remedy is not,
      // which is its own combination and the one a tap has to survive.
      await _pump(tester, const _DeafJumpPermissions());

      await tester.tap(find.byKey(const Key('permission-overlay-open')));
      await tester.pumpAndSettle();

      expect(
        find.text(AppCopy.zh.text(CopyKey.settingsPermissionOpenFailed)),
        findsOneWidget,
        reason: 'the jump is the row’s whole purpose; a tap that does nothing is '
            'indistinguishable from a tap that did not register',
      );
    });
  });

  group('the state is re-read', () {
    testWidgets('coming back to the foreground asks again', (
      WidgetTester tester,
    ) async {
      final InMemoryPermissions permissions = InMemoryPermissions(
        report: const PermissionReport(
          accessibility: PermissionState.off,
          overlay: PermissionState.off,
        ),
      );
      await _pump(tester, permissions);
      expect(
        _badgeText(tester, 'permission-accessibility-state'),
        AppCopy.zh.text(CopyKey.settingsPermissionStateOff),
      );

      // What happens while the user is away: they turned the service on in the
      // system settings, which is the only way this value ever changes.
      permissions.report = grantBoth;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      expect(
        _badgeText(tester, 'permission-accessibility-state'),
        AppCopy.zh.text(CopyKey.settingsPermissionStateReady),
        reason: 'a value read only on entry is stale at exactly the moment the '
            'user comes back to check it (ADR-0021 decision 9)',
      );
    });
  });

  group('a port that has no such permission', () {
    testWidgets('says so rather than looking broken', (
      WidgetTester tester,
    ) async {
      // macOS and Windows refuse both members permanently (ADR-0021 decision 6).
      // The section is still on their settings page, and it has to say why
      // rather than render two rows that will never change.
      await _pump(tester, const _RefusingPermissions());

      expect(
        find.text(AppCopy.zh.text(CopyKey.settingsPermissionUnavailable)),
        findsOneWidget,
      );
      expect(find.byType(StatusBadge), findsNothing);
      expect(
        find.text(AppCopy.zh.text(CopyKey.settingsPermissionReadFailed)),
        findsNothing,
        reason: 'a platform statement and a defect are two different sentences',
      );
    });

    testWidgets('a port that threw is not called unsupported', (
      WidgetTester tester,
    ) async {
      await _pump(tester, const _DeafPermissions());

      expect(
        find.text(AppCopy.zh.text(CopyKey.settingsPermissionReadFailed)),
        findsOneWidget,
      );
      expect(
        find.text(AppCopy.zh.text(CopyKey.settingsPermissionUnavailable)),
        findsNothing,
      );
    });
  });
}

Future<void> _pump(
  WidgetTester tester,
  Permissions permissions, {
  AppCopy copy = AppCopy.zh,
}) async {
  await tester.pumpWidget(
    CopyScope(
      copy: copy,
      child: MaterialApp(
        theme: buildTheme(),
        home: Scaffold(body: PermissionSection(permissions: permissions)),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

String _badgeText(WidgetTester tester, String key) =>
    tester.widget<StatusBadge>(find.byKey(Key(key))).label;

StatusTone _badgeTone(WidgetTester tester, String key) =>
    tester.widget<StatusBadge>(find.byKey(Key(key))).tone;

/// A port that has the two members and refuses them, as both desktop ports do.
final class _RefusingPermissions implements Permissions {
  const _RefusingPermissions();

  @override
  Future<PermissionReport> read() async => unsupportedOnThisPlatform(
    platform: 'this test',
    member: 'Permissions.read',
    reason: 'the two permissions are Android-specific',
  );

  @override
  Future<void> openSettings(PermissionKind kind) async =>
      unsupportedOnThisPlatform(
        platform: 'this test',
        member: 'Permissions.openSettings(${kind.name})',
        reason: 'the two permissions are Android-specific',
      );
}

/// A port that has them, is asked, and throws something that is not a refusal.
///
/// Deliberately not an `UnsupportedError`: the distinction the section draws is
/// between "this port does not have these" and "this port did not answer", and a
/// double that threw the first would test the wrong sentence.
final class _DeafPermissions implements Permissions {
  const _DeafPermissions();

  @override
  Future<PermissionReport> read() async => throw StateError('the channel is gone');

  @override
  Future<void> openSettings(PermissionKind kind) async =>
      throw StateError('the channel is gone');
}

/// A port whose state reads and whose page does not open.
///
/// The combination a real device reaches most easily: the plugin answers for the
/// state on the Flutter channel and the launch itself is refused by the
/// platform, which is a different call with a different failure.
final class _DeafJumpPermissions implements Permissions {
  const _DeafJumpPermissions();

  @override
  Future<PermissionReport> read() async => const PermissionReport(
    accessibility: PermissionState.ready,
    overlay: PermissionState.ready,
  );

  @override
  Future<void> openSettings(PermissionKind kind) async =>
      throw StateError('no activity to launch from');
}
