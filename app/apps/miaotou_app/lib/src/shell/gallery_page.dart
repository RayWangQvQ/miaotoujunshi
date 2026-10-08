import 'package:flutter/material.dart';
import 'package:miaotou_capabilities/miaotou_capabilities.dart';
import 'package:miaotou_domain/miaotou_domain.dart';

import '../design/copy.dart';
import '../design/spacing.dart';
import '../panel/panel_page.dart';
import '../panel/protocol.dart';
import '../widgets/candidate_card.dart';
import '../widgets/status_badge.dart';
import '../widgets/trend_chart.dart';

/// The three shared components, standing still.
///
/// A gallery rather than a widget test, because the point is that a person can
/// look at all three in one place and see whether they agree with each other —
/// a badge's amber next to a chart's red, a candidate card beside the trend it
/// will one day sit above. The trend view and the detail page render the same
/// classes, which is what `test/shared_components_test.dart` checks.
///
/// The samples are built from copy keys and from numbers, never from literals in
/// this file: a Chinese string here would be a second source of truth for what
/// the screen says, and the audit in `test/` would have to let it through.
final class GallerySamples {
  const GallerySamples({
    required this.candidate,
    required this.trend,
    required this.metricNote,
    required this.currentFrame,
    required this.browsingFrame,
  });

  final Candidate candidate;
  final Trend trend;

  /// Stands in for `TrendRules.metricNote`, which a real trend view is handed.
  final String metricNote;

  /// The panel as it looks when the analysed conversation is the one in front
  /// of the user.
  final PanelFrame currentFrame;

  /// The same analysis once the user has moved on: same drafts, no 「填入」.
  ///
  /// Both come from copy keys, so the audit that renders this page with a
  /// sentinel copy still sees only the marker.
  final PanelFrame browsingFrame;

  factory GallerySamples.synthetic(AppCopy copy) {
    final Candidate candidate = Candidate(
      text: copy.text(CopyKey.gallerySampleReply),
      reason: copy.text(CopyKey.gallerySampleReason),
      tradeoff: copy.text(CopyKey.gallerySampleTradeoff),
      weight: 62,
    );
    final Advice advice = Advice(
      support: copy.text(CopyKey.gallerySampleReason),
      facts: <String>[copy.text(CopyKey.gallerySampleTitle)],
      hypotheses: const <String>[],
      unknowns: const <String>[],
      intent: null,
      intentConfidence: null,
      strategy: copy.text(CopyKey.gallerySampleTitle),
      recommendation: copy.text(CopyKey.gallerySampleReason),
      nextStep: copy.text(CopyKey.gallerySampleTradeoff),
      stopCondition: copy.text(CopyKey.gallerySampleTradeoff),
      question: '',
      candidates: <Candidate>[candidate],
      rankingStatus: RankingStatus.ranked,
    );
    final String app = copy.text(CopyKey.gallerySampleApp);
    final String appOther = copy.text(CopyKey.gallerySampleAppOther);
    final String thread = copy.text(CopyKey.gallerySampleThread);
    final String threadOther = copy.text(CopyKey.gallerySampleThreadOther);

    return GallerySamples(
      candidate: candidate,
      trend: Trend(
        title: copy.text(CopyKey.gallerySampleTitle),
        candles: <Candle>[
          const Candle(date: 'D1', open: 0, high: 2, low: -1, close: 2, mine: 3, other: 5),
          const Candle(date: 'D2', open: 2, high: 4, low: 1, close: 1, mine: 6, other: 7),
          const Candle(date: 'D3', open: 1, high: 1, low: -3, close: -3, mine: 8, other: 5),
          const Candle(date: 'D4', open: -3, high: -1, low: -4, close: -1, mine: 4, other: 3),
          const Candle(date: 'D5', open: -1, high: 3, low: -2, close: 3, mine: 2, other: 5),
          const Candle(date: 'D6', open: 3, high: 5, low: 2, close: 4, mine: 1, other: 5),
        ],
        source: copy.text(CopyKey.gallerySampleTitle),
        metric: messageBalanceMetric,
      ),
      metricNote: copy.text(CopyKey.gallerySampleNote),
      currentFrame: PanelFrame(
        analysed: ConversationRef(
          packageName: 'com.tencent.mm',
          appName: app,
          title: thread,
        ),
        live: ConversationRef(
          packageName: 'com.tencent.mm',
          appName: app,
          title: thread,
        ),
        advice: advice,
      ),
      browsingFrame: PanelFrame(
        analysed: ConversationRef(
          packageName: 'com.tencent.mm',
          appName: app,
          title: thread,
        ),
        live: ConversationRef(
          packageName: 'com.tencent.mobileqq',
          appName: appOther,
          title: threadOther,
        ),
        advice: advice,
      ),
    );
  }
}

/// The gallery as a route: a scaffold of its own, because it is pushed onto the
/// navigator and a pushed page has to bring its own way back.
class GalleryPage extends StatelessWidget {
  const GalleryPage({super.key, required this.samples});

  final GallerySamples samples;

  @override
  Widget build(BuildContext context) {
    final AppCopy copy = CopyScope.of(context);
    final ThemeData theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(copy.text(CopyKey.galleryTitle))),
      body: ListView(
        padding: AppSpacing.page,
        children: <Widget>[
          Text(
            copy.text(CopyKey.galleryIntro),
            style: theme.textTheme.bodyMedium,
          ),
          AppSpacing.gapL,
          Text(
            copy.text(CopyKey.galleryCandidateCard),
            style: theme.textTheme.titleSmall,
          ),
          AppSpacing.gapS,
          CandidateCard(
            candidate: samples.candidate,
            rank: 1,
            rankingStatus: RankingStatus.ranked,
          ),
          AppSpacing.gapL,
          Text(
            copy.text(CopyKey.galleryBadge),
            style: theme.textTheme.titleSmall,
          ),
          AppSpacing.gapS,
          Wrap(
            spacing: AppSpacing.s,
            runSpacing: AppSpacing.xs,
            children: <Widget>[
              StatusBadge(label: copy.text(CopyKey.galleryToneNeutral)),
              StatusBadge(
                label: copy.text(CopyKey.galleryTonePositive),
                tone: StatusTone.positive,
              ),
              StatusBadge(
                label: copy.text(CopyKey.galleryToneCaution),
                tone: StatusTone.caution,
              ),
              StatusBadge(
                label: copy.text(CopyKey.galleryToneAlert),
                tone: StatusTone.alert,
              ),
            ],
          ),
          AppSpacing.gapL,
          Text(
            copy.text(CopyKey.galleryTrendChart),
            style: theme.textTheme.titleSmall,
          ),
          AppSpacing.gapS,
          TrendChart(
            trend: samples.trend,
            metricNote: samples.metricNote,
          ),
          AppSpacing.gapL,
          Text(
            copy.text(CopyKey.panelPreviewCurrent),
            style: theme.textTheme.titleSmall,
          ),
          AppSpacing.gapS,
          PanelPage(
            frame: samples.currentFrame,
            onCommand: _noCommand,
          ),
          AppSpacing.gapL,
          Text(
            copy.text(CopyKey.panelPreviewBrowsing),
            style: theme.textTheme.titleSmall,
          ),
          AppSpacing.gapS,
          PanelPage(
            frame: samples.browsingFrame,
            onCommand: _noCommand,
          ),
        ],
      ),
    );
  }
}

/// The gallery has nowhere to send a command to.
///
/// The panel is a pure renderer — it is handed a frame and a callback — so it
/// renders in a gallery unchanged, and the one thing a real host would do with
/// the command is the only thing missing.
void _noCommand(PanelCommand command) {}
