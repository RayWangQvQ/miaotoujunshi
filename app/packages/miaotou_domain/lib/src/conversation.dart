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
/// * **The label carries a resolved name, never a package.** [ConversationLabel]
///   has an `appName` and a `title` and nothing else. The `appName` is resolved
///   by whoever owns the platform and arrives on the reference itself
///   ([ConversationRef.appName], ADR-0028) — and, since ADR-0026, an app the
///   system cannot name falls back to its package name *as the name*, so the
///   label is never empty while a window is in front.
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
/// the label goes `app · title` → `title` → `app · 未知人` → `未知应用`, and
/// the app half itself resolves display name → package name (ADR-0026). The
/// words live in the application's copy file, but the split between the two
/// placeholders is semantic: 未知人 is "the app is named, the person is not",
/// and 未知应用 is "no window in front" ([NONE]) — the only case left after the
/// package-name fallback. Keeping that order is this type's whole job.
enum ConversationLabelKind {
  /// Both halves are known: `微信 · 张三`.
  appAndTitle,

  /// The thread is known but this build has no name for the app behind it.
  titleOnly,

  /// The app is known but the thread title could not be read — the person half
  /// is what is missing, and the renderer says so (未知人, not 未知应用).
  /// [appName] here is whatever names the app: the resolved display name, or
  /// the bare package name when no display name was resolved (ADR-0026).
  appOnly,

  /// Nothing at all is known — no chat window in front of the user ([NONE]).
  /// This is the only case left after the package-name fallback.
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
  /// `reference.appName` is the chat application's display name, already
  /// resolved by the platform (ADR-0028), or null when that port has no name for
  /// the package — which is a real answer and not a failure, and which is why
  /// the fallback order exists. A blank title is treated as absent, because a
  /// transient placeholder title is not a name anyone can confirm a fill
  /// against.
  factory ConversationLabel.of(ConversationRef reference) {
    final String? thread = reference.title?.trim();
    final String? name = (thread == null || thread.isEmpty) ? null : thread;

    // The app half is whatever names the package to the user: the resolved
    // display name when the platform has one, the bare package name when it
    // does not (ADR-0026), or null when even the package is unknown (NONE).
    final String? resolved = reference.appName?.trim();
    final String package = reference.packageName.trim();
    final String? app = (resolved == null || resolved.isEmpty)
        ? (package.isEmpty ? null : package)
        : resolved;

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
    required this.header,
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

  /// The one label the header prints: [analysed] once there is one, and [live]
  /// before that.
  ///
  /// **The fallback is the point** (ADR-0028). A panel with nothing analysed yet
  /// that says 未知应用 while the user is standing in an application the build
  /// has no adapter for — Douyin — names nothing at all, which is the exact
  /// complaint ADR-0026 was written to answer and which the header's old
  /// `analysed`-only reading silently preserved: without an adapter there is no
  /// tree reading, so no analysis, so never a name. The header therefore names
  /// the conversation the panel is *about* when there is one, and the one in
  /// front of the user when there is not — and, once it does, the app half is
  /// named even while the person half is not (抖音 · 未知人, not 未知应用).
  ///
  /// It is not [live] as a general rule: while read-only the two disagree, and
  /// the header has to keep saying which conversation the drafts below it
  /// belong to. That is what the read-only badge and banner then qualify.
  final ConversationLabel header;

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
/// Three facts in and nothing asked of anybody: the display name is already on
/// the reference ([ConversationRef.appName], ADR-0028), so this is a pure
/// function of what the caller holds and the panel never goes looking.
PanelView derivePanel({
  required ConversationRef? analysed,
  required ConversationRef? live,
  required Advice? advice,
  String? note,
}) {
  final bool hasAnalysis = analysed != null && !analysed.isNone;
  final ConversationLabel analysedLabel = hasAnalysis
      ? ConversationLabel.of(analysed)
      : ConversationLabel.none;
  final ConversationLabel liveLabel = (live == null || live.isNone)
      ? ConversationLabel.none
      : ConversationLabel.of(live);

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
    header: hasAnalysis ? analysedLabel : liveLabel,
    advice: advice,
    note: note,
    status: status,
    readOnly: readOnly,
    actions: actions,
  );
}

/// The identity half lives in `snapshot.dart`, beside [CapturedLine]:
/// [conversationSignature] and [Snapshot.signature].
