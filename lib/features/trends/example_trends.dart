/// Simulated trends, shown once the baseline is set.
///
/// After the baseline the user has nothing of their own to look at yet, and a screen of
/// unfamiliar numbers is hard to trust. So this shows their own baseline, two invented runs of
/// tests scored against it by the real engine, and a plain walk through how the numbers are
/// worked out. Everything on it is labelled as an example, because a chart of made-up data
/// that could be mistaken for the user's own would be worse than no chart.
library;

import 'package:fl_chart/fl_chart.dart';
// Flutter has its own Baseline widget, which would clash with the engine's.
import 'package:flutter/material.dart' hide Baseline;

import '../../app/l10n/generated/app_localizations.dart';
import '../../app/theme.dart';
import '../../app/widgets.dart';
import '../../engine/baseline.dart';
import '../../engine/features.dart';
import '../../engine/simulation.dart';
import 'baseline_format.dart';

/// The baseline card, the two example charts, and the explanation.
class ExampleTrendsSection extends StatelessWidget {
  const ExampleTrendsSection({required this.baseline, super.key});

  final Baseline baseline;

  @override
  Widget build(BuildContext context) {
    final text = AppText.of(context);

    final steady = simulateTrend(
      baseline: baseline,
      scenario: SimulationScenario.steady,
    );
    final change = simulateTrend(
      baseline: baseline,
      scenario: SimulationScenario.gradualChange,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        YourBaselineCard(baseline: baseline),
        const SizedBox(height: 22),

        Row(
          children: [
            Flexible(
              child: Text(
                text.exampleTitle,
                style: context.texts.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        const ExampleBadge(),
        const SizedBox(height: 10),
        Text(
          text.exampleIntro,
          style: context.texts.bodyMedium?.copyWith(
            color: context.colors.onSurfaceVariant,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 14),

        _ExampleChartCard(
          title: text.exampleSteadyTitle,
          caption: text.exampleSteadyBody,
          trend: steady,
        ),
        const SizedBox(height: 14),
        _ExampleChartCard(
          title: text.exampleChangeTitle,
          caption: change.notableAt == null
              ? text.exampleChangeNever
              : text.exampleChangeBody(
                  kSimulatedPersistence,
                  change.notableAt!,
                ),
          trend: change,
        ),
        const SizedBox(height: 14),
        const _Legend(),
        const SizedBox(height: 22),

        const HowItWorksCard(),
      ],
    );
  }
}

/// "Example, not your data" -- on everything simulated.
class ExampleBadge extends StatelessWidget {
  const ExampleBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final text = AppText.of(context);
    final colors = context.colors;

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: colors.tertiaryContainer,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.science_outlined,
              size: 16,
              color: colors.onTertiaryContainer,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                text.exampleBadge,
                style: context.texts.labelLarge?.copyWith(
                  color: colors.onTertiaryContainer,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// What is normal for this user, per measurement.
///
/// Real data, unlike the charts below it: these are the numbers the baseline actually froze.
class YourBaselineCard extends StatelessWidget {
  const YourBaselineCard({required this.baseline, super.key});

  final Baseline baseline;

  @override
  Widget build(BuildContext context) {
    final text = AppText.of(context);

    return SectionCard(
      title: text.baselineCardTitle,
      subtitle: text.baselineCardBody,
      leading: Icon(Icons.anchor, color: context.colors.primary),
      child: Column(
        children: [
          for (final spec in kFeatureSpecs)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 5),
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: context.domainColor(spec.domain.key),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          featureLabel(text, spec.key),
                          style: context.texts.bodyMedium,
                        ),
                        Text(
                          text.baselineRowSpread(
                            formatFeatureSpread(
                              spec.key,
                              baseline.scale[spec.key]!,
                            ),
                          ),
                          style: context.texts.bodySmall?.copyWith(
                            color: context.colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    formatFeatureValue(spec.key, baseline.median[spec.key]!),
                    style: context.texts.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ExampleChartCard extends StatelessWidget {
  const _ExampleChartCard({
    required this.title,
    required this.caption,
    required this.trend,
  });

  final String title;
  final String caption;
  final SimulatedTrend trend;

  @override
  Widget build(BuildContext context) {
    final text = AppText.of(context);

    return SectionCard(
      title: title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const ExampleBadge(),
          const SizedBox(height: 14),
          Semantics(
            label: '${text.exampleBadge}: $title',
            child: SizedBox(
              height: 200,
              child: SimulatedTrendChart(trend: trend),
            ),
          ),
          const SizedBox(height: 12),
          Text(caption, style: context.texts.bodyMedium?.copyWith(height: 1.5)),
        ],
      ),
    );
  }
}

/// A simulated run: the smoothed score, the baseline, and the line a change has to stay above.
class SimulatedTrendChart extends StatelessWidget {
  const SimulatedTrendChart({required this.trend, super.key});

  final SimulatedTrend trend;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final notableAt = trend.notableAt;
    final highest = trend.points
        .map((point) => point.ewma)
        .fold<double>(kSimulatedThreshold * 1.4, (a, b) => a > b ? a : b);

    return LineChart(
      LineChartData(
        minY: 0,
        maxY: highest * 1.1,
        minX: 1,
        maxX: trend.points.length.toDouble(),
        gridData: FlGridData(
          drawVerticalLine: false,
          getDrawingHorizontalLine: (value) =>
              FlLine(color: colors.outlineVariant),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 34,
              getTitlesWidget: (value, meta) => Text(
                value.toStringAsFixed(1),
                style: context.texts.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            axisNameSize: 22,
            axisNameWidget: Text(
              AppText.of(context).exampleAxis,
              style: context.texts.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 24,
              interval: 4,
              getTitlesWidget: (value, meta) => Text(
                '${value.toInt()}',
                style: context.texts.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ),
        extraLinesData: ExtraLinesData(
          horizontalLines: [
            // The line a change has to stay above.
            HorizontalLine(
              y: kSimulatedThreshold,
              color: colors.error.withValues(alpha: 0.75),
              strokeWidth: 1.5,
              dashArray: [6, 4],
            ),
            // The baseline itself. Scores are measured from here.
            HorizontalLine(y: 0, color: colors.outline, strokeWidth: 1.5),
          ],
        ),
        lineBarsData: [
          LineChartBarData(
            barWidth: 2.5,
            color: colors.primary,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              color: colors.primary.withValues(alpha: 0.10),
            ),
            spots: [
              for (final point in trend.points)
                FlSpot(point.test.toDouble(), point.ewma),
            ],
          ),
          // The moment a notable change would have been reported.
          if (notableAt != null)
            LineChartBarData(
              barWidth: 0,
              color: colors.error,
              dotData: FlDotData(
                getDotPainter: (spot, percent, bar, index) =>
                    FlDotCirclePainter(
                      radius: 6,
                      color: colors.error,
                      strokeWidth: 2,
                      strokeColor: colors.surface,
                    ),
              ),
              spots: [
                FlSpot(notableAt.toDouble(), trend.points[notableAt - 1].ewma),
              ],
            ),
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    final text = AppText.of(context);
    final colors = context.colors;

    Widget row(Color color, String label, {bool dashed = false}) => Row(
      children: [
        SizedBox(
          width: 24,
          height: 3,
          child: dashed
              ? Row(
                  children: [
                    for (var i = 0; i < 3; i++) ...[
                      Expanded(child: ColoredBox(color: color)),
                      if (i < 2) const SizedBox(width: 3),
                    ],
                  ],
                )
              : ColoredBox(color: color),
        ),
        const SizedBox(width: 10),
        Flexible(child: Text(label, style: context.texts.bodySmall)),
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        row(colors.primary, text.exampleLegendScore),
        const SizedBox(height: 8),
        row(colors.error, text.exampleLegendThreshold, dashed: true),
        const SizedBox(height: 8),
        row(colors.outline, text.exampleLegendBaseline),
      ],
    );
  }
}

/// Five plain-language steps from a measurement to a reported change.
class HowItWorksCard extends StatelessWidget {
  const HowItWorksCard({super.key});

  @override
  Widget build(BuildContext context) {
    final text = AppText.of(context);
    final steps = [
      text.howStep1,
      text.howStep2,
      text.howStep3,
      text.howStep4,
      text.howStep5(kSimulatedPersistence),
    ];

    return SectionCard(
      title: text.howTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < steps.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: context.colors.primaryContainer,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '${i + 1}',
                      style: context.texts.labelLarge?.copyWith(
                        color: context.colors.onPrimaryContainer,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      steps[i],
                      style: context.texts.bodyMedium?.copyWith(height: 1.5),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
