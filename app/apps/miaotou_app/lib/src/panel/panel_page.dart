import 'dart:async';

import 'package:flutter/material.dart';
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
  List<TextEditingController> _drafts = <TextEditingController>[];
  List<FocusNode> _draftFocus = <FocusNode>[];

  @override
  void initState() {
    super.initState();
    _expanded = widget.initialExpanded;
    _replaceDrafts();
  }

  @override
  void didUpdateWidget(PanelPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_sameDrafts(oldWidget.frame.advice, widget.frame.advice)) {
      _replaceDrafts();
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
      note: widget.frame.note,
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
      if (widget.frame.note != null)
        Padding(
          padding: AppSpacing.card,
          child: Text(
            widget.frame.note!,
            style: theme.textTheme.bodySmall?.copyWith(color: colors.textMuted),
          ),
        ),
    ];
    final Widget body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (advice == null)
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
                      final Future<void> Function(bool focusable)? changeFocus =
                          widget.onInputFocusChanged;
                      if (changeFocus != null) {
                        await changeFocus(true);
                      }
                      _draftFocus[i].requestFocus();
                    },
                    child: TextField(
                      key: ValueKey<String>('panel-draft-$i'),
                      controller: _drafts[i],
                      focusNode: _draftFocus[i],
                      decoration: InputDecoration(
                        labelText: copy.text(CopyKey.panelDraftLabel),
                      ),
                      onTapOutside: (_) {
                        FocusManager.instance.primaryFocus?.unfocus();
                        final Future<void> Function(bool focusable)?
                        changeFocus = widget.onInputFocusChanged;
                        if (changeFocus != null) {
                          unawaited(changeFocus(false));
                        }
                      },
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
        Padding(
          padding: AppSpacing.card,
          // A Wrap rather than a Row with a Spacer: three buttons in a 300dp
          // panel do not fit on one line, and the panel is the one surface that
          // cannot grow to make them.
          child: Wrap(
            alignment: WrapAlignment.end,
            spacing: AppSpacing.s,
            runSpacing: AppSpacing.s,
            children: <Widget>[
              if (view.allows(PanelAction.details))
                OutlinedButton(
                  onPressed: () => widget.onCommand(
                    const PanelCommand(PanelCommandKind.details),
                  ),
                  child: Text(copy.text(CopyKey.panelActionDetails)),
                ),
              OutlinedButton(
                key: const Key('panel-recognise-once'),
                onPressed: () => widget.onCommand(
                  const PanelCommand(PanelCommandKind.recogniseOnce),
                ),
                child: Text(copy.text(CopyKey.panelActionRecognise)),
              ),
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
            ],
          ),
        ),
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
}
