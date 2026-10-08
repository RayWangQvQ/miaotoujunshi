import 'package:miaotou_capabilities/miaotou_capabilities.dart';
import 'package:miaotou_domain/miaotou_domain.dart';

import '../design/copy.dart';
import 'protocol.dart';

/// Where the engine's vocabulary and the panel's vocabulary meet.
///
/// Two enums and a value type exist on both sides of the window boundary, and
/// neither side may import the other's. The engine is in `miaotou_domain`, which
/// may not know that a panel is a second window with a wire and a JSON encoding
/// (ADR-0020); the panel protocol is in this application, which is the side that
/// does. So the names are spelled twice, and this file is the only place that
/// knows they are the same list.
///
/// **Every mapping here is an exhaustive `switch`, and that is the gate.** A
/// note the engine can decide on and this file has no words for, or a command
/// the panel can send and the engine cannot name, is a build failure rather than
/// a test that runs later — which is the difference that matters, because the
/// failure mode being guarded against is a silent one: a code with no sentence
/// is a panel that shows nothing at all.

/// The sentence for one note.
CopyKey copyKeyOf(NoteCode code) => switch (code) {
  NoteCode.noConversation => CopyKey.runtimeNoConversation,
  NoteCode.recognising => CopyKey.runtimeRecognising,
  NoteCode.captureRefused => CopyKey.runtimeCaptureRefused,
  NoteCode.captureFailed => CopyKey.runtimeCaptureFailed,
  NoteCode.captureServiceOff => CopyKey.runtimeCaptureServiceOff,
  NoteCode.recogniseFailed => CopyKey.runtimeRecogniseFailed,
  NoteCode.nothingRecognised => CopyKey.runtimeNothingRecognised,
  NoteCode.sidesGuessed => CopyKey.panelNoteSidesGuessed,
  NoteCode.sidesNotSplit => CopyKey.panelNoteSidesNotSplit,
  NoteCode.reviewed => CopyKey.panelNoteReviewed,
  NoteCode.analysing => CopyKey.runtimeAnalysing,
  NoteCode.configureModels => CopyKey.runtimeConfigureModels,
  NoteCode.identityIncomplete => CopyKey.runtimeIdentityIncomplete,
  NoteCode.analysisFailed => CopyKey.runtimeAnalysisFailed,
  NoteCode.copied => CopyKey.runtimeCopied,
  NoteCode.filled => CopyKey.runtimeFilled,
  NoteCode.fillUnverified => CopyKey.runtimeFillUnverified,
  NoteCode.conversationChanged => CopyKey.runtimeConversationChanged,
};

/// The codes whose sentence carries the platform's own words.
///
/// One, and it is the one where the words *are* the answer: a refused frame
/// names its cause, and the platform wrote that sentence to be shown. Every
/// other code is a fact this application has its own words for.
const Set<NoteCode> notesWithPlatformWords = <NoteCode>{NoteCode.captureRefused};

/// Where those sentences hold the words.
///
/// A placeholder in the middle of a sentence and not a concatenation, because
/// the order differs per language and `拿不到画面。{reason}` is one sentence with
/// a hole in it rather than two.
const String platformWordsPlaceholder = '{reason}';

/// A note the engine decided on, as the panel takes it.
PanelNote noteOf(ConversationNote note, AppCopy copy) => switch (note) {
  LiteralNote(:final String text, :final NoteRemedy? remedy) => PanelNote(
    text,
    remedy: remedy == null ? null : panelRemedyOf(remedy),
  ),
  CopyNote(:final NoteCode code, :final String? reason, :final NoteRemedy? remedy) =>
    PanelNote(
      _sentence(copy, code, reason),
      remedy: remedy == null ? null : panelRemedyOf(remedy),
    ),
};

String _sentence(AppCopy copy, NoteCode code, String? reason) {
  final String template = copy.text(copyKeyOf(code));
  return reason == null
      ? template
      : template.replaceAll(platformWordsPlaceholder, reason);
}

/// The way out of a note, as the panel's own value.
///
/// A copy rather than a shared type, for the same reason the enums are spelled
/// twice: the panel is handed this and reports what it needs, and it neither
/// knows nor names the thing it is asking for (ADR-0021 decision 8).
PanelRemedy panelRemedyOf(NoteRemedy remedy) => switch (remedy) {
  AskPermission(:final PermissionKind kind) => OpenPermissionPage(kind),
  AskReview() => const EnterReview(),
};

/// The engine's name for one command the panel sent.
ConversationCommandKind commandKindOf(PanelCommandKind kind) => switch (kind) {
  PanelCommandKind.fill => ConversationCommandKind.fill,
  PanelCommandKind.copy => ConversationCommandKind.copy,
  PanelCommandKind.details => ConversationCommandKind.details,
  PanelCommandKind.reanalyse => ConversationCommandKind.reanalyse,
  PanelCommandKind.analyseCurrent => ConversationCommandKind.analyseCurrent,
  PanelCommandKind.recogniseOnce => ConversationCommandKind.recogniseOnce,
  PanelCommandKind.close => ConversationCommandKind.close,
  PanelCommandKind.openPermissionSettings =>
    ConversationCommandKind.openPermissionSettings,
  PanelCommandKind.openReview => ConversationCommandKind.openReview,
  PanelCommandKind.confirmTranscript =>
    ConversationCommandKind.confirmTranscript,
  PanelCommandKind.cancelReview => ConversationCommandKind.cancelReview,
};

/// One command, as the engine takes it.
///
/// The batch is rebuilt rather than reinterpreted, and that is deliberate:
/// [PanelLine] and [ChatLine] are the same two fields because the panel has
/// nowhere to point at, so a line the user edited in the panel crosses the
/// boundary as words and a speaker and nothing is carried over that the panel
/// could not have changed.
CommandReceived commandOf(PanelCommand command) => CommandReceived(
  commandKindOf(command.kind),
  text: command.text,
  permission: command.permission,
  lines: command.lines == null
      ? null
      : <ChatLine>[
          for (final PanelLine line in command.lines!)
            ChatLine(speaker: line.speaker, text: line.text),
        ],
  title: command.title,
  appName: command.appName,
);
