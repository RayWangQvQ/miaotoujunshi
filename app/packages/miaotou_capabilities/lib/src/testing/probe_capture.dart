/// Running one member and keeping what it threw.
///
/// `askCapability` classifies an outcome; this keeps the error itself, so a test
/// can assert not only that a member refused but which kind of refusal it was and
/// whether the message says who owns the work.
library;

/// Returned by [runProbe] when the member answered instead of throwing.
///
/// A sentinel rather than null, because null is a legitimate answer — "no window
/// found" is what `findTargetWindow` says most of the time — and a test that
/// could not tell the two apart would pass on a member that silently returned
/// nothing.
final Object probeReturned = Object();

/// Runs one probe and returns what it threw, or [probeReturned].
Future<Object> runProbe(Future<Object?> Function() probe) async {
  try {
    await probe();
    return probeReturned;
  } catch (error) {
    return error;
  }
}
