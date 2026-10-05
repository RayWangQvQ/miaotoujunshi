/// The system permissions this application cannot work without, and the state
/// each of them is in.
///
/// **Only Android has both.** The floating panel needs the display-over-other-apps
/// grant, and reading a chat window's own text needs the accessibility service
/// bound. The two desktop ports read pixels instead of a node tree and own their
/// own windows outright, so they have no equivalent of either — which is why
/// `Permissions` is the one interface in this contract that a desktop port
/// refuses permanently rather than a member it answers differently.
///
/// See ADR-0021 for why this is a contract member at all rather than an
/// Android-only channel behind a `Platform.isAndroid` branch.
library;

/// One system permission this application may need.
///
/// Two values, and neither of them is 自启动/省电无限制. That one is a property
/// of an OEM ROM rather than of a platform, the system exposes no way to read it,
/// and reaching its settings page needs a table of vendor component names that
/// this version deliberately does not carry. It is explained to the user as
/// prose and nothing else (ADR-0021).
enum PermissionKind {
  /// The accessibility service that reads the active chat window's text.
  ///
  /// Without it the Android bridge cannot answer a capture at all: it raises
  /// `accessibility_service_unavailable` before any capture machinery runs.
  accessibility,

  /// Drawing the floating panel over another application.
  overlay,
}

/// Whether a permission currently does its job.
///
/// Three values rather than a boolean because [accessibility] has two separate
/// facts behind it — the user moved the switch in the system settings, and the
/// platform actually bound the service — and 「勾了但没起来」 is a real state a
/// user can be looking at while the app says nothing is wrong. A boolean would
/// report that state as `off`, which is the failure ADR-0018's device run was
/// read as.
enum PermissionState {
  /// Not granted at all.
  off,

  /// Granted in the system, but not currently in effect.
  ///
  /// The accessibility switch is on and the service is not bound: the platform
  /// has not started it, a ROM has frozen the process, or the grant was made
  /// while this process was already running. The remedy is to come back and
  /// retry, not to grant it again.
  inactive,

  /// Granted and in effect.
  ready,
}

/// What every permission this port knows about is doing.
///
/// The value of this type is the constructor: it takes every kind by name and
/// has no defaults, exactly as `CapabilitySet` does, so a port cannot answer for
/// one permission by quietly omitting the other. A `Map<PermissionKind, …>`
/// would have been the shorter shape and the one that hides a missing key.
final class PermissionReport {
  const PermissionReport({
    required this.accessibility,
    required this.overlay,
  });

  final PermissionState accessibility;

  /// Never [PermissionState.inactive]: `Settings.canDrawOverlays` has no middle
  /// state, and a port that answered one would be inventing it.
  final PermissionState overlay;

  PermissionState stateOf(PermissionKind kind) => switch (kind) {
    PermissionKind.accessibility => accessibility,
    PermissionKind.overlay => overlay,
  };

  @override
  String toString() =>
      'PermissionReport(accessibility: ${accessibility.name}, '
      'overlay: ${overlay.name})';
}

/// The system permissions this port can read and take the user to.
///
/// **It reads and it opens; it does not ask.** There is deliberately no
/// `request(kind)` returning a result, because on Android there is nothing to
/// return: `ACTION_ACCESSIBILITY_SETTINGS` and `ACTION_MANAGE_OVERLAY_PERMISSION`
/// open a system page, the user may grant, grant and come back, or leaf through
/// and come back unchanged, and the launch reports none of it. A `request` would
/// be a promise the platform cannot keep — see ADR-0021, and ADR-0016 for the
/// macOS case where asking *is* possible and is therefore a different member.
///
/// State is **read, never inferred**: nothing here is derived from what the
/// application believes it configured. And the Android component name this
/// compares against stays inside the Kotlin implementation — a caller receives
/// [PermissionKind] and [PermissionState] and never a package or a class name.
abstract interface class Permissions {
  /// What every permission this port has is doing, right now.
  Future<PermissionReport> read();

  /// Takes the user to the system page for [kind].
  ///
  /// A port that has no such page names one through [kind] rather than throwing:
  /// every value of [PermissionKind] is one that port reported a state for.
  Future<void> openSettings(PermissionKind kind);
}
