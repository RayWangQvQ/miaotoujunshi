/// The answer to "how should this round read", once it has been checked against
/// the payload's vocabulary.
///
/// Deliberately a plain value with no vocabulary of its own. Validation happens
/// where the vocabulary is in hand (see `ReplyVocabulary.reply`), so this type
/// cannot be constructed with a tone nobody has heard of and cannot be
/// constructed *without* someone having agreed to the limits. What it does carry
/// is [maxChars] — the ceiling a candidate's text is checked against — resolved
/// once, at construction, so that the prompt and the check can never be told two
/// different numbers.
final class ReplyPreferences {
  const ReplyPreferences({
    required this.tone,
    required this.length,
    required this.count,
    required this.maxChars,
  });

  final String tone;
  final String length;
  final int count;

  /// The character ceiling for one candidate's text, from the payload's length
  /// tier.
  final int maxChars;

  /// The preferences as the scoring request and the prompt both want them.
  Map<String, Object?> describe() => <String, Object?>{
        'tone': tone,
        'length': length,
        'count': count,
        'max_chars': maxChars,
      };

  @override
  String toString() => 'ReplyPreferences($tone, $length, $count, <=$maxChars)';
}
