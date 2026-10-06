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
    this.onReviewChanged,
    this.initialExpanded = true,
  });

  /// Everything the panel may show. The only thing going down.
  final PanelFrame frame;

  /// The only thing going up.
  final void Function(PanelCommand command) onCommand;
  final ValueChanged<bool>? onExpandedChanged;
  final VoidCallback? onDragStart;
  final Future<void> Function(bool focusable)? onInputFocusChanged;

  /// Asks the host for a taller window while the review is up.
  ///
  /// The panel does not resize itself and cannot: the window belongs to the
  /// host, and on Android it is the host's own overlay. The review is a form,
  /// and on a 380 dp window with no `adjustResize` the keyboard covers it.
  final Future<void> Function(bool reviewing)? onReviewChanged;
  final bool initialExpanded;

  @override
  State<PanelPage> createState() => _PanelPageState();
}

class _PanelPageState extends State<PanelPage> {
  /// Transient: whether the body is showing.
  late bool _expanded;

  /// Transient: where the user dragged the panel to.
  Offset _landing = Offset.zero;
  List<TextEditingController> _drafts = <TextEditingController>[];
  List<FocusNode> _draftFocus = <FocusNode>[];

  /// Transient: the batch as the user is editing it, and nothing else.
  ///
  /// The review is a surface over a batch the main engine owns, so what lives
  /// here is only the edit in progress. Confirming sends it up; leaving the
  /// state throws it away. [_reviewSource] is the batch these rows were built
  /// from, which is how a republish of the same batch is told from a new one.
  List<_ReviewRow> _review = <_ReviewRow>[];
  List<PanelLine> _reviewSource = const <PanelLine>[];

  @override
  void initState() {
    super.initState();
    _expanded = widget.initialExpanded;
    _replaceDrafts();
    _replaceReview();
    // A panel engine that starts while a review is already up — the window was
    // recreated — still has to ask for the taller window, and no frame change
    // will come to tell it.
    if (widget.frame.reviewing) {
      _requestReviewSize(true);
    }
  }

  @override
  void didUpdateWidget(PanelPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_sameDrafts(oldWidget.frame.advice, widget.frame.advice)) {
      _replaceDrafts();
    }
    if (widget.frame.reviewing != oldWidget.frame.reviewing) {
      _requestReviewSize(widget.frame.reviewing);
    }
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
    for (final TextEditingController controller in _drafts) {
      controller.dispose();
    }
    for (final FocusNode node in _draftFocus) {
      node.dispose();
    }
    for (final _ReviewRow row in _review) {
      row.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppCopy copy = CopyScope.of(context);
    final AppColors colors = AppColors.of(context);
    final ThemeData theme = Theme.of(context);
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
              padding: AppSpacing.card,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  CandidateCard(
                    candidate: advice.candidates[i],
                    rank: i + 1,
                    rankingStatus: advice.rankingStatus,
                    onCopy: view.allows(PanelAction.copy)
                        ? () => widget.onCommand(
                            PanelCommand(
                              PanelCommandKind.copy,
                              candidateIndex: i,
                              text: _drafts[i].text,
                            ),
                          )
                        : null,
                  ),
                  Listener(
                    onPointerDown: (_) async {
                      await _takeInputFocus();
                      _draftFocus[i].requestFocus();
                    },
                    child: TextField(
                      key: ValueKey<String>('panel-draft-$i'),
                      controller: _drafts[i],
                      focusNode: _draftFocus[i],
                      decoration: InputDecoration(
                        labelText: copy.text(CopyKey.panelDraftLabel),
                      ),
                      onTapOutside: (_) => _releaseInputFocus(),
                    ),
                  ),
                  if (view.allows(PanelAction.fill))
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.s),
                      child: FilledButton.tonal(
                        onPressed: () => widget.onCommand(
                          PanelCommand(
                            PanelCommandKind.fill,
                            candidateIndex: i,
                            text: _drafts[i].text,
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

    return Transform.translate(
      // Keyed so a test can read the offset the user dragged to.
      key: const Key('panel-landing'),
      offset: _landing,
      child: Card(
        margin: EdgeInsets.zero,
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) => Column(
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
      padding: AppSpacing.card,
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
      padding: AppSpacing.card,
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
      final bool empty = _reviewIsEmpty;
      return Padding(
        padding: AppSpacing.card,
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
                child: Text(copy.text(CopyKey.panelActionCancelReview)),
              ),
              _recogniseButton(copy),
              FilledButton(
                key: const Key('panel-review-confirm'),
                onPressed: empty ? null : _confirmReview,
                child: Text(copy.text(CopyKey.panelActionConfirmReview)),
              ),
            ]),
          ],
        ),
      );
    }
    return Padding(
      padding: AppSpacing.card,
      child: _buttonWrap(<Widget>[
        if (view.allows(PanelAction.details))
          OutlinedButton(
            onPressed: () => widget.onCommand(
              const PanelCommand(PanelCommandKind.details),
            ),
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
    child: Text(copy.text(CopyKey.panelActionRecognise)),
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

  /// The batch, editable, in place of everything the panel would otherwise say.
  ///
  /// Two rows per line rather than one, which is a trade the 300dp panel forces:
  /// the text is what the user actually reads and corrects, so it gets the full
  /// width, and the three-state speaker and the two line operations sit above
  /// it. One row would have left a text field about a hundred points wide.
  Widget _reviewForm(AppCopy copy, AppColors colors, ThemeData theme) => Padding(
    padding: AppSpacing.card,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          copy.text(CopyKey.panelReviewTitle),
          style: theme.textTheme.labelSmall?.copyWith(color: colors.textMuted),
        ),
        AppSpacing.gapXs,
        Text(
          copy.text(CopyKey.panelReviewHint),
          style: theme.textTheme.bodySmall?.copyWith(color: colors.textMuted),
        ),
        for (int index = 0; index < _review.length; index++)
          _reviewRow(copy, index),
      ],
    ),
  );

  Widget _reviewRow(AppCopy copy, int index) {
    final _ReviewRow row = _review[index];
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.s),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: SegmentedButton<Speaker>(
                  key: ValueKey<String>('panel-review-speaker-$index'),
                  segments: <ButtonSegment<Speaker>>[
                    ButtonSegment<Speaker>(
                      value: Speaker.me,
                      label: Text(copy.text(CopyKey.panelSpeakerMe)),
                    ),
                    ButtonSegment<Speaker>(
                      value: Speaker.other,
                      label: Text(copy.text(CopyKey.panelSpeakerOther)),
                    ),
                    // The third state is the whole reason this is not a toggle:
                    // ADR-0015 makes admitting there is no author better than
                    // inventing one, and the review is where the user gets to
                    // say so.
                    ButtonSegment<Speaker>(
                      value: Speaker.unknown,
                      label: Text(copy.text(CopyKey.panelSpeakerUnknown)),
                    ),
                  ],
                  selected: <Speaker>{row.speaker},
                  showSelectedIcon: false,
                  onSelectionChanged: (Set<Speaker> value) =>
                      setState(() => row.speaker = value.first),
                  style: const ButtonStyle(
                    visualDensity: VisualDensity.compact,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ),
              _lineAction(
                key: ValueKey<String>('panel-review-merge-$index'),
                tooltip: copy.text(CopyKey.panelActionMergeUp),
                icon: Icons.vertical_align_top,
                // Nothing above the first line to fold it into.
                onPressed: index == 0 ? null : () => _mergeUp(index),
              ),
              _lineAction(
                key: ValueKey<String>('panel-review-delete-$index'),
                tooltip: copy.text(CopyKey.panelActionDeleteLine),
                icon: Icons.close,
                onPressed: () => _deleteLine(index),
              ),
            ],
          ),
          Listener(
            onPointerDown: (_) async {
              await _takeInputFocus();
              row.focus.requestFocus();
            },
            child: TextField(
              key: ValueKey<String>('panel-review-text-$index'),
              controller: row.controller,
              focusNode: row.focus,
              minLines: 1,
              maxLines: 3,
              // The confirm button is disabled on a batch with nothing left in
              // it, so it has to know when the last text goes away.
              onChanged: (_) => setState(() {}),
              onTapOutside: (_) => _releaseInputFocus(),
              decoration: const InputDecoration(isDense: true),
            ),
          ),
        ],
      ),
    );
  }

  Widget _lineAction({
    required Key key,
    required String tooltip,
    required IconData icon,
    required VoidCallback? onPressed,
  }) => IconButton(
    key: key,
    tooltip: tooltip,
    iconSize: 18,
    visualDensity: VisualDensity.compact,
    padding: EdgeInsets.zero,
    constraints: const BoxConstraints.tightFor(width: 32, height: 32),
    onPressed: onPressed,
    icon: Icon(icon),
  );

  /// Whether every line has been emptied out, which is the one thing the user
  /// can do here that leaves nothing to analyse.
  bool get _reviewIsEmpty =>
      _review.every((_ReviewRow row) => row.controller.text.trim().isEmpty);

  void _mergeUp(int index) {
    if (index <= 0 || index >= _review.length) {
      return;
    }
    setState(() {
      final _ReviewRow previous = _review[index - 1];
      final _ReviewRow current = _review.removeAt(index);
      // The rule `_Group.text` already uses for one wrapped bubble, and the
      // upper line keeps the speaker: a split that was not a split is one
      // message, and the user is folding the two halves of it back together.
      previous.controller.text =
          '${previous.controller.text.trim()} ${current.controller.text.trim()}'
              .trim();
      current.dispose();
    });
  }

  void _deleteLine(int index) {
    setState(() {
      _review.removeAt(index).dispose();
    });
  }

  void _confirmReview() {
    widget.onCommand(
      PanelCommand(
        PanelCommandKind.confirmTranscript,
        lines: <PanelLine>[
          for (final _ReviewRow row in _review)
            PanelLine(speaker: row.speaker, text: row.controller.text.trim()),
        ],
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

  void _requestReviewSize(bool reviewing) {
    final Future<void> Function(bool reviewing)? change = widget.onReviewChanged;
    if (change != null) {
      unawaited(change(reviewing));
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
    padding: AppSpacing.card,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          copy.text(CopyKey.panelTranscriptLabel),
          style: theme.textTheme.labelSmall?.copyWith(color: colors.textMuted),
        ),
        for (final PanelLine line in widget.frame.transcript)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Text(
              copy
                  .text(CopyKey.panelTranscriptLine)
                  .replaceAll('{who}', _speakerLabel(copy, line.speaker))
                  .replaceAll('{text}', line.text),
              style: theme.textTheme.bodySmall,
            ),
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
    margin: AppSpacing.card,
    padding: AppSpacing.card,
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

  bool _sameDrafts(Advice? before, Advice? after) {
    final List<Candidate> oldCandidates =
        before?.candidates ?? const <Candidate>[];
    final List<Candidate> newCandidates =
        after?.candidates ?? const <Candidate>[];
    if (oldCandidates.length != newCandidates.length) {
      return false;
    }
    for (int index = 0; index < oldCandidates.length; index++) {
      if (oldCandidates[index].text != newCandidates[index].text) {
        return false;
      }
    }
    return true;
  }

  void _replaceDrafts() {
    for (final TextEditingController controller in _drafts) {
      controller.dispose();
    }
    for (final FocusNode node in _draftFocus) {
      node.dispose();
    }
    _drafts = <TextEditingController>[
      for (final Candidate candidate
          in widget.frame.advice?.candidates ?? const <Candidate>[])
        TextEditingController(text: candidate.text),
    ];
    _draftFocus = <FocusNode>[
      for (int index = 0; index < _drafts.length; index++) FocusNode(),
    ];
  }

  /// Builds the editable rows out of the batch the main engine sent down.
  ///
  /// Called without `setState` from [didUpdateWidget], where a rebuild is
  /// already on its way — and from [initState], where there is nothing to
  /// rebuild yet. Every call is a fresh copy of the batch, so any edit in
  /// progress goes with the old one, which is the point: the rows are only ever
  /// the batch that is actually on the panel.
  void _replaceReview() {
    for (final _ReviewRow row in _review) {
      row.dispose();
    }
    _reviewSource = widget.frame.transcript;
    _review = <_ReviewRow>[
      for (final PanelLine line in _reviewSource)
        _ReviewRow(speaker: line.speaker, text: line.text),
    ];
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

/// One line of the batch while it is being reviewed.
///
/// The speaker is the domain's own three-valued one, so the panel cannot invent
/// a fourth; the text lives in a controller because that is what an editable
/// field needs, and the pair is the whole of the state.
final class _ReviewRow {
  _ReviewRow({required this.speaker, required String text})
    : controller = TextEditingController(text: text);

  Speaker speaker;
  final TextEditingController controller;
  final FocusNode focus = FocusNode();

  void dispose() {
    controller.dispose();
    focus.dispose();
  }
}
