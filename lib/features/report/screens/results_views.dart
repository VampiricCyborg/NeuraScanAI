/// The three views of the results: the latest test, the trends, and the log.
///
/// Each is a plain list that the Trends screen puts in a tab and the summary screen reuses, so
/// what the user sees straight after a test and what they see later are the same thing.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/l10n/generated/app_localizations.dart';
import '../../../app/providers.dart';
import '../../../app/router.dart';
import '../../../app/theme.dart';
import '../../../app/widgets.dart';
import '../../../engine/features.dart';
import '../../trends/baseline_format.dart';
import '../calculators/analysis.dart';
import '../calculators/trend_stats.dart';
import '../models.dart';
import '../providers.dart';
import '../widgets/charts.dart';
import '../widgets/report_text.dart';
import '../widgets/status_card.dart';
import '../widgets/test_card.dart';
import '../widgets/verdict.dart';

/// The status of a full test and its eight test cards.
class LatestTestView extends ConsumerWidget {
  const LatestTestView({this.sessionId, this.shrinkWrap = false, super.key});

  /// Which test. The latest full test if null.
  final String? sessionId;

  /// True when embedded in another scrolling list, so it sizes itself.
  final bool shrinkWrap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = AppText.of(context);
    final latest = sessionId == null
        ? ref.watch(latestFullTestProvider)
        : (ref.watch(sessionsProvider).value ?? const [])
              .where((s) => s.id == sessionId)
              .firstOrNull;

    if (latest == null) {
      return EmptyState(
        icon: Icons.fact_check_outlined,
        message: text.trendsNoData,
      );
    }

    final summaries = ref.watch(testSummariesProvider(latest.id));
    final top = ref.watch(topContributorsProvider(latest.id));
    final baseline = ref.watch(engineProvider).value?.baseline;
    final scored = ref.watch(scoredSessionCountProvider);
    final first = latest.isCounted && scored == 1;

    final children = <Widget>[
      SessionStatusCard(
        session: latest,
        topFeatures: top,
        calibratingCount: baseline?.pendingKeys.length ?? 0,
        early: first,
      ),
      const SizedBox(height: 14),
      for (final summary in summaries) ...[
        TestCard(
          summary: summary,
          onOpenMetric: (key) => context.push('${Routes.metric}?key=$key'),
        ),
        const SizedBox(height: 10),
      ],
      const SizedBox(height: 4),
      const NotADiagnosisNote(),
    ];

    if (shrinkWrap) return Column(children: children);
    return ListView(
      padding: const EdgeInsets.all(kPagePadding),
      children: children,
    );
  }
}

/// The charts, with a range selector.
class TrendsView extends ConsumerStatefulWidget {
  const TrendsView({this.now, super.key});

  /// Overridable so tests can pin the day ranges.
  final DateTime? now;

  @override
  ConsumerState<TrendsView> createState() => _TrendsViewState();
}

class _TrendsViewState extends ConsumerState<TrendsView> {
  TrendRange _range = TrendRange.all;

  @override
  Widget build(BuildContext context) {
    final text = AppText.of(context);
    final now = widget.now ?? DateTime.now();
    final index = ref.watch(indexSeriesProvider);
    final areas = ref.watch(areaSeriesProvider);

    if (index.isEmpty) {
      return EmptyState(icon: Icons.show_chart, message: text.resNoChartData);
    }

    return ListView(
      padding: const EdgeInsets.all(kPagePadding),
      children: [
        RangeSelector(
          value: _range,
          onChanged: (r) => setState(() => _range = r),
        ),
        const SizedBox(height: 14),
        SectionCard(
          title: text.resChartOverall,
          subtitle: text.resChartOverallNote,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IndexChart(points: index, range: _range, now: now),
              const SizedBox(height: 16),
              TrendStatsPanel(
                stats: computeTrendStats(
                  oriented: [
                    for (final p in applyRange(
                      index,
                      _range,
                      at: (p) => p.at,
                      now: now,
                    ))
                      p.index,
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        SectionCard(
          title: text.resChartShares,
          subtitle: text.resChartSharesNote,
          child: ShareBars(points: index, range: _range, now: now),
        ),
        const SizedBox(height: 14),
        SectionCard(
          title: text.resChartAreas,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final domain in Domain.values) ...[
                Row(
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: context.domainColor(domain.key),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      domainLabel(text, domain),
                      style: context.texts.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                AreaChart(
                  domain: domain,
                  points: areas[domain] ?? const [],
                  range: _range,
                  now: now,
                ),
                TrendStatsPanel(
                  stats: computeTrendStats(
                    oriented: [
                      for (final p in applyRange(
                        areas[domain] ?? const <DomainPoint>[],
                        _range,
                        at: (p) => p.at,
                        now: now,
                      ))
                        p.score,
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],
              Text(
                text.trendsHigherIsWorse,
                style: context.texts.bodySmall?.copyWith(
                  color: context.colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        SectionCard(
          title: text.resChartMetrics,
          subtitle: text.resChartMetricsNote,
          child: Column(
            children: [
              for (final spec in kFeatureSpecs)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(featureLabel(text, spec.key)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('${Routes.metric}?key=${spec.key}'),
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

/// Every test, counted or not.
class LogView extends ConsumerWidget {
  const LogView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = AppText.of(context);
    final rows = ref.watch(sessionLogProvider);

    if (rows.isEmpty) {
      return EmptyState(
        icon: Icons.history,
        message: text.dashboardNoSessionsYet,
      );
    }

    return ListView(
      padding: const EdgeInsets.all(kPagePadding),
      children: [
        Text(
          text.resLogTitle,
          style: context.texts.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          text.resLogNote,
          style: context.texts.bodySmall?.copyWith(
            color: context.colors.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 14),
        for (final row in rows.reversed) ...[
          LogRowTile(row: row),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

/// One row of the log.
class LogRowTile extends StatelessWidget {
  const LogRowTile({required this.row, super.key});

  final SessionLogRow row;

  @override
  Widget build(BuildContext context) {
    final text = AppText.of(context);
    final session = row.session;
    final kind = switch (row.kind) {
      LogKind.practice => text.resLogPractice,
      LogKind.baseline => text.resLogBaseline,
      LogKind.full => text.resLogFull,
    };
    final date =
        '${session.completedAt.day}/${session.completedAt.month}/${session.completedAt.year}';

    final why = switch (row.kind) {
      LogKind.practice => text.resLogPracticeWhy,
      LogKind.baseline when row.reasons.isEmpty => text.resLogBuilding,
      _ when row.reasons.isNotEmpty => text.resNotCountedWhy(
        row.reasons.map((r) => contextNoteLabel(text, r)).join(', '),
      ),
      _ => null,
    };

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 10,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  '$kind · $date',
                  style: context.texts.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (row.counted)
                  StateChip(
                    icon: Icons.check_circle_outline,
                    label: text.resValid,
                  )
                else
                  StateChip(icon: Icons.block, label: text.resNotCounted),
              ],
            ),
            if (why != null) ...[
              const SizedBox(height: 6),
              Text(why, style: context.texts.bodySmall),
            ],
            if (row.counted && session.index != null) ...[
              const SizedBox(height: 6),
              Text(
                text.resLogIndex(session.index!.toStringAsFixed(2)),
                style: context.texts.bodySmall?.copyWith(
                  color: context.colors.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// One measurement: its chart, its statistics and its three-way comparison.
class MetricDetailScreen extends ConsumerStatefulWidget {
  const MetricDetailScreen({required this.metricKey, super.key});

  final String metricKey;

  @override
  ConsumerState<MetricDetailScreen> createState() => _MetricDetailScreenState();
}

class _MetricDetailScreenState extends ConsumerState<MetricDetailScreen> {
  TrendRange _range = TrendRange.all;

  @override
  Widget build(BuildContext context) {
    final text = AppText.of(context);
    final spec = kSpecByKey[widget.metricKey];
    final series = ref.watch(allSeriesProvider)[widget.metricKey];
    final latest = ref.watch(latestFullTestProvider);

    if (spec == null || series == null) {
      return Scaffold(
        appBar: AppBar(title: Text(text.resMetricDetail)),
        body: EmptyState(icon: Icons.show_chart, message: text.resNoChartData),
      );
    }

    final now = DateTime.now();
    final visible = applyRange(
      series.points,
      _range,
      at: (p) => p.at,
      now: now,
    );
    final counted = [
      for (final p in visible)
        if (p.counted) p,
    ];
    final stats = computeTrendStats(
      oriented: [
        for (final p in counted)
          if (series.oriented(p.value) != null) series.oriented(p.value)!,
      ],
      raw: series.hasBaseline ? [for (final p in counted) p.value] : null,
    );

    return Scaffold(
      appBar: AppBar(title: Text(featureLabel(text, spec.key))),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(kPagePadding),
          children: [
            RangeSelector(
              value: _range,
              onChanged: (r) => setState(() => _range = r),
            ),
            const SizedBox(height: 14),
            SectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  MetricChart(series: series, range: _range, now: now),
                  const SizedBox(height: 16),
                  TrendStatsPanel(
                    stats: stats,
                    unitFormat: (slope) =>
                        '${slope >= 0 ? '+' : '−'}${formatFeatureValue(spec.key, slope.abs())}',
                  ),
                ],
              ),
            ),
            if (latest != null) ...[
              const SizedBox(height: 14),
              MetricCard(summary: summariseMetric(series, latest.id)),
            ],
            const SizedBox(height: 14),
            const NotADiagnosisNote(),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}
