/// The trend charts.
///
/// Three views once there is a full test: how the latest one compares with the baseline and
/// the test before it, the smoothed overall deviation, and the three areas separately. The
/// overall chart is what the status is based on; the per-area charts are where an improvement
/// is visible, since the overall index is one-sided and cannot go below zero.
///
/// Before the first full test there is nothing of the user's own to chart, so the screen shows
/// a prompt to take one, and an example built from their real baseline.
///
/// Only scored sessions are plotted. A session the check-in set aside was deliberately
/// excluded from the trend, and drawing it as a point on the line would show the user a
/// change the engine decided to ignore.
library;

import 'package:fl_chart/fl_chart.dart';
// Flutter has its own Baseline widget, which would clash with the engine's.
import 'package:flutter/material.dart' hide Baseline;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/l10n/generated/app_localizations.dart';
import '../../app/providers.dart';
import '../../app/router.dart';
import '../../app/theme.dart';
import '../../app/widgets.dart';
import '../../engine/baseline.dart';
import '../../engine/comparison.dart';
import '../../engine/constants.dart';
import '../../engine/features.dart';
import 'comparison_section.dart';
import 'example_trends.dart';

/// Overall and per-domain history.
class TrendsScreen extends ConsumerStatefulWidget {
  const TrendsScreen({super.key});

  @override
  ConsumerState<TrendsScreen> createState() => _TrendsScreenState();
}

class _TrendsScreenState extends ConsumerState<TrendsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this);

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = AppText.of(context);
    final deviation = ref.watch(deviationSeriesProvider);
    final domains = ref.watch(domainSeriesProvider);
    final verdictReady = ref.watch(verdictReadyProvider);
    final baseline = ref.watch(engineProvider).value?.baseline;
    final baselineReady = baseline != null;

    // Charts and the comparison start with the first full test. Before it the user is
    // invited to take one, and shown an example so the screen is not empty.
    if (!verdictReady) {
      return Scaffold(
        appBar: AppBar(title: Text(text.trendsTitle)),
        body: baselineReady
            ? ListView(
                padding: const EdgeInsets.all(kPagePadding),
                children: [
                  SectionCard(
                    title: text.trendsFirstTestTitle,
                    leading: Icon(
                      Icons.play_circle_outline,
                      color: context.colors.primary,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          text.trendsFirstTestBody,
                          style: context.texts.bodyMedium?.copyWith(
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 16),
                        PrimaryButton(
                          label: text.dashboardStartFullTest,
                          icon: Icons.play_arrow_rounded,
                          onPressed: () => context.push(Routes.session),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 22),
                  // Simulated, and labelled so. The user has no results of their own yet, so
                  // this shows their real baseline and how the measurements behave against it.
                  ExampleTrendsSection(baseline: baseline),
                  const SizedBox(height: 20),
                ],
              )
            : EmptyState(icon: Icons.show_chart, message: text.trendsNoData),
      );
    }

    final comparison = ref.watch(comparisonProvider(null));

    return Scaffold(
      appBar: AppBar(
        title: Text(text.trendsTitle),
        bottom: TabBar(
          controller: _tabs,
          tabs: [
            Tab(text: text.trendsCompare),
            Tab(text: text.trendsOverall),
            Tab(text: text.trendsByDomain),
          ],
        ),
      ),
      body: deviation.isEmpty
          ? EmptyState(icon: Icons.show_chart, message: text.trendsNoData)
          : TabBarView(
              controller: _tabs,
              children: [
                _CompareTab(comparison: comparison, baseline: baseline),
                _OverallTab(series: deviation),
                _DomainsTab(series: domains),
              ],
            ),
    );
  }
}

/// The latest test against the baseline and the test before it, and the worked example.
class _CompareTab extends StatelessWidget {
  const _CompareTab({required this.comparison, required this.baseline});

  final TestComparison? comparison;
  final Baseline? baseline;

  @override
  Widget build(BuildContext context) {
    final text = AppText.of(context);

    return ListView(
      padding: const EdgeInsets.all(kPagePadding),
      children: [
        if (comparison != null) ...[
          ComparisonSection(comparison: comparison!),
          const SizedBox(height: 14),
        ],
        if (baseline != null)
          SectionCard(
            child: Theme(
              // The expansion tile draws its own dividers, which sit oddly inside a card.
              data: Theme.of(context)
                  .copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.only(top: 8),
                title: Text(
                  text.trendsExampleToggle,
                  style: context.texts.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                children: [ExampleTrendsSection(baseline: baseline!)],
              ),
            ),
          ),
        const SizedBox(height: 14),
        const NotADiagnosisNote(),
        const SizedBox(height: 20),
      ],
    );
  }
}

class _OverallTab extends StatelessWidget {
  const _OverallTab({required this.series});

  final List<({DateTime at, double ewma})> series;

  @override
  Widget build(BuildContext context) {
    final text = AppText.of(context);

    return ListView(
      padding: const EdgeInsets.all(kPagePadding),
      children: [
        SectionCard(
          title: text.trendsOverall,
          subtitle: text.trendsHigherIsWorse,
          child: SizedBox(height: 240, child: _DeviationChart(series: series)),
        ),
        const SizedBox(height: 14),
        SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _LegendRow(
                color: context.colors.primary,
                label: text.trendsOverall,
              ),
              const SizedBox(height: 10),
              _LegendRow(
                color: context.colors.error,
                label: text.statusNotable,
                dashed: true,
              ),
              const SizedBox(height: 14),
              Text(
                text.trendsBaselineNote,
                style: context.texts.bodySmall?.copyWith(
                  color: context.colors.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                text.trendsExcludedNote,
                style: context.texts.bodySmall?.copyWith(
                  color: context.colors.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        const NotADiagnosisNote(),
        const SizedBox(height: 20),
      ],
    );
  }
}

/// The smoothed deviation, with the alert threshold marked.
class _DeviationChart extends StatelessWidget {
  const _DeviationChart({required this.series});

  final List<({DateTime at, double ewma})> series;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final maximum = series
        .map((point) => point.ewma)
        .fold<double>(kDefaultThreshold * 1.3, (a, b) => a > b ? a : b);

    return LineChart(
      LineChartData(
        minY: 0,
        maxY: maximum * 1.12,
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
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              // Session number, not a date. The sessions are unevenly spaced in time and
              // a date axis would compress a busy week against a quiet one, hiding how
              // many measurements the trend actually rests on.
              interval: (series.length / 5).clamp(1, 100).toDouble(),
              getTitlesWidget: (value, meta) => Text(
                '${value.toInt() + 1}',
                style: context.texts.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ),
        // The threshold, so a reader can see how far from it the line is rather than only
        // whether the app said something.
        extraLinesData: ExtraLinesData(
          horizontalLines: [
            HorizontalLine(
              y: kDefaultThreshold,
              color: colors.error.withValues(alpha: 0.7),
              strokeWidth: 1.5,
              dashArray: [6, 4],
            ),
            HorizontalLine(
              y: kDefaultThreshold * kMildFraction,
              color: colors.outline,
              strokeWidth: 1,
              dashArray: [3, 5],
            ),
          ],
        ),
        lineBarsData: [
          LineChartBarData(
            barWidth: 2.5,
            color: colors.primary,
            dotData: FlDotData(
              show: series.length <= 40,
              getDotPainter: (spot, percent, bar, index) =>
                  FlDotCirclePainter(radius: 3, color: colors.primary),
            ),
            belowBarData: BarAreaData(
              color: colors.primary.withValues(alpha: 0.10),
            ),
            spots: [
              for (var i = 0; i < series.length; i++)
                FlSpot(i.toDouble(), series[i].ewma),
            ],
          ),
        ],
      ),
    );
  }
}

class _DomainsTab extends StatelessWidget {
  const _DomainsTab({required this.series});

  final Map<Domain, List<({DateTime at, double score})>> series;

  @override
  Widget build(BuildContext context) {
    final text = AppText.of(context);

    return ListView(
      padding: const EdgeInsets.all(kPagePadding),
      children: [
        for (final domain in Domain.values) ...[
          SectionCard(
            title: domainLabel(text, domain),
            leading: Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: context.domainColor(domain.key),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            child: SizedBox(
              height: 150,
              child: _DomainChart(
                points: series[domain] ?? const [],
                color: context.domainColor(domain.key),
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
        const SizedBox(height: 4),
        Text(
          text.trendsHigherIsWorse,
          style: context.texts.bodySmall?.copyWith(
            color: context.colors.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }
}

/// One domain's z-score history.
///
/// Unlike the overall chart this one can go negative, and the zero line is drawn because
/// below it means the user is doing better than their baseline -- which the overall index
/// cannot show.
class _DomainChart extends StatelessWidget {
  const _DomainChart({required this.points, required this.color});

  final List<({DateTime at, double score})> points;
  final Color color;

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) {
      return Center(
        child: Text(
          AppText.of(context).trendsNoData,
          style: context.texts.bodySmall?.copyWith(
            color: context.colors.onSurfaceVariant,
          ),
        ),
      );
    }

    final scores = points.map((point) => point.score).toList();
    final lowest = scores.reduce((a, b) => a < b ? a : b);
    final highest = scores.reduce((a, b) => a > b ? a : b);
    final span = (highest - lowest).abs().clamp(1.0, 100.0);

    return LineChart(
      LineChartData(
        minY: lowest - span * 0.2,
        maxY: highest + span * 0.2,
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        titlesData: const FlTitlesData(show: false),
        extraLinesData: ExtraLinesData(
          horizontalLines: [
            HorizontalLine(
              y: 0,
              color: context.colors.outline,
              dashArray: [4, 4],
            ),
          ],
        ),
        lineBarsData: [
          LineChartBarData(
            barWidth: 2.5,
            color: color,
            dotData: FlDotData(show: points.length <= 30),
            spots: [
              for (var i = 0; i < points.length; i++)
                FlSpot(i.toDouble(), points[i].score),
            ],
          ),
        ],
      ),
    );
  }
}

class _LegendRow extends StatelessWidget {
  const _LegendRow({
    required this.color,
    required this.label,
    this.dashed = false,
  });

  final Color color;
  final String label;
  final bool dashed;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 22,
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
        Text(label, style: context.texts.bodySmall),
      ],
    );
  }
}
