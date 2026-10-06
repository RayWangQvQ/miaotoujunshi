import 'dart:async';

import 'package:flutter/material.dart';
import 'package:miaotou_capabilities/miaotou_capabilities.dart'
    show PermissionKind, Speaker;
import 'package:miaotou_domain/miaotou_domain.dart';

import '../design/colors.dart';
import '../design/copy.dart';
import '../design/spacing.dart';
import '../widgets/candidate_card.dart';
import '../widgets/empty_state.dart';
import '../widgets/status_badge.dart';
import 'protocol.dart';
import 'review_block.dart';

/// The conversation label as the header prints it, built out of copy.
///
/// Four branches and not one interpolation, because the fallbacks are the rule:
/// a thread whose title could not be read is named after the app and the
/// placeholder, and a conversation we know nothing about is the placeholder
/// alone. The domain decides *which* branch ([ConversationLabelKind]); only the
/// words live in [AppCopy].
String panelLabelText(AppCopy copy, ConversationLabel label) {
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
      title: unrecognised,
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
/// **Only transient state lives here.** [_PanelPageState] holds two fields —
/// whether the panel is expanded, and where the user last dropped it — and both
/// are facts about this window's surface, lost when it goes away. The advice,
/// the conversation and the verdict are all in [PanelPage.frame] and are
/// somebody else's to change; this widget renders what it is handed and asks for
/// what it wants through [PanelPage.onCommand]. That is #12, AC1, and
/// `test/panel_test.dart` scans this file for a field that would break it.
///
/// **No capability is called from here.** The panel cannot ask which
/// application is in front, because asking would put a second source of truth
/// beside the main window's — which is the drift ADR-0002 decision 2 exists to
/// prevent. It derives read-only from the two refs in the frame, exactly as that
/// decision says the view should, and it resolves a package to a name using the
/// map the frame brought.
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

  /// Transient: the batch as the user is editing it, and nothing else.
  ///
  /// The review is a surface over a batch the main engine owns, so what lives
  /// here is only the edit in progress. Confirming sends it up; leaving the
  /// state throws it away. The whole batch is one editable block (ADR-0025),
  /// so the edit is a single controller; [_reviewSource] is the batch the block
  /// was built from, which is how a republish of the same batch is told from a
  /// new one.
  final TextEditingController _reviewController = TextEditingController();
  final FocusNode _reviewFocus = FocusNode();
  List<PanelLine> _reviewSource = const <PanelLine>[];

  @override
  void initState() {
    super.initState();
    _expanded = widget.initialExpanded;
    // Only the source is recorded here: turning it into the block needs the
    // copy, and an inherited widget cannot be read from `initState`. The block
    // itself is written once the dependencies exist ([didChangeDependencies]).
    _reviewSource = widget.frame.transcript;
    // The speaker buttons gate on the block having a caret, and focus does not
    // rebuild on its own, so a change to it has to ask for one.
    _reviewFocus.addListener(() => setState(() {}));
  }

  bool _reviewLoaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The first build of the block needs the copy, which is why it waits for
    // this rather than `initState`. A republish that changed the batch still
    // goes through [_replaceReview] below.
    if (!_reviewLoaded) {
      _reviewLoaded = true;
      _reviewController.text = ReviewBlock.fromLines(
        _reviewSource,
        CopyScope.of(context),
      );
    }
  }

  @override
  void didUpdateWidget(PanelPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Entering the state, or being handed a different batch while in it. Both
    // are the same question — "are these rows still the batch on the panel?" —
    // and a frame that only repeated what is already loaded must not wipe an
    // edit in progress.
    if (widget.frame.reviewing &&
        (!oldWidget.frame.reviewing ||
            !_sameLines(widget.frame.transcript, _reviewSource))) {
      _replaceReview();
    }
  }

  @override
  void dispose() {
    _reviewController.dispose();
    _reviewFocus.dispose();
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
      appName: widget.frame.appNameFor,
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
          _reviewForm(copy, colors, theme)
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
                        panelLabelText(copy, view.analysed),
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
      final bool empty = _reviewIsEmpty(copy);
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
                onPressed: empty ? null : () => _confirmReview(copy),
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
            onPressed: () => widget.onCommand(
              const PanelCommand(PanelCommandKind.details),
            ),
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
  Widget _reviewForm(AppCopy copy, AppColors colors, ThemeData theme) => Padding(
    padding: AppSpacing.panel,
    // The whole form — title, shortcut buttons and the block — sits inside one
    // `TextFieldTapRegion` so that tapping a shortcut is *not* a tap outside
    // the field. The shortcut buttons act on the caret, and a tap that first
    // dismissed the caret would leave them nothing to act on: the field's own
    // `onTapOutside` unfocuses it, which flips `_reviewFocus.hasFocus` to false
    // and the buttons disable themselves in the very frame the tap lands. One
    // region keeps the buttons and the block in the same `EditableText` group,
    // so the buttons read the caret instead of killing it.
    child: TextFieldTapRegion(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // The title and the shortcut buttons share one row, because the
          // block is what the user reads and the header is what the 300dp panel
          // can least afford to give two lines (ADR-0025 amendment: the hint and
          // the fixed example line are gone — the block's own `我：`/`对方：`
          // prefixes teach the rule by being in front of the user's eyes).
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  copy.text(CopyKey.panelReviewTitle),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colors.textMuted,
                  ),
                ),
              ),
              _reviewSpeakerButtons(copy, theme),
            ],
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
          onPressed: _reviewFocus.hasFocus
              ? () => _setSpeaker(speaker, copy)
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
          ? () => _deleteLine()
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

  /// Deletes the physical line the caret is on.
  ///
  /// "Physical" is deliberate: a chat message that wrapped is several physical
  /// lines, and the user asked to delete the line they can see, not the message
  /// the model will later read. A non-last line goes with its trailing newline,
  /// a last line with its preceding newline, so the two neighbours meet rather
  /// than leaving a blank line behind. The caret falls back to the start of the
  /// deleted span, so tapping 删行 again removes the next line.
  void _deleteLine() {
    final TextEditingValue value = _reviewController.value;
    final String text = value.text;
    final TextSelection selection = value.selection;
    final int caret = selection.start < 0 ? 0 : selection.start;
    final int lineStart = text.lastIndexOf('\n', caret - 1) + 1;
    final int lineEnd = text.indexOf('\n', caret); // -1 when the caret is on the last line

    final int delStart;
    final int delEnd;
    if (lineEnd != -1) {
      // Not the last line: the line plus its trailing newline.
      delStart = lineStart;
      delEnd = lineEnd + 1;
    } else if (lineStart > 0) {
      // The last line: its preceding newline plus the line.
      delStart = lineStart - 1;
      delEnd = text.length;
    } else {
      // The only line there is.
      delStart = 0;
      delEnd = text.length;
    }

    setState(() {
      _reviewController.value = TextEditingValue(
        text: text.replaceRange(delStart, delEnd, ''),
        selection: TextSelection.collapsed(offset: delStart),
      );
    });
  }

  /// Rewrites the prefix of the caret's line — or of every line the selection
  /// covers — to [speaker].
  void _setSpeaker(Speaker speaker, AppCopy copy) {
    final TextEditingValue value = _reviewController.value;
    final String text = value.text;
    final TextSelection selection = value.selection;
    final int start = selection.start < 0 ? 0 : selection.start;
    final int end = selection.end < 0 ? start : selection.end;
    // The first line the selection touches, and the one after its end. A
    // collapsed caret sets start == end and so a single line.
    final int lineStart = text.lastIndexOf('\n', start - 1) + 1;
    int lineEnd = text.indexOf('\n', end);
    if (lineEnd == -1) {
      lineEnd = text.length;
    }

    final String prefix = '${ReviewBlock.wordOf(speaker, copy)}：';
    final String replacement = _rewriteSpan(
      text,
      lineStart,
      lineEnd,
      prefix,
      copy,
    );
    final int caret = _caretAfter(
      replacement,
      lineStart,
      prefix,
      end,
    );
    setState(() {
      _reviewController.value = TextEditingValue(
        text: replacement,
        selection: TextSelection.collapsed(offset: caret),
      );
    });
  }

  /// Replaces the speaker prefix of every line in `[lineStart, lineEnd)`.
  String _rewriteSpan(
    String text,
    int lineStart,
    int lineEnd,
    String prefix,
    AppCopy copy,
  ) {
    final String span = text.substring(lineStart, lineEnd);
    final List<String> rewritten = <String>[];
    for (final String raw in span.split('\n')) {
      final String line = raw.trim();
      final Speaker? matched = ReviewBlock.speakerOf(line, copy);
      if (matched == null) {
        rewritten.add('$prefix$line');
      } else {
        rewritten.add('$prefix${ReviewBlock.bodyOf(line, matched, copy)}');
      }
    }
    return text.replaceRange(lineStart, lineEnd, rewritten.join('\n'));
  }

  /// Where the caret should land after a rewrite: at the end of the original
  /// selection's extent, but never before the new prefix of that line.
  int _caretAfter(String replacement, int lineStart, String prefix, int end) {
    final int endLineStart = replacement.lastIndexOf('\n', end - 1) + 1;
    final int prefixEnd = endLineStart + prefix.length;
    return end < prefixEnd ? prefixEnd : end;
  }

  /// Whether the block has nothing left to analyse in it.
  bool _reviewIsEmpty(AppCopy copy) =>
      ReviewBlock.toLines(_reviewController.text, copy).isEmpty;

  void _confirmReview(AppCopy copy) {
    widget.onCommand(
      PanelCommand(
        PanelCommandKind.confirmTranscript,
        lines: ReviewBlock.toLines(_reviewController.text, copy),
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
  Widget _transcript(AppCopy copy, AppColors colors, ThemeData theme) => Padding(
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
  static String _speakerLabel(AppCopy copy, Speaker speaker) => switch (speaker) {
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

  /// Loads the editable block out of the batch the main engine sent down.
  ///
  /// Called from [didUpdateWidget], where a rebuild is already on its way, and
  /// where the copy is readable. Every call is a fresh copy of the batch, so
  /// any edit in progress goes with the old one, which is the point: the block
  /// is only ever the batch that is actually on the panel.
  void _replaceReview() {
    _reviewSource = widget.frame.transcript;
    _reviewController.text = ReviewBlock.fromLines(
      _reviewSource,
      CopyScope.of(context),
    );
  }

  static bool _sameLines(List<PanelLine> before, List<PanelLine> after) {
    if (before.length != after.length) {
      return false;
    }
    for (int index = 0; index < before.length; index++) {
      if (before[index].speaker != after[index].speaker ||
          before[index].text != after[index].text) {
        return false;
      }
    }
    return true;
  }
}
