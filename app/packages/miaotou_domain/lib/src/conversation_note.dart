import 'package:miaotou_capabilities/miaotou_capabilities.dart';

/// What the panel has to say, in the vocabulary of the side that decides it.
///
/// **Every note is either a code or someone else's sentence, and never a string
/// written here.** This package holds no sentence a screen shows — that is what
/// ADR-0009's boundary means for copy, and what the application's own audit
/// enforces — so a note the engine decides on travels as a [NoteCode] and the
/// application is the side that turns it into words. A note that came from
/// somewhere else travels as a [LiteralNote] instead, because there is nothing
/// to look up: the platform's refusal and the domain's own `DomainException`
/// were written to be shown unchanged, and re-writing them here would put a
/// second author in front of the one thing the user needs to read.
///
/// The engine used to hold these as finished `String`s and the application
/// built them at the call site, which is how a `runtimeNoConversation` came to
/// mean "no conversation" in one place and "the platform declined to answer" in
/// another. A code is one name for one fact, and the mapping table in the
/// application is where a missing name becomes a compile error rather than a
/// blank panel.
sealed class ConversationNote {
  const ConversationNote({this.remedy});

  /// Something the user can do about this, or null when the note is only
  /// something to read.
  ///
  /// A value rather than a flag, for the same reason [NoteCode] is an enum: the
  /// panel must not know which system page a refusal is about (ADR-0021
  /// decision 8), and this package is the side that does know.
  final NoteRemedy? remedy;
}

/// A note whose words are the application's copy.
final class CopyNote extends ConversationNote {
  const CopyNote(this.code, {this.reason, super.remedy});

  final NoteCode code;

  /// The platform's own words, for the one code that shows them.
  ///
  /// Null for every other code, and not optional where it is not: a refusal
  /// that names its cause is the difference between a user who can act and a
  /// user who cannot, so the sentence is carried rather than summarised.
  final String? reason;

  @override
  bool operator ==(Object other) =>
      other is CopyNote &&
      other.code == code &&
      other.reason == reason &&
      other.remedy == remedy;

  @override
  int get hashCode => Object.hash(CopyNote, code, reason, remedy);

  @override
  String toString() =>
      'CopyNote(${code.name}${reason == null ? '' : ', $reason'})';
}

/// A note whose words were written by somebody else.
///
/// Two sources reach this, and both are read verbatim. A platform refusal is
/// written to be shown unchanged — it names a cause and, where there is one, a
/// remedy, and a sentence of our own would be the only thing standing between
/// the user and the reason. A `DomainException` is this package's own refusal,
/// raised by the gate or the transport, and it already says which of its two
/// reasons it is.
final class LiteralNote extends ConversationNote {
  const LiteralNote(this.text, {super.remedy});

  final String text;

  @override
  bool operator ==(Object other) =>
      other is LiteralNote && other.text == text && other.remedy == remedy;

  @override
  int get hashCode => Object.hash(LiteralNote, text, remedy);

  @override
  String toString() => 'LiteralNote($text)';
}

/// The one sentence, per fact, that the panel can be showing.
///
/// Named after the fact and not after the position it appears in: a code is
/// published from several places — [NoteCode.noConversation] from a failed
/// start, from a pushed stream that errored and from a command with nothing to
/// act on — and they are the same note because they are the same fact.
enum NoteCode {
  /// There is no conversation to work with.
  noConversation,

  /// A whole-frame capture is being taken and read.
  recognising,

  /// The platform refused this frame and said why.
  captureRefused,

  /// The capture could not be taken, for a reason the platform did not name.
  captureFailed,

  /// The platform cannot capture at all because its accessibility service is
  /// off. The only note that carries a remedy of its own.
  captureServiceOff,

  /// A frame was taken and could not be read.
  recogniseFailed,

  /// A frame was read and held nothing.
  nothingRecognised,

  /// A capture was read and the geometry found both sides, which is a guess.
  sidesGuessed,

  /// A capture was read and the geometry found one side, so nobody was
  /// attributed. Definitely a caveat, never a failure.
  sidesNotSplit,

  /// The user read the batch and confirmed it.
  reviewed,

  /// A round is running.
  analysing,

  /// A round cannot run until the model is configured. ADR-0026's neighbour:
  /// the application is usable and the one thing missing is a route.
  configureModels,

  /// A round cannot run until the application and the person are both named.
  /// The way out is the review, where the missing half is entered by hand
  /// (ADR-0030).
  identityIncomplete,

  /// A round threw something that is not the domain's own refusal.
  analysisFailed,

  /// A draft is on the clipboard.
  copied,

  /// A draft landed in the conversation and was verified.
  filled,

  /// A draft was put where the user can paste it, because the landing could not
  /// be verified.
  fillUnverified,

  /// The conversation moved on since the draft was written.
  conversationChanged,
}

/// Something the user can do about a note.
///
/// The counterpart of the application's own remedy value: this package decides
/// *that* a refusal has a way out and *which* one, and the application is the
/// side that knows how to draw a button for it. Two variants and not a
/// [PermissionKind] alone, because the two ways out are different in kind — one
/// leaves the application for a system page, the other comes back into the
/// panel's own review state.
sealed class NoteRemedy {
  const NoteRemedy();
}

/// The system page for one permission is the way out.
final class AskPermission extends NoteRemedy {
  const AskPermission(this.kind);

  final PermissionKind kind;

  @override
  bool operator ==(Object other) =>
      other is AskPermission && other.kind == kind;

  @override
  int get hashCode => Object.hash(AskPermission, kind);

  @override
  String toString() => 'AskPermission(${kind.name})';
}

/// Reviewing the batch on the panel is the way out.
///
/// The refusal this answers is 「all of this is unconfirmed, confirm it first」,
/// and the batch it is about is the one the panel is showing (ADR-0022).
final class AskReview extends NoteRemedy {
  const AskReview();

  @override
  bool operator ==(Object other) => other is AskReview;

  @override
  int get hashCode => Object.hash(AskReview, 0);

  @override
  String toString() => 'AskReview()';
}
