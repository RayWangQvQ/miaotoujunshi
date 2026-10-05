import 'package:miaotou_capabilities/miaotou_capabilities.dart';

import 'advice.dart';

/// Which conversation is on the panel, which one the user is looking at, and
/// what the panel may therefore offer — one derivation for all three ports.
///
/// ADR-0002 is the whole of the specification, and it was written against
/// Android, which was the only port that had the problem. The other two grew
/// their own answers with their own names: Windows keeps a `_shown` (what is on
/// screen) beside a `_chat` (what WeChat has open) and disables fill, copy and
/// reason together; macOS gates fill on having read a title. Neither is wrong
/// and neither is the same, so this module is the convergence.
///
/// Two decisions about where things live:
///
/// * **The label carries no package name.** [ConversationLabel] has an
///   `appName` and a `title` and nothing else, so the one thing ADR-0002
///   forbids — printing `com.tencent.mm` where a person can read it — is not
///   representable rather than merely discouraged. The package is resolved to a
///   name *before* it reaches here, by whoever owns the platform.
/// * **The derivation is a pure function of two refs and an advice.** ADR-0002
///   decision 2 puts the verdict on the side that knows which conversation the
///   user is looking at, and forbids the renderer from going and looking for
///   itself. Here that means [derivePanel] is called with both refs and the view
///   only renders what it is handed.
///
/// Nothing here is persisted. Read-only is derived every time, never stored:
/// ADR-0002 rejects a remembered "ignore" toggle on the grounds that it
/// eventually brings the mis-fill back.

/// How much of a conversation can be named to the user.
///
/// Four cases and not a nullable string, because the fallbacks are the rule:
/// Android's `ConversationRef.displayLabel()` goes `app · title` → `title` →
/// `app · 未识别会话` → `未识别会话`, and the last one is the one that must
/// never become a package name. The port keeps that order; only the words live
/// in the application's copy file.
enum ConversationLabelKind {
  /// Both halves are known: `微信 · 张三`.
  appAndTitle,

  /// The thread is known but this build has no name for the app behind it.
  titleOnly,

  /// The app is known but the thread title could not be read.
  appOnly,

  /// Neither half is known.
  unrecognised,
}

/// A conversation's identity as it may be shown.
///
/// **There is deliberately no `packageName` here.** The packages are how the
/// three platforms identify a chat application, and they are the one thing a
/// header must never echo: ADR-0002 says so, Android's `ChatApps.displayName`
/// returns null rather than inventing one, and the port's own comment says the
/// knowledge-base list may show a raw package precisely because it is answering
/// a different question. Dropping the field at this boundary is what makes the
/// rule true instead of aspirational.
final class ConversationLabel {
  const ConversationLabel._({
    required this.kind,
    this.appName,
    this.title,
  });

  /// Resolves a reference into something a header may print.
  ///
  /// `appName` is the chat application's display name, already resolved by the
  /// platform, or null when this build has no name for that package — which is
  /// a real answer and not a failure, and which is why the fallback order
  /// exists. A blank title is treated as absent, because a transient
  /// placeholder title is not a name anyone can confirm a fill against.
  factory ConversationLabel.of(
    ConversationRef reference, {
    String? appName,
  }) {
    final String? app = (appName == null || appName.trim().isEmpty) ? null : appName;
    final String? thread = reference.title?.trim();
    final String? name = (thread == null || thread.isEmpty) ? null : thread;

    if (app != null && name != null) {
      return ConversationLabel._(kind: ConversationLabelKind.appAndTitle, appName: app, title: name);
    }
    if (name != null) {
      return ConversationLabel._(kind: ConversationLabelKind.titleOnly, title: name);
    }
    if (app != null) {
      return ConversationLabel._(kind: ConversationLabelKind.appOnly, appName: app);
    }
    return const ConversationLabel._(kind: ConversationLabelKind.unrecognised);
  }

  /// Nothing has been analysed yet, so there is nothing to name.
  static const ConversationLabel none =
      ConversationLabel._(kind: ConversationLabelKind.unrecognised);

  final ConversationLabelKind kind;

  /// The chat application's display name, or null when it is unknown.
  final String? appName;

  /// The thread title, or null when it could not be read.
  final String? title;

  /// True when the thread itself is named — enough to confirm a fill target.
  bool get isIdentified => title != null;
}

/// What the panel is showing, in the header's own words.
enum PanelStatus {
  /// Nothing has been analysed, or the panel has not been bound to a
  /// conversation. Android's word for it: 尚未分析.
  notAnalysed,

  /// The analysed conversation is the one in front of the user. 正在看.
  viewing,

  /// The user has moved on; the panel is showing an old conversation. 浏览中 ·
  /// 只读.
  browsingReadOnly,
}

/// One thing the panel may be asked to do.
///
/// An enum rather than four booleans because ADR-0002 decision 3 is a statement
/// about *which* of these survive read-only, and a set is what makes that
/// testable: read-only withdraws [fill] and nothing else.
enum PanelAction {
  /// Put a candidate into the chat application's input box.
  fill,

  /// Put a candidate on the clipboard.
  copy,

  /// Open the full analysis.
  details,

  /// Analyse the conversation on the panel again.
  reanalyse,

  /// Drop what is on the panel and read whatever the user is looking at now.
  ///
  /// ADR-0002 decision 3 calls this out by name: while read-only, the old
  /// 「重新分析」 reused the snapshot on the panel, which by definition belongs
  /// to another conversation, so tapping it silently did nothing.
  analyseCurrent,
}

/// Everything the panel shows, derived from three facts.
final class PanelView {
  const PanelView({
    required this.analysed,
    required this.live,
    required this.status,
    required this.readOnly,
    required this.actions,
    this.advice,
    this.note,
  });

  /// Whose analysis is on the panel.
  final ConversationLabel analysed;

  /// What the user is looking at right now.
  final ConversationLabel live;

  /// The verdict and the drafts, or null when there has been no analysis.
  final Advice? advice;

  /// A caveat about how the analysed snapshot was produced, shown verbatim.
  ///
  /// An OCR capture cannot tell who said what, and that belongs on the panel
  /// rather than buried in a log.
  final String? note;

  final PanelStatus status;

  /// True when [analysed] and [live] name different conversations.
  ///
  /// Derived, never stored — see the module comment.
  final bool readOnly;

  /// What the panel may offer. Read-only removes [PanelAction.fill] and only
  /// that: ADR-0002 decision 3.
  final Set<PanelAction> actions;

  bool allows(PanelAction action) => actions.contains(action);
}

/// Derives everything the panel shows.
///
/// `appName` resolves a package to a display name, and is supplied by the side
/// that owns the platform: the panel has no business asking. Returning null is
/// a legitimate answer and is what drives the [ConversationLabelKind.appOnly]
/// and [ConversationLabelKind.unrecognised] fallbacks.
PanelView derivePanel({
  required ConversationRef? analysed,
  required ConversationRef? live,
  required Advice? advice,
  required String? Function(ConversationRef reference) appName,
  String? note,
}) {
  final bool hasAnalysis = analysed != null && !analysed.isNone;
  final ConversationLabel analysedLabel = hasAnalysis
      ? ConversationLabel.of(analysed, appName: appName(analysed))
      : ConversationLabel.none;
  final ConversationLabel liveLabel = (live == null || live.isNone)
      ? ConversationLabel.none
      : ConversationLabel.of(live, appName: appName(live));

  // ADR-0002 decision 2, verbatim: readOnly = shown != null && shown != live.
  final bool readOnly = hasAnalysis && analysed != live;

  final PanelStatus status = !hasAnalysis
      ? PanelStatus.notAnalysed
      : readOnly
          ? PanelStatus.browsingReadOnly
          : PanelStatus.viewing;

  final Set<PanelAction> actions = <PanelAction>{
    // The one thing read-only never takes away: ADR-0002 decision 3.
    if (advice != null) ...<PanelAction>{PanelAction.copy, PanelAction.details},
    // A fill writes into a specific thread. Two things have to be true: the
    // user is still looking at the conversation that was analysed (macOS gates
    // on having read a title; Android's fillInput re-reads the tree and
    // compares title and signature), and we know which thread that was.
    if (advice != null &&
        advice.candidates.isNotEmpty &&
        !readOnly &&
        analysedLabel.isIdentified)
      PanelAction.fill,
    if (readOnly) PanelAction.analyseCurrent else PanelAction.reanalyse,
  };

  return PanelView(
    analysed: analysedLabel,
    live: liveLabel,
    advice: advice,
    note: note,
    status: status,
    readOnly: readOnly,
    actions: actions,
  );
}

/// The identity half lives in `snapshot.dart`, beside [CapturedLine]:
/// [conversationSignature] and [Snapshot.signature].
