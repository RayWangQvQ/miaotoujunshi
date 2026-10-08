/// Which conversation something belongs to: the chat application's package, the
/// name the platform has for it, and the thread title.
///
/// Every field may be absent, and absence is a legitimate state rather than an
/// error (ADR-0002): an OCR capture has no title to read, an application can be
/// showing a transient placeholder title, a package can exist that the system
/// cannot name, and there may be no chat window in front of the user at all.
/// Never infer one field from another, and never treat an absent field as "the
/// same as last time" — a caller says so out loud instead of guessing.
///
/// **The display name travels with the identity** (ADR-0028). A package is what
/// the platform is *told*; a name is what the platform *asks the system* for,
/// and asking is the platform's business (ADR-0002 decision 2). So the
/// resolution happens at the port that owns the platform and arrives here
/// already done — Android asks `PackageManager` through `ChatApps`, and the
/// desktop ports answer null. Nothing downstream holds a resolver, a map or a
/// hand-written table, which is what makes the fallback order in
/// `ConversationLabel` the only place the rule lives.
final class ConversationRef {
  const ConversationRef({
    required this.packageName,
    this.appName,
    this.title,
  });

  /// No chat window is in front of the user.
  static const ConversationRef none = ConversationRef(packageName: '');

  /// The chat application's package name (`com.tencent.mm`) or bundle
  /// identifier. Empty when the application itself is unknown.
  final String packageName;

  /// The name the platform resolved for [packageName] — Android's
  /// `PackageManager` label, Chinese or English as the system has it — or null
  /// when the system could not name the package.
  ///
  /// Deliberately **not** part of the identity: [==] compares the package and
  /// the title, because a name is a rendering attribute *of a package* and two
  /// readings of one conversation must not compare unequal just because one of
  /// them arrived without one. The guard that a fill is read against, and the
  /// read-only flip, both ride on this equality.
  final String? appName;

  /// The thread title as the chat application shows it. Null or blank when it
  /// could not be read.
  final String? title;

  /// True only when both halves of the identity are present. This is what a fill
  /// may be guarded on; it is not a licence to guess either half.
  bool get isIdentified =>
      packageName.trim().isNotEmpty && (title?.trim().isNotEmpty ?? false);

  /// True when nothing at all is known — no chat window in front.
  bool get isNone => packageName.trim().isEmpty && (title?.trim().isEmpty ?? true);

  @override
  bool operator ==(Object other) =>
      other is ConversationRef &&
      other.packageName == packageName &&
      other.title == title;

  @override
  int get hashCode => Object.hash(packageName, title);

  @override
  String toString() => 'ConversationRef($packageName, $title)';
}
