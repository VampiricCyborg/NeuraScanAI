/// The charts of the results module.
///
/// Every chart can be read without colour and without sight:
///
/// * a counted test is a **filled circle**, a test the check-in set aside is a **hollow circle**
///   and is never joined into the line;
/// * the smoothed curve is **dashed**, the baseline **dotted**, the usual-spread band a **pale
///   fill**, the population range a **hatched-look outline band** in a second colour;
/// * the series colours come from the Okabe-Ito palette (see `kDomainColors`), chosen to stay
///   apart for the common kinds of colour-blindness;
/// * each chart carries a spoken description: "Delayed recall, trend declining over 8 tests".
///
/// A population band is drawn only when its range is validated. A placeholder draws nothing,
/// and no chart here marks a value normal or abnormal.
library;

import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../app/l10n/generated/app_localizations.dart';
import '../../../app/theme.dart';
import '../../../app/widgets.dart';
import '../../../engine/constants.dart';
import '../../../engine/features.dart';
import '../../trends/baseline_format.dart';
import '../calculators/analysis.dart';
import '../calculators/trend_stats.dart';
import '../models.dart';
import '../report_constants.dart';
import 'report_text.dart';
import 'verdict.dart';

/// Tallest a chart is drawn, so text scaled to 200% does not squeeze it to nothing.
const double kChartHeight = 220;

/// One thing a chart's legend explains.
class LegendItem {
  const LegendItem({
    required this.label,
    required this.color,
    this.kind = LegendKind.line,
  });

  final String label;
  final Color color;
  final LegendKind kind;
}

/// The shape of a legend swatch. Different shapes, not only different colours.
enum LegendKind { line, dashed, dotted, filledDot, hollowDot, band, square }

/// A wrapping legend, so it survives large text.
class ChartLegend extends StatelessWidget {
  const ChartLegend({required this.items, super.key});

  final List<LegendItem> items;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 16,
      runSpacing: 8,
      children: [
        for (final item in items)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _Swatch(item: item),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  item.label,
                  style: context.texts.bodySmall?.copyWith(
                    color: context.colors.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
      ],
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({required this.item});

  final LegendItem item;

  @override
  Widget build(BuildContext context) {
    const size = Size(24, 14);
    return CustomPaint(
      size: size,
      painter: _SwatchPainter(item.kind, item.color),
    );
  }
}

class _SwatchPainter extends CustomPainter {
  const _SwatchPainter(this.kind, this.color);

  final LegendKind kind;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final mid = size.height / 2;
    final line = Paint()
      ..color = color
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    switch (kind) {
      case LegendKind.line:
        canvas.drawLine(Offset(0, mid), Offset(size.width, mid), line);
      case LegendKind.dashed:
        for (var x = 0.0; x < size.width; x += 9) {
          canvas.drawLine(
            Offset(x, mid),
            Offset(math.min(x + 5, size.width), mid),
            line,
          );
        }
      case LegendKind.dotted:
        for (var x = 1.0; x < size.width; x += 5) {
          canvas.drawCircle(Offset(x, mid), 1.2, Paint()..color = color);
        }
      case LegendKind.filledDot:
        canvas.drawCircle(
          Offset(size.width / 2, mid),
          5,
          Paint()..color = color,
        );
      case LegendKind.hollowDot:
        canvas.drawCircle(
          Offset(size.width / 2, mid),
          4.5,
          Paint()
            ..color = color
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.2,
        );
      case LegendKind.band:
        canvas.drawRect(
          Rect.fromLTWH(0, 2, size.width, size.height - 4),
          Paint()..color = color.withValues(alpha: 0.25),
        );
        canvas.drawRect(
          Rect.fromLTWH(0, 2, size.width, size.height - 4),
          Paint()
            ..color = color
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1,
        );
      case LegendKind.square:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(size.width / 2 - 6, mid - 6, 12, 12),
            const Radius.circular(2),
          ),
          Paint()..color = color,
        );
    }
  }

  @override
  bool shouldRepaint(_SwatchPainter old) =>
      old.kind != kind || old.color != color;
}

/// The choice of how much history to show.
class RangeSelector extends StatelessWidget {
  const RangeSelector({
    required this.value,
    required this.onChanged,
    super.key,
  });

  final TrendRange value;
  final ValueChanged<TrendRange> onChanged;

  @override
  Widget build(BuildContext context) {
    final text = AppText.of(context);
    final labels = {
      TrendRange.last7: text.resRange7,
      TrendRange.days30: text.resRange30,
      TrendRange.days90: text.resRange90,
      TrendRange.all: text.resRangeAll,
    };

    return Semantics(
      label: text.resRangeLabel,
      container: true,
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          for (final range in TrendRange.values)
            ChoiceChip(
              key: ValueKey('range-${range.name}'),
              label: Text(labels[range]!),
              selected: range == value,
              onSelected: (_) => onChanged(range),
              // A tick on the selected one, so selection is not only a colour.
              showCheckmark: true,
            ),
        ],
      ),
    );
  }
}

/// What the trend statistics say, or why they say nothing yet.
class TrendStatsPanel extends StatelessWidget {
  const TrendStatsPanel({required this.stats, this.unitFormat, super.key});

  final TrendStats stats;

  /// Formats the raw slope in the measurement's own units. Null hides the slope line.
  final String Function(double slope)? unitFormat;

  @override
  Widget build(BuildContext context) {
    final text = AppText.of(context);

    final lines = <Widget>[];
    if (!stats.enough) {
      // The rule: no trend claim below the minimum, only how far along the data is.
      lines.add(
        _StatLine(
          icon: Icons.hourglass_top,
          text: text.resNotEnoughData(stats.n, kMinSessionsForTrend),
        ),
      );
    } else {
      final direction = stats.direction!;
      lines.add(
        _StatLine(
          icon: switch (direction) {
            TrendDirection.improving => Icons.trending_up,
            TrendDirection.stable => Icons.trending_flat,
            TrendDirection.declining => Icons.trending_down,
          },
          text: '${text.resTrendDirection}: ${trendWord(text, direction)}',
          bold: true,
        ),
      );
      if (stats.slopeRaw != null && unitFormat != null) {
        lines.add(
          _StatLine(
            icon: Icons.show_chart,
            text: text.resTrendSlope(unitFormat!(stats.slopeRaw!)),
          ),
        );
      }
    }
    if (stats.ewma != null) {
      lines.add(
        _StatLine(
          icon: Icons.waves,
          text: text.resTrendEwma(stats.ewma!.toStringAsFixed(2)),
        ),
      );
      lines.add(
        _StatLine(
          icon: Icons.timeline,
          text: text.resTrendRunMild(stats.runMild),
        ),
      );
      lines.add(
        _StatLine(
          icon: Icons.flag_outlined,
          text: text.resTrendRunNotable(stats.runNotable),
        ),
      );
    }
    if (stats.n > 0) {
      lines.add(
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            text.resTrendValidOnly,
            style: context.texts.bodySmall?.copyWith(
              color: context.colors.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: lines,
    );
  }
}

class _StatLine extends StatelessWidget {
  const _StatLine({required this.icon, required this.text, this.bold = false});

  final IconData icon;
  final String text;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: context.colors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: context.texts.bodyMedium?.copyWith(
                fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// -- the chart of one measurement --------------------------------------------------------

/// One measurement over time, with its baseline, its usual spread, its smoothed curve, the
/// population range if there is a validated one, and a hollow marker for every test that was
/// set aside.
class MetricChart extends StatelessWidget {
  const MetricChart({
    required this.series,
    required this.range,
    required this.now,
    super.key,
  });

  final MetricSeries series;
  final TrendRange range;

  /// The moment the day ranges are measured back from.
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final text = AppText.of(context);
    final spec = series.spec;
    final colors = context.colors;
    final color = context.domainColor(spec.domain.key);

    final visible = applyRange(series.points, range, at: (p) => p.at, now: now);
    final counted = [
      for (final p in visible)
        if (p.counted) p,
    ];
    final validated = series.reference != null && series.reference!.isValidated
        ? series.reference
        : null;

    if (visible.isEmpty) {
      return SizedBox(
        height: kChartHeight,
        child: Center(
          child: Text(
            text.resNoChartInRange,
            style: context.texts.bodyMedium?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    // Smoothed curve for the visible counted tests, in the measurement's own units. It is the
    // engine's smoothing run over the whole history, then cut to the range, so a short range
    // does not restart it from zero.
    final smoothedAll = {
      for (final point in series.smoothed) point.at: point.value,
    };

    final values = [for (final p in visible) p.value];
    final lows = <double>[...values];
    final highs = <double>[...values];
    if (series.hasBaseline) {
      lows.add(series.baselineMedian! - series.baselineScale!);
      highs.add(series.baselineMedian! + series.baselineScale!);
    }
    if (validated != null) {
      lows.add(validated.low!);
      highs.add(validated.high!);
    }
    var minY = lows.reduce(math.min);
    var maxY = highs.reduce(math.max);
    final pad = math.max((maxY - minY) * 0.15, 1e-6);
    minY -= pad;
    maxY += pad;

    FlSpot spot(int i) => FlSpot(i.toDouble(), visible[i].value);

    final countedSpots = [
      for (var i = 0; i < visible.length; i++)
        if (visible[i].counted) spot(i),
    ];
    final excludedSpots = [
      for (var i = 0; i < visible.length; i++)
        if (!visible[i].counted) spot(i),
    ];
    final smoothedSpots = [
      for (var i = 0; i < visible.length; i++)
        if (visible[i].counted && smoothedAll[visible[i].at] != null)
          FlSpot(i.toDouble(), smoothedAll[visible[i].at]!),
    ];

    final stats = computeTrendStats(
      oriented: [
        for (final p in counted)
          if (series.oriented(p.value) != null) series.oriented(p.value)!,
      ],
    );
    final description = stats.enough
        ? text.resChartSemantics(
            featureLabel(text, spec.key),
            trendWord(text, stats.direction!),
            counted.length,
          )
        : text.resChartSemanticsNone(
            featureLabel(text, spec.key),
            stats.n,
            kMinSessionsForTrend,
          );

    return Semantics(
      label: description,
      image: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExcludeSemantics(
            child: SizedBox(
              height: kChartHeight,
              child: LineChart(
                LineChartData(
                  minX: 0,
                  maxX: math.max(visible.length - 1, 1).toDouble(),
                  minY: minY,
                  maxY: maxY,
                  gridData: FlGridData(
                    drawVerticalLine: false,
                    getDrawingHorizontalLine: (_) =>
                        FlLine(color: colors.outlineVariant, strokeWidth: 0.6),
                  ),
                  borderData: FlBorderData(show: false),
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(),
                    rightTitles: const AxisTitles(),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 52,
                        getTitlesWidget: (value, meta) {
                          if (value == meta.min || value == meta.max) {
                            return const SizedBox.shrink();
                          }
                          return Text(
                            formatFeatureValue(spec.key, value),
                            style: context.texts.labelSmall?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                          );
                        },
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 26,
                        interval: math
                            .max(1, (visible.length / 5).ceil())
                            .toDouble(),
                        getTitlesWidget: (value, meta) => Text(
                          '${value.toInt() + 1}',
                          style: context.texts.labelSmall?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                  ),
                  rangeAnnotations: RangeAnnotations(
                    horizontalRangeAnnotations: [
                      if (series.hasBaseline)
                        HorizontalRangeAnnotation(
                          y1: series.baselineMedian! - series.baselineScale!,
                          y2: series.baselineMedian! + series.baselineScale!,
                          color: color.withValues(alpha: 0.14),
                        ),
                      if (validated != null)
                        HorizontalRangeAnnotation(
                          y1: validated.low!,
                          y2: validated.high!,
                          color: colors.tertiary.withValues(alpha: 0.12),
                        ),
                    ],
                  ),
                  extraLinesData: ExtraLinesData(
                    horizontalLines: [
                      if (series.hasBaseline)
                        HorizontalLine(
                          y: series.baselineMedian!,
                          color: color,
                          strokeWidth: 1.6,
                          dashArray: const [2, 5],
                        ),
                      if (validated != null) ...[
                        HorizontalLine(
                          y: validated.low!,
                          color: colors.tertiary,
                          strokeWidth: 1,
                        ),
                        HorizontalLine(
                          y: validated.high!,
                          color: colors.tertiary,
                          strokeWidth: 1,
                        ),
                      ],
                    ],
                  ),
                  lineTouchData: LineTouchData(
                    touchTooltipData: LineTouchTooltipData(
                      getTooltipItems: (touched) => [
                        for (final t in touched)
                          if (t.spotIndex >= 0)
                            LineTooltipItem(
                              _tooltip(text, visible, t.x.round()),
                              TextStyle(
                                color: colors.onInverseSurface,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                      ],
                    ),
                  ),
                  lineBarsData: [
                    // The smoothed curve, dashed.
                    if (smoothedSpots.length >= 2)
                      LineChartBarData(
                        spots: smoothedSpots,
                        color: colors.onSurface,
                        dashArray: const [7, 4],
                        dotData: const FlDotData(show: false),
                      ),
                    // Counted tests: a line through filled circles.
                    LineChartBarData(
                      spots: countedSpots,
                      color: color,
                      barWidth: 2.5,
                      dotData: FlDotData(
                        getDotPainter: (spot, percent, bar, index) =>
                            FlDotCirclePainter(
                              radius: 4,
                              color: color,
                              strokeWidth: 1.5,
                              strokeColor: colors.surface,
                            ),
                      ),
                    ),
                    // Tests set aside: hollow circles, never joined.
                    if (excludedSpots.isNotEmpty)
                      LineChartBarData(
                        spots: excludedSpots,
                        color: Colors.transparent,
                        barWidth: 0,
                        dotData: FlDotData(
                          getDotPainter: (spot, percent, bar, index) =>
                              FlDotCirclePainter(
                                radius: 5,
                                color: Colors.transparent,
                                strokeWidth: 2.2,
                                strokeColor: color,
                              ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          ChartLegend(
            items: [
              LegendItem(
                label: text.resLegendCounted,
                color: color,
                kind: LegendKind.filledDot,
              ),
              if (excludedSpots.isNotEmpty)
                LegendItem(
                  label: text.resLegendExcluded,
                  color: color,
                  kind: LegendKind.hollowDot,
                ),
              if (series.hasBaseline) ...[
                LegendItem(
                  label: text.resLegendBaseline,
                  color: color,
                  kind: LegendKind.dotted,
                ),
                LegendItem(
                  label: text.resLegendBand,
                  color: color,
                  kind: LegendKind.band,
                ),
              ],
              if (smoothedSpots.length >= 2)
                LegendItem(
                  label: text.resLegendSmoothed,
                  color: colors.onSurface,
                  kind: LegendKind.dashed,
                ),
              if (validated != null)
                LegendItem(
                  label: text.resLegendPopulation,
                  color: colors.tertiary,
                  kind: LegendKind.band,
                ),
            ],
          ),
        ],
      ),
    );
  }

  String _tooltip(AppText text, List<MetricPoint> visible, int index) {
    if (index < 0 || index >= visible.length) return '';
    final point = visible[index];
    final date = '${point.at.day}/${point.at.month}';
    final value = formatFeatureValue(series.spec.key, point.value);
    return point.counted
        ? '$date\n$value'
        : '$date\n$value\n${text.resNotCounted}';
  }
}

// -- the overall index -------------------------------------------------------------------

/// The overall deviation index and its smoothed value, with the mild and notable levels.
class IndexChart extends StatelessWidget {
  const IndexChart({
    required this.points,
    required this.range,
    required this.now,
    super.key,
  });

  final List<IndexPoint> points;
  final TrendRange range;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final text = AppText.of(context);
    final colors = context.colors;
    final visible = applyRange(points, range, at: (p) => p.at, now: now);

    if (visible.isEmpty) {
      return SizedBox(
        height: kChartHeight,
        child: Center(
          child: Text(
            text.resNoChartInRange,
            style: context.texts.bodyMedium?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    const notable = kDefaultThreshold;
    const mild = kDefaultThreshold * kMildFraction;
    final maxY =
        [
          notable * 1.4,
          ...visible.map((p) => p.index),
          ...visible.map((p) => p.ewma),
        ].reduce(math.max) *
        1.1;

    final stats = computeTrendStats(
      oriented: [for (final p in visible) p.index],
    );
    final description = stats.enough
        ? text.resChartSemantics(
            text.resChartOverall,
            trendWord(text, stats.direction!),
            visible.length,
          )
        : text.resChartSemanticsNone(
            text.resChartOverall,
            stats.n,
            kMinSessionsForTrend,
          );

    return Semantics(
      label: description,
      image: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExcludeSemantics(
            child: SizedBox(
              height: kChartHeight,
              child: LineChart(
                LineChartData(
                  minX: 0,
                  maxX: math.max(visible.length - 1, 1).toDouble(),
                  minY: 0,
                  maxY: maxY,
                  gridData: FlGridData(
                    drawVerticalLine: false,
                    getDrawingHorizontalLine: (_) =>
                        FlLine(color: colors.outlineVariant, strokeWidth: 0.6),
                  ),
                  borderData: FlBorderData(show: false),
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(),
                    rightTitles: const AxisTitles(),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 36,
                        getTitlesWidget: (value, meta) => Text(
                          value.toStringAsFixed(1),
                          style: context.texts.labelSmall?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 26,
                        interval: math
                            .max(1, (visible.length / 5).ceil())
                            .toDouble(),
                        getTitlesWidget: (value, meta) => Text(
                          '${value.toInt() + 1}',
                          style: context.texts.labelSmall?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                  ),
                  extraLinesData: ExtraLinesData(
                    horizontalLines: [
                      HorizontalLine(
                        y: notable,
                        color: kWorseColor,
                        strokeWidth: 1.6,
                        dashArray: const [7, 4],
                      ),
                      HorizontalLine(
                        y: mild,
                        color: colors.outline,
                        strokeWidth: 1.4,
                        dashArray: const [2, 5],
                      ),
                    ],
                  ),
                  lineBarsData: [
                    LineChartBarData(
                      spots: [
                        for (var i = 0; i < visible.length; i++)
                          FlSpot(i.toDouble(), visible[i].index),
                      ],
                      color: colors.outline,
                      barWidth: 0,
                      dotData: FlDotData(
                        getDotPainter: (s, p, b, i) => FlDotCirclePainter(
                          radius: 3.5,
                          color: Colors.transparent,
                          strokeWidth: 1.8,
                          strokeColor: colors.onSurfaceVariant,
                        ),
                      ),
                    ),
                    LineChartBarData(
                      spots: [
                        for (var i = 0; i < visible.length; i++)
                          FlSpot(i.toDouble(), visible[i].ewma),
                      ],
                      color: colors.primary,
                      barWidth: 2.8,
                      dotData: FlDotData(
                        getDotPainter: (s, p, b, i) => FlDotCirclePainter(
                          radius: 4,
                          color: colors.primary,
                          strokeWidth: 1.5,
                          strokeColor: colors.surface,
                        ),
                      ),
                      belowBarData: BarAreaData(
                        color: colors.primary.withValues(alpha: 0.08),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          ChartLegend(
            items: [
              LegendItem(
                label: text.resLegendSmoothed,
                color: colors.primary,
                kind: LegendKind.filledDot,
              ),
              LegendItem(
                label: text.resLegendIndex,
                color: colors.onSurfaceVariant,
                kind: LegendKind.hollowDot,
              ),
              LegendItem(
                label: text.resLegendMild,
                color: colors.outline,
                kind: LegendKind.dotted,
              ),
              LegendItem(
                label: text.resLegendNotable,
                color: kWorseColor,
                kind: LegendKind.dashed,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// -- what the index is made of -----------------------------------------------------------

/// One stacked bar per test, each adding up to 100% of the index.
class ShareBars extends StatelessWidget {
  const ShareBars({
    required this.points,
    required this.range,
    required this.now,
    super.key,
  });

  final List<IndexPoint> points;
  final TrendRange range;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final text = AppText.of(context);
    final colors = context.colors;
    final visible = applyRange(points, range, at: (p) => p.at, now: now);

    if (visible.isEmpty) {
      return SizedBox(
        height: 120,
        child: Center(
          child: Text(
            text.resNoChartInRange,
            style: context.texts.bodyMedium?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    BarChartGroupData group(int i) {
      final shares = visible[i].contributions;
      var start = 0.0;
      final stack = <BarChartRodStackItem>[];
      for (final domain in Domain.values) {
        final share = shares[domain] ?? 0.0;
        if (share <= 0) continue;
        stack.add(
          BarChartRodStackItem(
            start,
            start + share,
            context.domainColor(domain.key),
            // A thin surface-coloured edge between segments, so neighbouring areas are
            // separated by a line as well as by colour.
            borderSide: BorderSide(color: colors.surface, width: 1.5),
          ),
        );
        start += share;
      }
      return BarChartGroupData(
        x: i,
        barRods: [
          BarChartRodData(
            toY: math.max(start, 1e-9),
            width: math.max(6, math.min(22, 240 / visible.length)),
            borderRadius: BorderRadius.circular(3),
            rodStackItems: stack,
          ),
        ],
      );
    }

    return Semantics(
      label: '${text.resChartShares}. ${text.resChartSharesNote}',
      image: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExcludeSemantics(
            child: SizedBox(
              height: 180,
              child: BarChart(
                BarChartData(
                  maxY: 1.0,
                  minY: 0,
                  alignment: BarChartAlignment.spaceAround,
                  gridData: FlGridData(
                    drawVerticalLine: false,
                    horizontalInterval: 0.25,
                    getDrawingHorizontalLine: (_) =>
                        FlLine(color: colors.outlineVariant, strokeWidth: 0.6),
                  ),
                  borderData: FlBorderData(show: false),
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(),
                    rightTitles: const AxisTitles(),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 40,
                        interval: 0.25,
                        getTitlesWidget: (value, meta) => Text(
                          '${(value * 100).round()}%',
                          style: context.texts.labelSmall?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 24,
                        interval: math
                            .max(1, (visible.length / 6).ceil())
                            .toDouble(),
                        getTitlesWidget: (value, meta) => Text(
                          '${value.toInt() + 1}',
                          style: context.texts.labelSmall?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                  ),
                  barGroups: [
                    for (var i = 0; i < visible.length; i++) group(i),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          ChartLegend(
            items: [
              for (final domain in Domain.values)
                LegendItem(
                  label: _domainName(text, domain),
                  color: context.domainColor(domain.key),
                  kind: LegendKind.square,
                ),
            ],
          ),
        ],
      ),
    );
  }

  String _domainName(AppText text, Domain domain) => switch (domain) {
    Domain.cognitive => text.domainCognitive,
    Domain.speech => text.domainSpeech,
    Domain.motor => text.domainMotor,
    Domain.interaction => text.domainInteraction,
  };
}

// -- an area over time -------------------------------------------------------------------

/// One area's score over time, with the zero line: above it is worse, below it better.
class AreaChart extends StatelessWidget {
  const AreaChart({
    required this.domain,
    required this.points,
    required this.range,
    required this.now,
    super.key,
  });

  final Domain domain;
  final List<DomainPoint> points;
  final TrendRange range;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final text = AppText.of(context);
    final colors = context.colors;
    final color = context.domainColor(domain.key);
    final visible = applyRange(points, range, at: (p) => p.at, now: now);

    if (visible.isEmpty) {
      return SizedBox(
        height: 110,
        child: Center(
          child: Text(
            text.resNoChartInRange,
            style: context.texts.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    final scores = [for (final p in visible) p.score];
    final low = math.min(scores.reduce(math.min), -0.5);
    final high = math.max(scores.reduce(math.max), kDefaultThreshold * 1.2);
    final stats = computeTrendStats(oriented: scores);
    final name = _name(text);
    final description = stats.enough
        ? text.resChartSemantics(
            name,
            trendWord(text, stats.direction!),
            visible.length,
          )
        : text.resChartSemanticsNone(name, stats.n, kMinSessionsForTrend);

    return Semantics(
      label: description,
      image: true,
      child: ExcludeSemantics(
        child: SizedBox(
          height: 140,
          child: LineChart(
            LineChartData(
              minX: 0,
              maxX: math.max(visible.length - 1, 1).toDouble(),
              minY: low,
              maxY: high,
              gridData: const FlGridData(show: false),
              borderData: FlBorderData(show: false),
              titlesData: const FlTitlesData(show: false),
              extraLinesData: ExtraLinesData(
                horizontalLines: [
                  HorizontalLine(
                    y: 0,
                    color: colors.outline,
                    strokeWidth: 1.2,
                    dashArray: const [2, 5],
                  ),
                ],
              ),
              lineBarsData: [
                LineChartBarData(
                  spots: [
                    for (var i = 0; i < visible.length; i++)
                      FlSpot(i.toDouble(), visible[i].score),
                  ],
                  color: color,
                  barWidth: 2.6,
                  dotData: FlDotData(
                    show: visible.length <= 30,
                    getDotPainter: (s, p, b, i) => FlDotCirclePainter(
                      radius: 3.5,
                      color: color,
                      strokeWidth: 1.4,
                      strokeColor: colors.surface,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _name(AppText text) => switch (domain) {
    Domain.cognitive => text.domainCognitive,
    Domain.speech => text.domainSpeech,
    Domain.motor => text.domainMotor,
    Domain.interaction => text.domainInteraction,
  };
}
