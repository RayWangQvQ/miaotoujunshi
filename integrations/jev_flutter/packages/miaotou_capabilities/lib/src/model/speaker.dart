/// Who wrote one chat line.
///
/// Three values, not two. `me` and `other` are the pair the shared payload's
/// `trend-rules.json` declares and the pair this repository settled on inside
/// every port (ADR-0015). `unknown` is not a missing value: macOS's perception
/// layer emits it for a bubble that is not clearly anchored to either side, and
/// the panel renders that line as 说话人待确认. A two-valued enum cannot express
/// it, and folding it into one of the other two would silently invent an author.
///
/// The token a model sees is *not* this enum's name. The wire vocabulary stays
/// at each port's boundary — `them` on the two desktop ports, 我/对方 on Android
/// — and each of the three conversion sites translates on the way out
/// (ADR-0015). Nothing above the boundary should spell those tokens.
enum Speaker {
  /// The user.
  me,

  /// The other party.
  other,

  /// The line could not be attributed to either side.
  unknown,
}
