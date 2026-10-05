/// A refusal the deciding half produces, carrying the message a person is shown.
///
/// The three ports each raise their language's generic error — Python
/// `ValueError`, Kotlin `IllegalArgumentException` — and the existing suite
/// asserts on the *message*, not the type, because the message is what reaches
/// the user. A single type here keeps that property while giving the tests
/// something narrower to catch than `Exception`.
///
/// It is deliberately not an `Error`: every one of these is an expected outcome
/// of bad input or a model that did not keep its contract, not a defect in the
/// program.
final class DomainException implements Exception {
  const DomainException(this.message);

  /// The line shown to the user. Written in the product's language, not the
  /// code's, because it travels to a person unchanged (see the project's
  /// Chinese-UI exception).
  final String message;

  @override
  String toString() => message;
}
