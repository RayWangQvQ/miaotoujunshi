/// Where injected text goes.
final class InjectTarget {
  const InjectTarget({required this.windowId});

  /// The window handle from [ScreenCapture.findTargetWindow]. Injection is
  /// always aimed at a named window rather than at whatever has the focus: the
  /// user is free to click elsewhere while the advice is on screen, and the
  /// text must not follow them.
  final String windowId;

  @override
  String toString() => 'InjectTarget($windowId)';
}

/// The outcome of one injection.
///
/// The boolean is the point of this type. "I wrote it, so it should be there" is
/// not acceptable: the implementation must read the text back by its own
/// platform means — Android reads the node's text, macOS reads `AXValue`,
/// Windows reads the node's text — before it may report success. Read-back is
/// deliberately not a separate interface member, because the three platforms
/// verify in three different ways and exposing that would leak the difference
/// into the contract (ADR-0009 decision 5).
final class InjectResult {
  const InjectResult.verified(this.observedText)
      : verifiedLanding = true,
        reason = null;

  const InjectResult.unverified(this.reason)
      : verifiedLanding = false,
        observedText = '';

  /// True only when the text was read back out of the target.
  final bool verifiedLanding;

  /// What was read back. Empty when [verifiedLanding] is false.
  final String observedText;

  /// Why the landing could not be verified. Null when it was.
  final String? reason;

  @override
  String toString() => verifiedLanding
      ? 'InjectResult.verified(${observedText.length} chars)'
      : 'InjectResult.unverified($reason)';
}

/// Putting text into another application's input field.
///
/// **Injection only.** There is no member that sends, and none may be added:
/// the absence is the design, and `PRIVACY.md` is where it is promised.
abstract interface class TextInject {
  /// Writes [text] into [target] and reports whether it landed.
  Future<InjectResult> inject(String text, {required InjectTarget target});
}
