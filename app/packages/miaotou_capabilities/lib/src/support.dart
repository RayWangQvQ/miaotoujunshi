/// How a capability implementation answers a call.
///
/// ADR-0009 requires every port to answer for every member of the contract:
/// implement it, or refuse it out loud. A refusal must never be an empty buffer,
/// an empty list or a plausible default — the three shapes a silent fallback
/// takes, and the three shapes nothing downstream can tell apart from a real
/// answer.
library;

/// The platform this implementation targets can never implement [member].
///
/// This is a permanent statement, not an open to-do. `UiTreeReader` on the two
/// desktop ports is the case the rule exists for: accessibility nodes exist on
/// Android and nowhere else. A future reader who finds this should not "fix" it
/// into a silently empty snapshot — see the boundary rules in `GLOSSARY.md`.
Never unsupportedOnThisPlatform({
  required String platform,
  required String member,
  required String reason,
}) {
  throw UnsupportedError('$platform cannot implement $member: $reason');
}

/// This platform can implement [member], but this milestone has not built it.
///
/// Deliberately distinct from [unsupportedOnThisPlatform]: it names the ticket
/// that removes it, so a reader can tell a permanent refusal from work in flight,
/// and so a support report can say which of the two it is looking at.
///
/// The distinction survives the fact that the SDK declares
/// `UnimplementedError extends Error implements UnsupportedError` — a not-yet is
/// an `UnsupportedError` too, so a caller must test the narrower type first. Do
/// not "simplify" the two into one.
Never notYetBuilt({
  required String platform,
  required String member,
  required String ticket,
}) {
  throw UnimplementedError('$platform has not built $member yet; owned by $ticket');
}

/// What one member of the contract did when it was asked.
///
/// The distinction between [unsupported] and [notYetBuilt] is the whole reason
/// this type exists: the first is a statement about a platform, the second is
/// work in flight, and a report that showed them as one thing would hide the
/// difference between "this port will never do it" and "this port has not done it
/// yet".
enum SupportAnswer {
  /// It returned a value.
  answered,

  /// It refused because the platform can never do this.
  unsupported,

  /// It refused because the work has not been built yet.
  notYetBuilt,

  /// It threw something else. That is a defect, not a statement of support.
  failed,
}

/// Asks one member and says how it answered.
///
/// Nothing here swallows a refusal: a member that throws is recorded as having
/// thrown, which is what makes "every member is answered for" observable rather
/// than merely compiled.
///
/// **The catch order is load-bearing.** The SDK declares
/// `class UnimplementedError extends Error implements UnsupportedError`, so a
/// not-yet *is* an `UnsupportedError` and the wider clause must come second.
/// Swapping the two would silently classify every pending member as a permanent
/// refusal — which is why `contract_test.dart` asserts the classifier's answer
/// rather than the thrown type. The SDK's own doc comment describes the same
/// split this contract draws: an operation the object does not intend to support
/// throws `UnsupportedError`, and one it intends to support but has not finished
/// throws `UnimplementedError`.
Future<SupportAnswer> askCapability(Future<Object?> Function() probe) async {
  try {
    await probe();
    return SupportAnswer.answered;
  } on UnimplementedError {
    return SupportAnswer.notYetBuilt;
  } on UnsupportedError {
    return SupportAnswer.unsupported;
  } catch (_) {
    return SupportAnswer.failed;
  }
}
