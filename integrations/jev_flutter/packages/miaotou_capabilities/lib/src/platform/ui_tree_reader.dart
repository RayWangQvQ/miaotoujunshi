import '../model/chat_snapshot.dart';

/// Reading the foreground chat application's own view of itself.
///
/// **Android only.** The two desktop ports have no accessibility node tree to
/// read: everything they know arrives as pixels. Every member of this interface
/// throws `UnsupportedError` there — a permanent statement, not a gap to be
/// filled, and the case ADR-0009 decision 2 was written for. Do not replace the
/// throw with an empty snapshot.
abstract interface class UiTreeReader {
  /// The conversation currently in front, or null when the foreground
  /// application is not showing a chat window.
  Future<ChatUiSnapshot?> readActiveChat();

  /// Snapshots as the platform produces them.
  ///
  /// Android is event-driven — the accessibility service is woken by a content
  /// change and pushes what it sees — while the desktop ports are asked for a
  /// frame. Exposing the push shape here is what lets the domain consume one
  /// stream on all three ports instead of branching on the platform, which is
  /// the measured property ADR-0009 decision 1 exists to preserve.
  Stream<ChatUiSnapshot> get snapshots;
}
