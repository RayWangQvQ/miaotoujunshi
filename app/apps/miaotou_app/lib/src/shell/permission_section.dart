import 'dart:async';

import 'package:flutter/material.dart';
import 'package:miaotou_capabilities/miaotou_capabilities.dart';

import '../design/colors.dart';
import '../design/copy.dart';
import '../design/spacing.dart';
import '../widgets/status_badge.dart';

/// The system permissions this application cannot work without, and the way to
/// each of their pages.
///
/// This is the Flutter port's replacement for the retired Kotlin port's 权限设置
/// section: it went away with `integrations/jev_android` in `9629f3b` and
/// nothing took its place until ADR-0021. It is **not a preference** — with
/// neither permission granted the application can neither read a conversation
/// nor draw a card — so it sits above every setting rather than among them, and
/// it is the first thing on the page.
///
/// Three rows, and only two of them are permissions:
///
/// * **无障碍权限** — the state, and a button that opens
///   [PermissionKind.accessibility]'s system page.
/// * **悬浮窗权限** — the same for [PermissionKind.overlay].
/// * **自启动 + 省电无限制** — a paragraph. No portable API reads it and this
///   version does not try, so the row states the instruction and asserts nothing
///   about whether the user has followed it (ADR-0021 decision 7, and the vendor
///   table recorded there as deferred rather than rejected).
///
/// **The state is read twice, not once.** `initState` reads it so the section is
/// correct the moment it appears, and the lifecycle observer reads it again on
/// `resumed` — because the only way to change either permission is to leave for
/// a system page, and a user who does that and comes back is the whole reason
/// the section exists (ADR-0021 decision 9). A value read only on entry is stale
/// at exactly the moment it matters, and the retired port rebuilt itself from
/// `onResume` for the same reason.
///
/// Nothing here opens a system page itself: it asks [permissions] to, and the
/// only thing it knows about the page is a [PermissionKind]. That is deliberate
/// — a component name in this file would be an Android detail in the UI layer,
/// which is what ADR-0009 exists to prevent.
class PermissionSection extends StatefulWidget {
  const PermissionSection({super.key, required this.permissions});

  /// The port's answer for both the state and the two jumps.
  ///
  /// One capability rather than two callbacks, because a row is truthful only
  /// when the same object both reports the state and owns the remedy.
  final Permissions permissions;

  @override
  State<PermissionSection> createState() => _PermissionSectionState();
}

/// What the last read did, which is not the same question as what a permission
/// is doing.
///
/// [unavailable] and [failed] both end in the same place visually and mean
/// opposite things: the first is a port that will never have these permissions
/// (macOS and Windows, permanently — ADR-0021 decision 6), the second is a port
/// that has them and did not answer. Collapsing them would make a broken channel
/// look like a platform statement.
enum _Read {
  /// Not answered yet.
  pending,

  /// [PermissionReport] is in hand.
  ready,

  /// The port has no such permission, and says so rather than failing.
  unavailable,

  /// The port was asked and threw something else.
  failed,
}

class _PermissionSectionState extends State<PermissionSection>
    with WidgetsBindingObserver {
  PermissionReport? _report;
  _Read _read = _Read.pending;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_load());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Coming back from a system page is the event this section is built around.
  ///
  /// Only `resumed`: the other states are the user leaving, and re-reading on
  /// the way out would ask a question whose answer cannot have changed.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_load());
    }
  }

  Future<void> _load() async {
    try {
      final PermissionReport report = await widget.permissions.read();
      _settle(report, _Read.ready);
    } on UnsupportedError {
      // A permanent statement about the platform, not a fault: the two desktop
      // ports refuse both members outright (ADR-0009 decision 2, ADR-0021
      // decision 6). The narrower UnimplementedError is also an
      // UnsupportedError, and both land here because this section has nothing
      // different to say about work in flight.
      _settle(null, _Read.unavailable);
    } on Object {
      _settle(null, _Read.failed);
    }
  }

  void _settle(PermissionReport? report, _Read read) {
    if (!mounted) {
      return;
    }
    setState(() {
      _report = report;
      _read = read;
    });
  }

  Future<void> _open(PermissionKind kind) async {
    try {
      await widget.permissions.openSettings(kind);
    } on Object {
      // The jump is the row's whole purpose, so a failure to make it has to be
      // said out loud rather than leaving the tap looking ignored.
      if (mounted) {
        _message(CopyKey.settingsPermissionOpenFailed);
      }
    }
  }

  void _message(CopyKey key) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(CopyScope.of(context).text(key))),
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppCopy copy = CopyScope.of(context);
    final ThemeData theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          copy.text(CopyKey.settingsPermissionSection),
          style: theme.textTheme.titleMedium,
        ),
        AppSpacing.gapS,
        ..._body(copy, theme),
        AppSpacing.gapL,
      ],
    );
  }

  List<Widget> _body(AppCopy copy, ThemeData theme) {
    switch (_read) {
      case _Read.pending:
        // Nothing rather than a spinner: the read resolves in the same frame on
        // every port that implements it, and a spinner that appears and vanishes
        // is a flicker the user learns to ignore.
        return const <Widget>[];
      case _Read.unavailable:
        return <Widget>[_line(copy, theme, CopyKey.settingsPermissionUnavailable)];
      case _Read.failed:
        return <Widget>[_line(copy, theme, CopyKey.settingsPermissionReadFailed)];
      case _Read.ready:
        break;
    }
    final PermissionReport report = _report!;
    return <Widget>[
      _permission(
        id: 'permission-accessibility',
        copy: copy,
        theme: theme,
        title: CopyKey.settingsPermissionAccessibility,
        hint: CopyKey.settingsPermissionAccessibilityHint,
        kind: PermissionKind.accessibility,
        state: report.accessibility,
      ),
      AppSpacing.gapS,
      _permission(
        id: 'permission-overlay',
        copy: copy,
        theme: theme,
        title: CopyKey.settingsPermissionOverlay,
        hint: CopyKey.settingsPermissionOverlayHint,
        kind: PermissionKind.overlay,
        state: report.overlay,
      ),
      AppSpacing.gapS,
      _autostart(copy, theme),
    ];
  }

  Widget _line(AppCopy copy, ThemeData theme, CopyKey key) => Text(
    copy.text(key),
    style: theme.textTheme.bodySmall,
  );

  /// One permission: what it is, what it is doing, and the way to its page.
  ///
  /// The button is rendered in every state rather than only when the permission
  /// is off. A user whose accessibility service is ticked-but-not-bound needs the
  /// page as much as one who never opened it — more, because the switch they are
  /// looking at already says on — and deciding otherwise here would be this
  /// widget second-guessing a state it only just read.
  Widget _permission({
    required String id,
    required AppCopy copy,
    required ThemeData theme,
    required CopyKey title,
    required CopyKey hint,
    required PermissionKind kind,
    required PermissionState state,
  }) => Card(
    key: Key(id),
    margin: EdgeInsets.zero,
    child: Padding(
      padding: AppSpacing.card,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  copy.text(title),
                  style: theme.textTheme.bodyMedium,
                ),
              ),
              StatusBadge(
                key: Key('$id-state'),
                label: copy.text(_stateLabel(state)),
                tone: _stateTone(state),
              ),
            ],
          ),
          AppSpacing.gapXs,
          Text(
            copy.text(hint),
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.of(context).textMuted,
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton(
              key: Key('$id-open'),
              onPressed: () => _open(kind),
              child: Text(copy.text(CopyKey.settingsPermissionOpen)),
            ),
          ),
        ],
      ),
    ),
  );

  /// The one row that is prose.
  ///
  /// No badge and no button, on purpose: it would report a state it cannot read
  /// and offer a jump it cannot make. What it can do is tell the user why the
  /// two permissions above it stop working on some ROMs, which is the part the
  /// system settings will never say.
  Widget _autostart(AppCopy copy, ThemeData theme) => Card(
    key: const Key('permission-autostart'),
    margin: EdgeInsets.zero,
    child: Padding(
      padding: AppSpacing.card,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            copy.text(CopyKey.settingsPermissionAutostart),
            style: theme.textTheme.bodyMedium,
          ),
          AppSpacing.gapXs,
          Text(
            copy.text(CopyKey.settingsPermissionAutostartHint),
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.of(context).textMuted,
            ),
          ),
        ],
      ),
    ),
  );

  /// `off` is a fact and `inactive` is a warning.
  ///
  /// The words already separate them (ADR-0021's last consequence says they have
  /// to), and the tone separates them again for a reader scanning the column:
  /// nothing is broken when a switch is off, and something is wrong when the
  /// switch is on and the service still is not running.
  static StatusTone _stateTone(PermissionState state) => switch (state) {
    PermissionState.ready => StatusTone.positive,
    PermissionState.inactive => StatusTone.caution,
    PermissionState.off => StatusTone.neutral,
  };

  static CopyKey _stateLabel(PermissionState state) => switch (state) {
    PermissionState.ready => CopyKey.settingsPermissionStateReady,
    PermissionState.inactive => CopyKey.settingsPermissionStateInactive,
    PermissionState.off => CopyKey.settingsPermissionStateOff,
  };
}
