import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:miaotou_domain/miaotou_domain.dart';

import '../design/colors.dart';
import '../design/spacing.dart';

/// The K-line, drawn from candles the domain already computed.
///
/// Two things this widget does not do:
///
/// * **It draws no numbers of its own.** The scale is geometry. A chart that
///   printed its own axis labels would be a second place where the metric is
///   described, and the payload already has one.
/// * **It will not draw without [metricNote].** That sentence is `metric_note`
///   in `trend-rules.json` and it says what the number is *not* — a message
///   balance, not a relationship score. #8 made it travel with the data for
///   exactly this reason: a caller that never saw it could render a chart that
///   looks like a score. Requiring it here is what closes that door.
///
/// Rising is red and falling is green, which is the convention a reader of a
/// K-line in this language expects. It is a direction, not a judgement: a day
/// where the other person wrote more raises the balance, and nothing about that
/// is good or bad.
class TrendChart extends StatelessWidget {
  const TrendChart({
    super.key,
    required this.trend,
    required this.metricNote,
    this.height = 168,
  });

  final Trend trend;

  /// The payload's disclaimer. Must come from [TrendRules.metricNote].
  final String metricNote;

  final double height;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(
          height: height,
          width: double.infinity,
          child: CustomPaint(
            painter: _CandlePainter(trend: trend, colors: colors),
          ),
        ),
        AppSpacing.gapS,
        Text(
          metricNote,
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: colors.textMuted),
        ),
      ],
    );
  }
}

final class _CandlePainter extends CustomPainter {
  const _CandlePainter({required this.trend, required this.colors});

  final Trend trend;
  final AppColors colors;

  @override
  void paint(Canvas canvas, Size size) {
    final List<Candle> candles = trend.candles;
    if (candles.isEmpty || size.width <= 0) {
      return;
    }

    int low = candles.first.low;
    int high = candles.first.high;
    for (final Candle candle in candles) {
      if (candle.low < low) {
        low = candle.low;
      }
      if (candle.high > high) {
        high = candle.high;
      }
    }

    // A flat series has no range to divide by; drawing it as a line across the
    // middle is the honest picture, and dividing by zero is not.
    final double range = (high - low).toDouble();
    final double drawnHeight = size.height - AppSpacing.m;
    double yFor(int value) =>
        AppSpacing.xs + (drawnHeight * (1 - (value - low) / (range == 0 ? 1 : range)));

    final double slot = size.width / candles.length;
    final double bodyWidth = (slot * 0.55).clamp(2.0, AppSpacing.l).toDouble();

    for (int index = 0; index < candles.length; index++) {
      final Candle candle = candles[index];
      final double x = slot * (index + 0.5);
      final Color color = candle.close >= candle.open
          ? colors.balanceUp
          : colors.balanceDown;
      final Paint paint = Paint()
        ..color = color
        ..strokeWidth = 1;

      canvas.drawLine(
        Offset(x, yFor(candle.high)),
        Offset(x, yFor(candle.low)),
        paint,
      );
      canvas.drawRect(
        Rect.fromLTWH(
          x - bodyWidth / 2,
          yFor(math.max(candle.open, candle.close)),
          bodyWidth,
          math.max(
            yFor(math.min(candle.open, candle.close)) -
                yFor(math.max(candle.open, candle.close)),
            1,
          ),
        ),
        Paint()..color = color,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CandlePainter oldPainter) =>
      oldPainter.trend != trend || oldPainter.colors != colors;
}
