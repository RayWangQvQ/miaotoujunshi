/// Which conversation something belongs to: the chat application's package plus
/// the thread title.
///
/// Either field may be absent, and absence is a legitimate state rather than an
/// error (ADR-0002): an OCR capture has no title to read, an application can be
/// showing a transient placeholder title, and there may be no chat window in
/// front of the user at all. Never infer one field from the other, and never
/// fall back to printing the bare package name — the interface carries no
/// display logic for exactly that reason; [isIdentified] is the whole of what a
/// caller may conclude.
final class ConversationRef {
  const ConversationRef({required this.packageName, this.title});

  /// No chat window is in front of the user.
  static const ConversationRef none = ConversationRef(packageName: '');

  /// The chat application's package name (`com.tencent.mm`) or bundle
  /// identifier. Empty when the application itself is unknown.
  final String packageName;

  /// The thread title as the chat application shows it. Null or blank when it
  /// could not be read.
  final String? title;

  /// True only when both halves are present. This is what a fill may be guarded
  /// on; it is not a licence to guess either half.
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
