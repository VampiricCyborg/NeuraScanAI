/// Everything a report says, worked out once.
///
/// The PDF, the CSV and the JSON all read this one model, so they cannot disagree about a
/// number. It is built from the stored tests by the same calculators the screens use; nothing
/// in it is computed a second way for the report.
///
/// Only derived values go in: the measurements a test produced, the scores built from them, and
/// the context the user logged. Raw audio and raw touch traces are never stored, so there is
/// nothing of that kind to leave out -- but the model is also an allow-list of what *may* be
/// exported, and a test checks the exports hold nothing else.
library;

import '../../../data/models.dart';
import '../../../engine/baseline.dart';
import '../../../engine/features.dart';
import '../../../engine/screening_engine.dart';
import '../calculators/analysis.dart';
import '../calculators/trend_stats.dart';
import '../models.dart';
import '../reference_ranges.dart';

/// The parts of a report the user chooses. The cover, the executive summary and the closing
/// disclaimer are always there.
enum ReportSection {
  /// A page for each of the four areas.
  domains,

  /// A section for each of the eight tests.
  tests,

  /// A table of every test in the period, counted or not.
  log,

  /// How the numbers are made, and what they cannot tell you.
  methods,
}

/// What the user asked for.
class ReportOptions {
  const ReportOptions({
    this.period = TrendRange.all,
    this.sections = const {...ReportSection.values},
    this.userLabel = '',
  });

  final TrendRange period;
  final Set<ReportSection> sections;

  /// A name or label for the report, typed by the user. Blank means none.
  final String userLabel;

  bool includes(ReportSection section) => sections.contains(section);

  ReportOptions copyWith({
    TrendRange? period,
    Set<ReportSection>? sections,
    String? userLabel,
  }) => ReportOptions(
    period: period ?? this.period,
    sections: sections ?? this.sections,
    userLabel: userLabel ?? this.userLabel,
  );
}

/// How far the baseline has got.
enum BaselineProgress {
  /// Nothing set yet.
  none,

  /// The core measurements have a baseline; some measurements are still calibrating.
  partial,

  /// Every measurement has one.
  complete,
}

/// The report's data.
class ReportModel {
  const ReportModel({
    required this.generatedAt,
    required this.options,
    required this.from,
    required this.to,
    required this.baselineProgress,
    required this.pendingMeasurements,
    required this.sessions,
    required this.series,
    required this.indexPoints,
    required this.areaPoints,
    required this.indexStats,
    required this.areaStats,
    required this.metricStats,
    required this.log,
    this.latest,
    this.summaries = const [],
    this.topFeatures = const [],
  });

  final DateTime generatedAt;
  final ReportOptions options;

  /// The period covered: from the first test in it to the last.
  final DateTime from;
  final DateTime to;

  final BaselineProgress baselineProgress;

  /// How many measurements still have no baseline.
  final int pendingMeasurements;

  /// Every stored test in the period, counted or not, oldest first.
  final List<SessionRecord> sessions;

  /// Each measurement's tests in the period, against the frozen baseline.
  final Map<String, MetricSeries> series;

  final List<IndexPoint> indexPoints;
  final Map<Domain, List<DomainPoint>> areaPoints;
  final TrendStats indexStats;
  final Map<Domain, TrendStats> areaStats;
  final Map<String, TrendStats> metricStats;
  final List<SessionLogRow> log;

  /// The latest full test in the period, if there is one.
  final SessionRecord? latest;

  /// The eight tests of [latest], against the three references.
  final List<TestSummary> summaries;

  /// The measurements that moved [latest]'s index most.
  final List<TopContributor> topFeatures;

  /// Full tests that counted.
  int get validTests => sessions.where((s) => s.isCounted).length;

  /// Full tests the check-in set aside.
  int get setAsideTests => sessions.where((s) => s.isSetAside).length;

  /// The status the engine gave [latest], or null with no full test.
  ScreeningStatus? get status => latest?.status;

  bool get isEmpty => latest == null;
}

/// Builds the report for [options] from [sessions] (oldest first, current baseline only).
///
/// [now] is the end of day-based periods; it is a parameter so a test can pin it.
ReportModel buildReportModel({
  required List<SessionRecord> sessions,
  required Baseline? baseline,
  required ReferenceRanges ranges,
  required ReportOptions options,
  required DateTime now,
}) {
  // The period is a date window, taken from the full tests so that "last 7" means seven
  // tests wherever they fall; everything else in the window comes with it.
  final fullTests = [
    for (final session in sessions)
      if (session.isFullTest) session,
  ];
  final inWindow = applyRange(
    fullTests,
    options.period,
    at: (s) => s.completedAt,
    now: now,
  );
  final from = inWindow.isEmpty
      ? now
      : (options.period == TrendRange.all && sessions.isNotEmpty
            ? sessions.first.completedAt
            : inWindow.first.completedAt);
  final scoped = [
    for (final session in sessions)
      if (!session.completedAt.isBefore(from) &&
          !session.completedAt.isAfter(now))
        session,
  ];

  // Series over everything, so a test's average of the four before it is the same in a short
  // report as in a long one; the points shown are then those in the window.
  final fullSeries = buildAllSeries(
    sessions: sessions,
    baseline: baseline,
    ranges: ranges,
  );
  final windowed = <String, MetricSeries>{
    for (final entry in fullSeries.entries)
      entry.key: MetricSeries(
        spec: entry.value.spec,
        points: [
          for (final point in entry.value.points)
            if (!point.at.isBefore(from) && !point.at.isAfter(now)) point,
        ],
        baselineMedian: entry.value.baselineMedian,
        baselineScale: entry.value.baselineScale,
        reference: entry.value.reference,
      ),
  };

  final metricStats = {
    for (final entry in windowed.entries)
      entry.key: computeTrendStats(
        oriented: entry.value.orientedCounted,
        raw: entry.value.hasBaseline
            ? [for (final p in entry.value.counted) p.value]
            : null,
      ),
  };

  final indexPoints = buildIndexSeries(scoped);
  final areaPoints = {
    for (final domain in Domain.values)
      domain: buildDomainSeries(domain, scoped),
  };

  final latest = scoped.where((s) => s.isFullTest).lastOrNull;

  return ReportModel(
    generatedAt: now,
    options: options,
    from: from,
    to: scoped.isEmpty ? now : scoped.last.completedAt,
    baselineProgress: baseline == null
        ? BaselineProgress.none
        : baseline.isComplete
        ? BaselineProgress.complete
        : BaselineProgress.partial,
    pendingMeasurements: baseline?.pendingKeys.length ?? kFeatureKeys.length,
    sessions: scoped,
    series: windowed,
    indexPoints: indexPoints,
    areaPoints: areaPoints,
    indexStats: computeTrendStats(
      oriented: [for (final p in indexPoints) p.index],
    ),
    areaStats: {
      for (final entry in areaPoints.entries)
        entry.key: computeTrendStats(
          oriented: [for (final p in entry.value) p.score],
        ),
    },
    metricStats: metricStats,
    // Built from every test so the practice run is recognised by its place in the whole
    // history, then cut to the window.
    log: [
      for (final row in buildSessionLog(sessions))
        if (!row.session.completedAt.isBefore(from) &&
            !row.session.completedAt.isAfter(now))
          row,
    ],
    latest: latest,
    summaries: latest == null
        ? const []
        : summariseTests(series: fullSeries, session: latest),
    topFeatures: latest == null || baseline == null
        ? const []
        : topContributors(session: latest, baseline: baseline),
  );
}

extension _LastOrNull<T> on Iterable<T> {
  T? get lastOrNull => isEmpty ? null : last;
}
