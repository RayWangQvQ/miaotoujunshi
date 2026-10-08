import 'dart:async';

import 'package:flutter/material.dart';
import 'package:miaotou_capabilities/miaotou_capabilities.dart'
    show ConversationRef, PermissionKind, Speaker;
import 'package:miaotou_domain/miaotou_domain.dart';

import '../design/colors.dart';
import '../design/copy.dart';
import '../design/spacing.dart';
import '../widgets/candidate_card.dart';
import '../widgets/empty_state.dart';
import '../widgets/status_badge.dart';
import 'protocol.dart';
import 'review_block.dart';
import 'review_session.dart';

/// The conversation label as the header prints it, built out of copy.
///
/// A conversation is the app plus the person (ADR-0028): 「抖音 · 张三」. The
/// four branches are one decision each because the fallbacks are the rule — an
/// app we know but a person whose title could not be read is 「抖音 · 未知人」
/// (never 未知应用, which now means "no window in front" and nothing else). The
/// domain decides *which* branch ([ConversationLabelKind]); only the words live
/// in [AppCopy].
String panelLabelText(AppCopy copy, ConversationLabel label) {
  final String unknownPerson = copy.text(CopyKey.panelLabelUnknownPerson);
  final String unrecognised = copy.text(CopyKey.panelLabelUnrecognised);
  return switch (label.kind) {
    ConversationLabelKind.appAndTitle => _fill(
      copy.text(CopyKey.panelLabelPair),
      app: label.appName!,
      title: label.title!,
    ),
    ConversationLabelKind.titleOnly => _fill(
      copy.text(CopyKey.panelLabelTitleOnly),
      title: label.title!,
    ),
    ConversationLabelKind.appOnly => _fill(
      copy.text(CopyKey.panelLabelPair),
      app: label.appName!,
      title: unknownPerson,
    ),
    ConversationLabelKind.unrecognised => unrecognised,
  };
}

String _fill(String template, {String app = '', String title = ''}) =>
    template.replaceAll('{app}', app).replaceAll('{title}', title);

/// The floating panel.
///
/// ADR-0002 is what this renders: the verdict and the drafts belong to one
/// conversation, the user may be looking at another, and the difference has to
/// be visible and to cost the panel its 「填入」 and nothing else.
///
/// ## What lives here and what does not
///
/// **Only transient state lives here.** [_PanelPageState] holds whether the
/// panel is expanded, where the user last dropped it, and the block the user is
/// editing in the review — three facts about this window's surface, all lost
/// when it goes away. The advice, the conversation, the verdict and the batch
/// are all in [PanelPage.frame] and are somebody else's to change; this widget
/// renders what it is handed and asks for what it wants through
/// [PanelPage.onCommand]. That is #12, AC1, and `test/panel_test.dart` scans
/// this file and [ReviewSession] for a field that would break it.
///
/// **The review's rules are not here.** What the block starts as, what 我 / 对方
/// / 删行 do to the caret's line, and whether a frame carries a batch the field
/// does not are all [ReviewSession]'s — including the one question this widget
/// cannot answer on its own, because it is about the batch and not about the
/// surface: *a republish that repeats it must not wipe an edit in progress.*
///
/// **No capability is called from here.** The panel cannot ask which
/// application is in front, because asking would put a second source of truth
/// beside the main window's — which is the drift ADR-0002 decision 2 exists to
/// prevent. It derives read-only from the two refs in the frame, exactly as that
/// decision says the view should, and the app's display name is already on each
/// ref (ADR-0028), so nothing here resolves a package either.
///
/// ADR-0012 gives the panel a window of its own; until #18 and #21 create it,
/// the gallery hosts this so it is not dead code.
class PanelPage extends StatefulWidget {
  const PanelPage({
    super.key,
    required this.frame,
    required this.onCommand,
    this.onExpandedChanged,
    this.onDragStart,
    this.onInputFocusChanged,
    this.initialExpanded = true,
  });

  /// Everything the panel may show. The only thing going down.
  final PanelFrame frame;

  /// The only thing going up.
  final void Function(PanelCommand command) onCommand;
  final ValueChanged<bool>? onExpandedChanged;
  final VoidCallback? onDragStart;
  final Future<void> Function(bool focusable)? onInputFocusChanged;
  final bool initialExpanded;

  @override
  State<PanelPage> createState() => _PanelPageState();
}

class _PanelPageState extends State<PanelPage> {
  /// Transient: whether the body is showing.
  late bool _expanded;

  /// Transient: where the user dragged the panel to.
  Offset _landing = Offset.zero;

  /// Transient: the block as the user is typing it, and nothing else.
  ///
  /// The review is a surface over a batch the main engine owns, so what lives
  /// here is only the edit in progress. Confirming sends it up; leaving the
  /// state throws it away. The whole batch is one editable block (ADR-0025), so
  /// the edit is a single controller — and which line the caret is on is read
  /// off that controller when a shortcut is pressed, not mirrored into a field
  /// here.
  final TextEditingController _reviewController = TextEditingController();
  final FocusNode _reviewFocus = FocusNode();

  /// The person's name and the application's name, as the review collects them
  /// (ADR-0030). Seeded from the conversation once, then the user's to edit.
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _appNameController = TextEditingController();
  bool _identitySeeded = false;

  /// What the confirm button said the last time a required half was missing.
  String? _identityError;

  /// The review's rules, built on the first frame that can read the copy.
  ///
  /// **Lazy rather than created in `initState`**, because the block is made of
  /// copy and [CopyScope] is an inherited widget — the same reason the first
  /// block could not be built there either. **Built once**, because a later
  /// `didChangeDependencies` is a dependency change and not a new review: a
  /// second module would have no memory of the batch it built, and would put the
  /// raw batch back in the field under the user's hands.
  late final ReviewSession _review = ReviewSession(CopyScope.of(context));

  @override
  void initState() {
    super.initState();
    _expanded = widget.initialExpanded;
    // The speaker buttons gate on the block having a caret, and focus does not
    // rebuild on its own, so a change to it has to ask for one.
    _reviewFocus.addListener(() => setState(() {}));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The first frame that can build the block, because the copy it is made of
    // lives in an inherited widget and `initState` cannot read one.
    _syncReview();
  }

  @override
  void didUpdateWidget(PanelPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Every frame goes through the review, in both states — see [_syncReview].
    _syncReview();
  }

  /// Hands the frame to the review and writes back the block it asks for.
  ///
  /// Called in **both** states, including the frames where the review is not up,
  /// because that is where the review's memory of the batch it built is cleared
  /// — and clearing it is what makes coming back to the review a fresh block
  /// rather than last time's edit resurrected under the caret. Which of the two
  /// questions a frame raises is the module's to answer, not this widget's:
  /// *the batch on the panel is the batch in the field* means leave the edit
  /// alone, and anything else means start again.
  void _syncReview() {
    final String? block = _review.blockFor(
      reviewing: widget.frame.reviewing,
      batch: widget.frame.transcript,
    );
    if (block != null) {
      _reviewController.text = block;
    }
    _seedIdentity();
  }

  /// Fills the identity fields from the conversation the review is about, once.
  ///
  /// Seeded on the first frame that enters the review and never again: a later
  /// frame republishes the same batch, and overwriting the fields then would
  /// wipe what the user just typed under their hands. What the platform already
  /// read (the title, the application's name) is pre-filled; what it could not
  /// is left empty for the user to supply (ADR-0030).
  void _seedIdentity() {
    if (_identitySeeded) {
      return;
    }
    final ConversationRef ref = widget.frame.analysed;
    final String? title = ref.title?.trim();
    if (title != null && title.isNotEmpty) {
      _titleController.text = title;
    }
    // The app half is whatever names it: the resolved display name or, failing
    // that, the bare package name (ADR-0026). Pre-filled once, and read-only
    // when the platform named it at all — see [_appIsNamed].
    final String? appName = _resolvedAppName(ref);
    if (appName != null) {
      _appNameController.text = appName;
    }
    _identitySeeded = true;
  }

  /// What names the app half of the review: the platform's display name, or the
  /// bare package name when the system could not name it (ADR-0026). Null only
  /// when even the package is unknown — the one case the field is left for the
  /// user to fill (ADR-0030).
  String? _resolvedAppName(ConversationRef ref) {
    final String? displayName = ref.appName?.trim();
    if (displayName != null && displayName.isNotEmpty) {
      return displayName;
    }
    final String package = ref.packageName.trim();
    return package.isEmpty ? null : package;
  }

  /// True when the platform already named the application — a display name or a
  /// bare package — so the field must not be editable (ADR-0030 decision 2: the
  /// user fills it only when the platform could not name the app at all).
  bool get _appIsNamed => _resolvedAppName(widget.frame.analysed) != null;

  @override
  void dispose() {
    _reviewController.dispose();
    _reviewFocus.dispose();
    _titleController.dispose();
    _appNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppCopy copy = CopyScope.of(context);
    final AppColors colors = AppColors.of(context);
    // The panel is a 300dp overlay, not a page, so its type is clamped a step
    // down: no text on it may read larger than a body line. The clamp is applied
    // *here*, on the panel's own theme, so the shared candidate card and labeled
    // block — which read the theme off the context rather than a parameter — are
    // the only copies that shrink, and the main window's pages keep their scale.
    final ThemeData theme = _panelTheme(Theme.of(context));
    final PanelView view = derivePanel(
      analysed: widget.frame.analysed,
      live: widget.frame.live,
      advice: widget.frame.advice,
      note: widget.frame.note?.text,
    );
    final Advice? advice = view.advice;

    if (!_expanded) {
      return SizedBox.square(
        dimension: 56,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: widget.onDragStart == null
              ? null
              : (DragStartDetails details) => widget.onDragStart!(),
          child: Card(
            margin: EdgeInsets.zero,
            shape: const CircleBorder(),
            color: colors.accentMuted,
            child: IconButton(
              key: const Key('panel-ball'),
              onPressed: _toggleExpanded,
              icon: const Icon(Icons.auto_awesome),
            ),
          ),
        ),
      );
    }

    final List<Widget> fixed = <Widget>[
      _header(context, copy, theme, view),
      if (view.readOnly) _banner(copy, colors, theme),
      if (widget.frame.note != null) _note(copy, colors, theme),
      // The review's title row — the two speaker buttons and 删行 — stays
      // pinned while the block below scrolls. It acts on the caret of the
      // block, so scrolling to a line must not scroll the very buttons that
      // rewrite it out of reach.
      if (widget.frame.reviewing) _reviewHeader(copy, theme),
    ];
    final Widget body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        // The review takes the body whatever else is in the frame. It is a
        // state, not a section: the user is being asked a question, and a
        // candidate card behind it would be the panel talking over itself.
        //
        // **An analysis with no candidates still shows the batch.** 「本轮建议
        // 不回复」 is a verdict the domain reaches on purpose
        // (`RankingStatus.notNeeded`), not a failure to produce one, and the
        // panel has to be able to say it: the batch the user just confirmed is
        // the only thing on the panel that is theirs, and hiding it behind an
        // advice that carries no drafts leaves a note and nothing else — which
        // is what 「重新分析」 looked like when it appeared to do nothing
        // (ADR-0024).
        if (widget.frame.reviewing)
          _reviewForm(copy, theme)
        else if ((advice == null || advice.candidates.isEmpty) &&
            widget.frame.transcript.isNotEmpty)
          _transcript(copy, colors, theme)
        else if (advice == null)
          Padding(
            padding: AppSpacing.page,
            child: EmptyState(message: copy.text(CopyKey.panelEmpty)),
          )
        else
          for (int i = 0; i < advice.candidates.length; i++)
            Padding(
              padding: AppSpacing.panel,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  CandidateCard(
                    candidate: advice.candidates[i],
                    rank: i + 1,
                    rankingStatus: advice.rankingStatus,
                    dense: true,
                    onCopy: view.allows(PanelAction.copy)
                        ? () => widget.onCommand(
                            PanelCommand(
                              PanelCommandKind.copy,
                              candidateIndex: i,
                              text: advice.candidates[i].text,
                            ),
                          )
                        : null,
                  ),
                  if (view.allows(PanelAction.fill))
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.s),
                      child: FilledButton.tonal(
                        onPressed: () => widget.onCommand(
                          PanelCommand(
                            PanelCommandKind.fill,
                            candidateIndex: i,
                            text: advice.candidates[i].text,
                          ),
                        ),
                        child: Text(copy.text(CopyKey.panelActionFill)),
                      ),
                    ),
                ],
              ),
            ),
        _bottomRow(copy, view),
      ],
    );

    return Theme(
      // The clamped type has to reach the shared widgets — the candidate card
      // and the labeled block read `Theme.of(context)`, not a parameter — so the
      // panel's own theme is pushed down the tree, not just handed to its own
      // helpers.
      data: theme,
      child: Transform.translate(
        // Keyed so a test can read the offset the user dragged to.
        key: const Key('panel-landing'),
        offset: _landing,
        child: Card(
          margin: EdgeInsets.zero,
          // One tap region over the whole panel — fixed header row included —
          // so a tap on the pinned review buttons (我 / 对方 / 删行) is *not*
          // a tap outside the review block's field. The buttons read the
          // caret, and a tap that first dismissed it would leave them nothing
          // to act on.
          child: TextFieldTapRegion(
            child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) =>
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      ...fixed,
                      if (_expanded)
                        if (constraints.hasBoundedHeight)
                          Expanded(
                            child: SingleChildScrollView(
                              key: const Key('panel-scroll'),
                              child: body,
                            ),
                          )
                        else
                          body,
                    ],
                  ),
            ),
          ),
        ),
      ),
    );
  }

  /// A copy of [base] with the body type clamped down a step.
  ///
  /// A 300dp overlay is not a page, and no text on it should read larger than a
  /// body line: `bodyLarge` is the one role that breaks that cap by default, and
  /// the candidate card's draft reads it. `bodyMedium` follows it down so the
  /// reason and tradeoff under a draft stay a step below the draft rather than
  /// the same size. `bodySmall` is already the floor and is left alone — the
  /// review block, the note and the header's conversation line all read it and
  /// have nowhere lower to go.
  ThemeData _panelTheme(ThemeData base) {
    final TextTheme text = base.textTheme;
    return base.copyWith(
      textTheme: text.copyWith(
        bodyLarge: text.bodyMedium,
        bodyMedium: text.bodySmall,
      ),
    );
  }

  /// The title, the conversation and the status word.
  ///
  /// The header is also the drag handle: ADR-0012's panel is frameless, so
  /// there is no title bar for the platform to give back.
  Widget _header(
    BuildContext context,
    AppCopy copy,
    ThemeData theme,
    PanelView view,
  ) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onPanStart: widget.onDragStart == null
        ? null
        : (DragStartDetails details) => widget.onDragStart!(),
    onPanUpdate: widget.onDragStart != null
        ? null
        : (DragUpdateDetails details) =>
              setState(() => _landing += details.delta),
    child: Padding(
      padding: AppSpacing.panel,
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  copy.text(CopyKey.appTitle),
                  style: theme.textTheme.titleSmall,
                ),
                AppSpacing.gapXs,
                Row(
                  children: <Widget>[
                    Flexible(
                      child: Text(
                        panelLabelText(copy, view.header),
                        style: theme.textTheme.bodySmall,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    AppSpacing.gapS,
                    StatusBadge(
                      label: copy.text(_statusKey(view.status)),
                      tone: view.readOnly
                          ? StatusTone.caution
                          : StatusTone.neutral,
                    ),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: copy.text(CopyKey.panelActionClose),
            onPressed: () =>
                widget.onCommand(const PanelCommand(PanelCommandKind.close)),
            icon: const Icon(Icons.close, size: 18),
          ),
          IconButton(
            onPressed: _toggleExpanded,
            icon: Icon(
              _expanded ? Icons.expand_less : Icons.expand_more,
              size: 18,
            ),
          ),
        ],
      ),
    ),
  );

  /// The note, and the way out of it when there is one.
  ///
  /// A note is usually only something to read, and this renders exactly as it did
  /// before for those: one line of muted text. Some are not — the platform
  /// refusing because a system permission is off, and the domain refusing a
  /// batch nobody has confirmed — and for those the sentence alone leaves the
  /// user to find their own way from a description of it. That is what made the
  /// first device run of ADR-0018 unreadable, and what left ADR-0019's marking
  /// with nothing to act on, so the note carries what it needs and this draws a
  /// button for it.
  ///
  /// The panel does not open anything and does not review anything: it asks, and
  /// the main engine — which holds the capabilities and the gate — does it.
  Widget _note(AppCopy copy, AppColors colors, ThemeData theme) {
    final PanelNote note = widget.frame.note!;
    final PanelRemedy? remedy = note.remedy;
    return Padding(
      padding: AppSpacing.panel,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            note.text,
            style: theme.textTheme.bodySmall?.copyWith(color: colors.textMuted),
          ),
          if (remedy != null)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.s),
              child: OutlinedButton(
                key: const Key('panel-note-remedy'),
                onPressed: () => widget.onCommand(_remedyCommand(remedy)),
                child: Text(
                  copy.text(switch (remedy) {
                    OpenPermissionPage() => CopyKey.panelActionOpenSettings,
                    EnterReview() => CopyKey.panelActionGoReview,
                  }),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// The command a note's way out asks for.
  ///
  /// The mapping lives here rather than in the protocol, because a note
  /// describes what the user needs and a command asks for an action: the panel
  /// is the only side that turns the first into the second, and the main engine
  /// stays the only side that knows what either means on this port.
  static PanelCommand _remedyCommand(PanelRemedy remedy) => switch (remedy) {
    OpenPermissionPage(:final PermissionKind kind) => PanelCommand(
      PanelCommandKind.openPermissionSettings,
      permission: kind,
    ),
    EnterReview() => const PanelCommand(PanelCommandKind.openReview),
  };

  /// The panel's bottom row, which says which state the panel is in.
  ///
  /// The review owns it while it is up (ADR-0022 decision 10): 「重新分析」 is
  /// gone from that row, because the gate will refuse an unconfirmed batch every
  /// time and a button that cannot succeed is a button the user will press.
  /// 「识别一次」 stays, because re-photographing the screen is the answer to a
  /// capture that read badly and it is not a second button beside the first —
  /// it is the same one.
  Widget _bottomRow(AppCopy copy, PanelView view) {
    if (widget.frame.reviewing) {
      final bool empty = _review.lines(_reviewController.text).isEmpty;
      return Padding(
        padding: AppSpacing.panel,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            if (empty)
              Text(
                copy.text(CopyKey.panelReviewNothingLeft),
                textAlign: TextAlign.end,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            _buttonWrap(<Widget>[
              OutlinedButton(
                key: const Key('panel-review-cancel'),
                onPressed: () => widget.onCommand(
                  const PanelCommand(PanelCommandKind.cancelReview),
                ),
                style: _compactButtonStyle(),
                child: Text(copy.text(CopyKey.panelActionCancelReview)),
              ),
              _recogniseButton(copy),
              FilledButton(
                key: const Key('panel-review-confirm'),
                onPressed: empty ? null : _confirmReview,
                style: _compactButtonStyle(),
                child: Text(copy.text(CopyKey.panelActionConfirmReview)),
              ),
            ]),
          ],
        ),
      );
    }
    return Padding(
      padding: AppSpacing.panel,
      child: _buttonWrap(<Widget>[
        if (view.allows(PanelAction.details))
          OutlinedButton(
            onPressed: () =>
                widget.onCommand(const PanelCommand(PanelCommandKind.details)),
            style: _compactButtonStyle(),
            child: Text(copy.text(CopyKey.panelActionDetails)),
          ),
        // The way back into the review once the batch has been confirmed
        // (ADR-0022 decision 12): a wrong character noticed afterwards should
        // not cost a second photograph of the screen.
        if (widget.frame.transcript.isNotEmpty)
          OutlinedButton(
            key: const Key('panel-review-open'),
            onPressed: () => widget.onCommand(
              const PanelCommand(PanelCommandKind.openReview),
            ),
            style: _compactButtonStyle(),
            child: Text(copy.text(CopyKey.panelActionReview)),
          ),
        _recogniseButton(copy),
        FilledButton(
          onPressed: () => widget.onCommand(
            PanelCommand(
              view.readOnly
                  ? PanelCommandKind.analyseCurrent
                  : PanelCommandKind.reanalyse,
            ),
          ),
          style: _compactButtonStyle(),
          child: Text(
            copy.text(
              view.readOnly
                  ? CopyKey.panelActionAnalyseCurrent
                  : CopyKey.panelActionReanalyse,
            ),
          ),
        ),
      ]),
    );
  }

  Widget _recogniseButton(AppCopy copy) => OutlinedButton(
    key: const Key('panel-recognise-once'),
    onPressed: () =>
        widget.onCommand(const PanelCommand(PanelCommandKind.recogniseOnce)),
    style: _compactButtonStyle(),
    child: Text(copy.text(CopyKey.panelActionRecognise)),
  );

  /// The shared style for the panel's bottom-row buttons.
  ///
  /// The panel is a 300dp overlay, and its buttons are the one thing that can
  /// quietly grow taller than the surface that holds them: Material's default
  /// button is sized for a phone in hand, not a window the size of a note. A
  /// compact density and the label's own size keep the row on one line.
  ButtonStyle _compactButtonStyle() => OutlinedButton.styleFrom(
    visualDensity: VisualDensity.compact,
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.m),
    minimumSize: const Size(0, 36),
    textStyle: Theme.of(context).textTheme.labelSmall,
  );

  /// A Wrap rather than a Row with a Spacer: three buttons in a 300dp panel do
  /// not fit on one line, and the panel is the one surface that cannot grow to
  /// make them.
  Widget _buttonWrap(List<Widget> children) => Wrap(
    alignment: WrapAlignment.end,
    spacing: AppSpacing.s,
    runSpacing: AppSpacing.s,
    children: children,
  );

  /// The batch, editable as one block of text, in place of everything the panel
  /// would otherwise say (ADR-0025).
  ///
  /// The speaker is a prefix on each line rather than a control beside it: one
  /// block costs the panel a line a piece instead of two rows, and a missing
  /// line is a carriage return rather than a button that never existed. The
  /// shortcut row above the block does two jobs: the two speaker buttons rewrite
  /// the prefix of the caret's line (or every line the selection touches), and
  /// 删行 deletes the caret's whole physical line. They are disabled until the
  /// block has been focused, because before that there is no line to act on and
  /// guessing "the last one" would be an intention the user did not state.
  Widget _reviewForm(AppCopy copy, ThemeData theme) => Padding(
    padding: AppSpacing.panel,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // The identity the review confirms, before the block it edits
        // (ADR-0030): a conversation is the application plus the person, and
        // the analysis is gated on both. The person is always the user's to
        // fill; the application is asked for only when the platform could not
        // name it at all — once it is named, there is no field to type in.
        TextField(
          key: const Key('panel-review-title'),
          controller: _titleController,
          textAlignVertical: TextAlignVertical.top,
          style: theme.textTheme.bodySmall,
          onChanged: (_) => setState(() => _identityError = null),
          onTapOutside: (_) => _releaseInputFocus(),
          decoration: InputDecoration(
            isDense: true,
            labelText: copy.text(CopyKey.panelReviewPersonLabel),
            border: const OutlineInputBorder(),
          ),
        ),
        if (!_appIsNamed) ...<Widget>[
          AppSpacing.gapXs,
          TextField(
            key: const Key('panel-review-app'),
            controller: _appNameController,
            textAlignVertical: TextAlignVertical.top,
            style: theme.textTheme.bodySmall,
            onChanged: (_) => setState(() => _identityError = null),
            onTapOutside: (_) => _releaseInputFocus(),
            decoration: InputDecoration(
              isDense: true,
              labelText: copy.text(CopyKey.panelReviewAppLabel),
              border: const OutlineInputBorder(),
            ),
          ),
        ],
        if (_identityError != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Text(
              _identityError!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ),
        AppSpacing.gapXs,
        // The block grows with its content and the panel body scrolls it; there
        // is no `Expanded` here because the body already sits inside a
        // `SingleChildScrollView` whose height is unbounded.
        Listener(
          onPointerDown: (_) async {
            await _takeInputFocus();
            _reviewFocus.requestFocus();
          },
          child: TextField(
            key: const Key('panel-review-block'),
            controller: _reviewController,
            focusNode: _reviewFocus,
            minLines: 6,
            maxLines: null,
            textAlignVertical: TextAlignVertical.top,
            // The block is the densest surface on the panel, so it reads at a
            // size below the body default: a ten-line capture in a 300dp window
            // is what it has to fit, and every point the text gives up is a line
            // the user does not scroll to find.
            style: theme.textTheme.bodySmall,
            // The confirm button is disabled on a block with nothing left in
            // it, so it has to know when the last text goes away.
            onChanged: (_) => setState(() {}),
            onTapOutside: (_) => _releaseInputFocus(),
            decoration: const InputDecoration(
              isDense: true,
              alignLabelWithHint: true,
              border: OutlineInputBorder(),
            ),
          ),
        ),
      ],
    ),
  );

  /// The review's pinned title row: the label plus the two speaker buttons and
  /// 删行.
  ///
  /// It sits above the scroll region (see [build]'s `fixed` list) so that
  /// scrolling the block to edit a line keeps the very controls that rewrite it
  /// on screen. The row itself reads the caret off the controller at press time,
  /// so being pinned away from the block costs it nothing.
  Widget _reviewHeader(AppCopy copy, ThemeData theme) => Padding(
    padding: const EdgeInsets.fromLTRB(
      AppSpacing.s,
      AppSpacing.s,
      AppSpacing.s,
      AppSpacing.xs,
    ),
    child: Row(
      children: <Widget>[
        Expanded(
          child: Text(
            copy.text(CopyKey.panelReviewTitle),
            style: Theme.of(context).textTheme.labelSmall
                ?.copyWith(color: AppColors.of(context).textMuted),
          ),
        ),
        _reviewSpeakerButtons(copy, theme),
      ],
    ),
  );

  /// The shortcut row: the two speaker buttons and 删行.
  ///
  /// 未定 is not a button. ADR-0015 makes it a first-class speaker — a line
  /// nobody has claimed is the honest answer — but the way to *produce* one is
  /// to type the prefix or inherit it, not to tap a third button: a shortcut
  /// whose whole job is "say there is no author" earns its place less than one
  /// that deletes a line the recogniser read wrong. The prefix is still written
  /// out by serialisation, so the state stays reachable without the button.
  Widget _reviewSpeakerButtons(AppCopy copy, ThemeData theme) => Row(
    mainAxisSize: MainAxisSize.min,
    children: <Widget>[
      for (final Speaker speaker in const <Speaker>[Speaker.me, Speaker.other])
        Padding(
          padding: const EdgeInsets.only(left: AppSpacing.xs),
          child: _speakerButton(copy, speaker, theme),
        ),
      Padding(
        padding: const EdgeInsets.only(left: AppSpacing.xs),
        child: _deleteLineButton(copy, theme),
      ),
    ],
  );

  Widget _speakerButton(AppCopy copy, Speaker speaker, ThemeData theme) =>
      // A shortcut that takes focus would be a shortcut that disables itself:
      // the buttons read `_reviewFocus.hasFocus`, and a focused button steals
      // that focus from the block in the same gesture that taps it. `Focus` with
      // `canRequestFocus: false` keeps the tap but refuses the focus, so the
      // caret stays in the block and the button stays enabled.
      Focus(
        canRequestFocus: false,
        child: OutlinedButton(
          key: ValueKey<String>('panel-review-set-${speaker.name}'),
          // No caret, no line to act on: the buttons stay disabled until the block
          // has been focused once.
          //
          // The caret is read off the controller at press time, so nothing has to
          // rebuild for the button to act on it — the parse the button's state
          // came from is the one it edits.
          onPressed: _reviewFocus.hasFocus
              ? () => setState(() {
                  _reviewController.value = _review.setSpeaker(
                    _reviewController.value,
                    speaker,
                  );
                })
              : null,
          style: OutlinedButton.styleFrom(
            visualDensity: VisualDensity.compact,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            // Sharing the row with the title (ADR-0025 amendment) means the
            // buttons are the smallest they can be and still read: no inner
            // padding beyond the label, at the label's own size rather than the
            // button default.
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s),
            minimumSize: Size.zero,
            textStyle: theme.textTheme.labelSmall,
          ),
          child: Text(_speakerLabel(copy, speaker)),
        ),
      );

  /// 删行: deletes the caret's whole physical line, newline and all.
  ///
  /// It is a text edit, not a command to the engine — the block is the source
  /// of truth while the review is up, and deleting a line is deleting text. It
  /// is styled apart from the speaker buttons on purpose: it is the one
  /// destructive action in the row, and red is how the panel says "this is not
  /// reversible".
  Widget _deleteLineButton(AppCopy copy, ThemeData theme) => Focus(
    canRequestFocus: false,
    child: OutlinedButton(
      key: const Key('panel-review-delete-line'),
      onPressed:
          _reviewFocus.hasFocus && _reviewController.text.trim().isNotEmpty
          ? () => setState(() {
              _reviewController.value = _review.deleteLine(
                _reviewController.value,
              );
            })
          : null,
      style: OutlinedButton.styleFrom(
        visualDensity: VisualDensity.compact,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s),
        minimumSize: Size.zero,
        textStyle: theme.textTheme.labelSmall,
        foregroundColor: theme.colorScheme.error,
      ),
      child: Text(copy.text(CopyKey.panelActionDeleteLine)),
    ),
  );

  /// Sends the block up as the user left it, after the identity is complete.
  ///
  /// The command and the confirm button's own enablement read the same door
  /// ([ReviewSession.lines]), so the batch cannot arrive empty on the one frame
  /// the button said it would not (ADR-0025 decision 15). ADR-0030 adds a second
  /// door before it: the person must be named, and the application too when the
  /// platform could not name it at all — otherwise the round behind the next
  /// button would refuse, so the refusal is said here, at the moment it can be
  /// fixed.
  void _confirmReview() {
    final String title = _titleController.text.trim();
    final String appName = _appNameController.text.trim();
    final bool missingTitle = title.isEmpty;
    final bool missingApp = !_appIsNamed && appName.isEmpty;
    if (missingTitle || missingApp) {
      setState(() {
        _identityError = missingTitle
            ? CopyScope.of(context).text(CopyKey.panelReviewPersonRequired)
            : CopyScope.of(context).text(CopyKey.panelReviewAppRequired);
      });
      return;
    }
    setState(() => _identityError = null);
    widget.onCommand(
      PanelCommand(
        PanelCommandKind.confirmTranscript,
        lines: _review.lines(_reviewController.text),
        title: title.isEmpty ? null : title,
        appName: appName.isEmpty ? null : appName,
      ),
    );
  }

  Future<void> _takeInputFocus() async {
    final Future<void> Function(bool focusable)? changeFocus =
        widget.onInputFocusChanged;
    if (changeFocus != null) {
      await changeFocus(true);
    }
  }

  void _releaseInputFocus() {
    FocusManager.instance.primaryFocus?.unfocus();
    final Future<void> Function(bool focusable)? changeFocus =
        widget.onInputFocusChanged;
    if (changeFocus != null) {
      unawaited(changeFocus(false));
    }
  }

  /// What the last whole-frame capture read, in place of the empty state.
  ///
  /// ADR-0018: a capture is the one path where the panel is the only witness.
  /// The note above it asks the user to check the sides before filling a reply
  /// in, and asking for that check without showing what is being checked is what
  /// made a successful read look exactly like a capture that found nothing. So
  /// the lines go where the empty state was: the panel has nothing else to say
  /// until the user asks for an analysis, and a read that worked is the most
  /// interesting thing it knows.
  Widget _transcript(
    AppCopy copy,
    AppColors colors,
    ThemeData theme,
  ) => Padding(
    padding: AppSpacing.panel,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          copy.text(CopyKey.panelTranscriptLabel),
          style: theme.textTheme.labelSmall?.copyWith(color: colors.textMuted),
        ),
        AppSpacing.gapXs,
        // The read-only reading is the same block the review edits (ADR-0025):
        // tapping 「核对」 must not reformat the same words underneath the
        // caret, and the two shapes of one batch must not disagree about what a
        // batch looks like. It scrolls with the body, so no inner scroll.
        Text(
          ReviewBlock.fromLines(widget.frame.transcript, copy),
          style: theme.textTheme.bodySmall,
        ),
      ],
    ),
  );

  /// The side, in the panel's own words rather than the wire's.
  static String _speakerLabel(AppCopy copy, Speaker speaker) =>
      switch (speaker) {
        Speaker.me => copy.text(CopyKey.panelSpeakerMe),
        Speaker.other => copy.text(CopyKey.panelSpeakerOther),
        Speaker.unknown => copy.text(CopyKey.panelSpeakerUnknown),
      };

  /// Why 「填入」 is gone, in so many words. ADR-0002 decision 3 asks for a
  /// banner rather than a silently missing button.
  Widget _banner(AppCopy copy, AppColors colors, ThemeData theme) => Container(
    margin: AppSpacing.panel,
    padding: AppSpacing.panel,
    decoration: BoxDecoration(
      color: colors.toneCautionBackground,
      borderRadius: AppRadius.card,
    ),
    child: Text(
      copy.text(CopyKey.panelReadOnlyBanner),
      style: theme.textTheme.bodySmall?.copyWith(color: colors.toneCaution),
    ),
  );

  static CopyKey _statusKey(PanelStatus status) => switch (status) {
    PanelStatus.notAnalysed => CopyKey.panelStatusNotAnalysed,
    PanelStatus.viewing => CopyKey.panelStatusViewing,
    PanelStatus.browsingReadOnly => CopyKey.panelStatusBrowsing,
  };

  void _toggleExpanded() {
    setState(() => _expanded = !_expanded);
    widget.onExpandedChanged?.call(_expanded);
  }
}
