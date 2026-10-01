/// Turning a user's stored tests into the things the results screens and the report show.
///
/// Pure functions of the stored records, the baseline and the reference ranges: no state, no
/// Flutter. The screens, the PDF and the CSV/JSON export all read from here, so the three cannot
/// disagree about what a test said.
///
/// Every measurement is set against three references, and kept apart:
///
/// 1. **The user's own baseline** -- the frozen median and spread. This is the primary
///    reference and the only one that drives any status.
/// 2. **The user's previous tests** -- the last one, the average of the last four, and the best
///    and worst.
/// 3. **The population range** -- context only, shown when it has a source and never read as a
///    verdict.
///
/// Only *valid* tests count in any statistic: full tests that were scored. A test the check-in
/// set aside is listed, marked not counted, and left out of every average, best, worst and
/// trend; nothing is silently dropped.
library;

import '../../../data/models.dart';
import '../../../engine/baseline.dart';
import '../../../engine/comparison.dart';
import '../../../engine/constants.dart';
import '../../../engine/features.dart';
import '../../../engine/scoring.dart';
import '../../../engine/screening_engine.dart';
import '../models.dart';
import '../reference_ranges.dart';
import 'trend_stats.dart';

// -- what kind of test a stored record is -----------------------------------------------

extension SessionKindOf on SessionRecord {
  /// A full test: scored against the baseline, or set aside by the check-in.
  bool get isFullTest =>
      status.isScored || status == ScreeningStatus.excludedContext;

  /// A baseline test, including the practice run.
  bool get isBaselineTest => status == ScreeningStatus.buildingBaseline;

  /// True if this test counts in statistics: a scored full test.
  bool get isCounted => status.isScored;

  /// True if the check-in set this full test aside.
  bool get isSetAside => status == ScreeningStatus.excludedContext;
}

/// Context the user logged on the check-in, worth listing beside a result.
///
/// These are what the user told the app, not causes. "What may explain this" is a list of the
/// things logged, in the user's own terms, and never a medical reason.
enum ContextNote {
  sleepFair,
  sleepPoor,
  fatigueSome,
  fatigueVery,
  illnessOrMedication,
}

/// The things [checkIn] reported that are not "all fine".
List<ContextNote> contextNotes(CheckIn checkIn) => [
  if (checkIn.sleep == SleepQuality.fair) ContextNote.sleepFair,
  if (checkIn.sleep == SleepQuality.poor) ContextNote.sleepPoor,
  if (checkIn.fatigue == FatigueLevel.some) ContextNote.fatigueSome,
  if (checkIn.fatigue == FatigueLevel.very) ContextNote.fatigueVery,
  if (checkIn.illnessOrMedicationChange) ContextNote.illnessOrMedication,
];

/// The things in [checkIn] that were enough to set a test aside.
///
/// A subset of [contextNotes]: poor sleep, heavy tiredness and illness or a medication change.
/// Middling sleep and mild tiredness are logged but do not exclude anything.
List<ContextNote> confoundingNotes(CheckIn checkIn) => [
  if (checkIn.sleep.isConfounding) ContextNote.sleepPoor,
  if (checkIn.fatigue.isConfounding) ContextNote.fatigueVery,
  if (checkIn.illnessOrMedicationChange) ContextNote.illnessOrMedication,
];

// -- series -------------------------------------------------------------------------------

/// One measurement in one full test.
class MetricPoint {
  const MetricPoint({
    required this.sessionId,
    required this.at,
    required this.value,
    required this.counted,
  });

  final String sessionId;
  final DateTime at;
  final double value;

  /// False for a test the check-in set aside: it is shown, hollow, and not counted.
  final bool counted;
}

/// One measurement over the full tests of the current baseline.
class MetricSeries {
  const MetricSeries({
    required this.spec,
    required this.points,
    this.baselineMedian,
    this.baselineScale,
    this.reference,
  });

  final FeatureSpec spec;

  /// Every full test that measured it, oldest first, counted or not.
  final List<MetricPoint> points;

  /// Null while the measurement is still calibrating.
  final double? baselineMedian;
  final double? baselineScale;

  /// The population range for context, or null if there is no entry for it.
  final ReferenceRange? reference;

  bool get hasBaseline => baselineMedian != null && baselineScale != null;

  /// The points that count.
  List<MetricPoint> get counted => [
    for (final point in points)
      if (point.counted) point,
  ];

  /// [value] as spreads from the baseline, positive meaning worse. Null while calibrating.
  double? oriented(double value) => hasBaseline
      ? spec.orient((value - baselineMedian!) / baselineScale!)
      : null;

  /// The counted values as oriented deviations, oldest first. Empty while calibrating.
  List<double> get orientedCounted => [
    if (hasBaseline)
      for (final point in counted) oriented(point.value)!,
  ];

  /// The smoothed curve in the measurement's own units, one entry per counted point.
  ///
  /// The engine's smoothing, applied to this measurement alone: an EWMA of the raw deviation
  /// from the baseline, starting at zero, turned back into the measurement's units so it can be
  /// drawn on the same axis as the values.
  List<({DateTime at, double value})> get smoothed {
    if (!hasBaseline) return const [];
    final rawDeviations = [
      for (final point in counted)
        (point.value - baselineMedian!) / baselineScale!,
    ];
    final curve = ewmaSeries(rawDeviations);
    return [
      for (var i = 0; i < curve.length; i++)
        (at: counted[i].at, value: baselineMedian! + curve[i] * baselineScale!),
    ];
  }
}

/// Builds the series of [spec] from [sessions] (oldest first, current baseline only).
MetricSeries buildMetricSeries({
  required FeatureSpec spec,
  required List<SessionRecord> sessions,
  required Baseline? baseline,
  ReferenceRanges ranges = ReferenceRanges.none,
}) {
  final points = <MetricPoint>[
    for (final session in sessions)
      if (session.isFullTest && session.features[spec.key] != null)
        MetricPoint(
          sessionId: session.id,
          at: session.completedAt,
          value: session.features[spec.key]!,
          counted: session.isCounted,
        ),
  ];
  return MetricSeries(
    spec: spec,
    points: points,
    baselineMedian: baseline?.median[spec.key],
    baselineScale: baseline?.scale[spec.key],
    reference: ranges.forMetric(spec.key),
  );
}

/// Builds every measurement's series.
Map<String, MetricSeries> buildAllSeries({
  required List<SessionRecord> sessions,
  required Baseline? baseline,
  ReferenceRanges ranges = ReferenceRanges.none,
}) => {
  for (final spec in kFeatureSpecs)
    spec.key: buildMetricSeries(
      spec: spec,
      sessions: sessions,
      baseline: baseline,
      ranges: ranges,
    ),
};

// -- per-metric summaries -----------------------------------------------------------------

/// What happened to one measurement in one test.
enum MetricState {
  /// Measured, counted, and compared with its baseline.
  measured,

  /// Measured and counted, but the baseline for it is still being set from the first full
  /// tests, so there is nothing to compare it with yet. Shown as a raw value.
  calibrating,

  /// Not measured in this test: too little typing, or a baseline test that does not include it.
  notMeasured,

  /// Measured, but the check-in set the test aside, so it is listed and not counted.
  notCounted,
}

/// One measurement in one test, against the three references.
class MetricSummary {
  const MetricSummary({
    required this.spec,
    required this.state,
    this.value,
    this.baselineMedian,
    this.baselineScale,
    this.zOriented,
    this.previous,
    this.rollingMean,
    this.best,
    this.worst,
    this.vsBaseline,
    this.vsPrevious,
    this.vsRolling,
    this.reference,
    this.calibrationCollected = 0,
    this.countedTests = 0,
  });

  final FeatureSpec spec;
  final MetricState state;

  /// This test's value. Null only if it was not measured.
  final double? value;

  /// The user's baseline for it, while it has one.
  final double? baselineMedian;
  final double? baselineScale;

  /// Spreads from the baseline, positive meaning worse.
  final double? zOriented;

  /// The last valid test's value before this one.
  final double? previous;

  /// The mean of the (up to) four valid tests before this one.
  final double? rollingMean;

  /// The best and the worst valid value so far, this test included.
  final double? best;
  final double? worst;

  /// Better, about the same or worse, against each reference.
  final Change? vsBaseline;
  final Change? vsPrevious;
  final Change? vsRolling;

  /// The population range, for context. See [ReferenceRanges].
  final ReferenceRange? reference;

  /// While calibrating: how many of the tests it needs have been taken.
  final int calibrationCollected;

  /// Valid tests that measured it, this one included.
  final int countedTests;

  /// This test's value minus the baseline, in the measurement's own units.
  double? get deltaFromBaseline =>
      value == null || baselineMedian == null ? null : value! - baselineMedian!;
}

/// Better, about the same or worse for [deviation], in spreads with positive meaning worse.
Change classifyChange(double deviation) {
  if (deviation >= kSimilarBandSds) return Change.worse;
  if (deviation <= -kSimilarBandSds) return Change.better;
  return Change.similar;
}

/// Summarises [series] for the test with id [sessionId].
MetricSummary summariseMetric(MetricSeries series, String sessionId) {
  final spec = series.spec;
  final index = series.points.indexWhere((p) => p.sessionId == sessionId);
  final countedSoFar = [
    for (final point in series.counted)
      if (index < 0 || !point.at.isAfter(series.points[index].at)) point,
  ];

  if (index < 0) {
    return MetricSummary(
      spec: spec,
      state: MetricState.notMeasured,
      baselineMedian: series.baselineMedian,
      baselineScale: series.baselineScale,
      reference: series.reference,
      countedTests: countedSoFar.length,
    );
  }

  final point = series.points[index];
  if (!point.counted) {
    return MetricSummary(
      spec: spec,
      state: MetricState.notCounted,
      value: point.value,
      baselineMedian: series.baselineMedian,
      baselineScale: series.baselineScale,
      reference: series.reference,
      countedTests: countedSoFar.length,
    );
  }

  final countedIndex = series.counted.indexWhere(
    (p) => p.sessionId == sessionId,
  );
  final values = [for (final p in series.counted) p.value];
  final previous = countedIndex > 0 ? values[countedIndex - 1] : null;
  final rolling = priorMean(values, countedIndex);

  // Best and worst are in the sense of this measurement: the lowest oriented deviation is the
  // best, the highest the worst. Orientation does not need a baseline, only the direction.
  double orient(double v) => spec.direction == Direction.higherIsWorse ? v : -v;
  final uptoNow = values.sublist(0, countedIndex + 1);
  final best = uptoNow.reduce((a, b) => orient(a) <= orient(b) ? a : b);
  final worst = uptoNow.reduce((a, b) => orient(a) >= orient(b) ? a : b);

  if (!series.hasBaseline) {
    return MetricSummary(
      spec: spec,
      state: MetricState.calibrating,
      value: point.value,
      previous: previous,
      rollingMean: rolling,
      best: best,
      worst: worst,
      reference: series.reference,
      calibrationCollected: countedSoFar.length.clamp(0, kExtensionTests),
      countedTests: countedSoFar.length,
    );
  }

  final scale = series.baselineScale!;
  final z = series.oriented(point.value)!;
  return MetricSummary(
    spec: spec,
    state: MetricState.measured,
    value: point.value,
    baselineMedian: series.baselineMedian,
    baselineScale: scale,
    zOriented: z,
    previous: previous,
    rollingMean: rolling,
    best: best,
    worst: worst,
    vsBaseline: classifyChange(z),
    vsPrevious: previous == null
        ? null
        : classifyChange(spec.orient((point.value - previous) / scale)),
    vsRolling: rolling == null
        ? null
        : classifyChange(spec.orient((point.value - rolling) / scale)),
    reference: series.reference,
    countedTests: countedSoFar.length,
  );
}

// -- per-test summaries -------------------------------------------------------------------

/// Whether a test, as a whole, counted.
enum TestValidity {
  /// At least one of its measurements was taken and counted.
  valid,

  /// Nothing in it was measured.
  notMeasured,

  /// The check-in set the whole test aside.
  notCounted,
}

/// One of the eight tests as it came out in one full test.
class TestSummary {
  const TestSummary({
    required this.id,
    required this.validity,
    required this.metrics,
    this.contextReasons = const [],
  });

  final TestId id;
  final TestValidity validity;
  final List<MetricSummary> metrics;

  /// Why the test was set aside, if it was: the confounds the check-in reported.
  final List<ContextNote> contextReasons;
}

/// The eight test summaries for the full test [sessionId].
List<TestSummary> summariseTests({
  required Map<String, MetricSeries> series,
  required SessionRecord session,
}) {
  return [
    for (final id in TestId.values)
      () {
        final metrics = [
          for (final key in id.featureKeys)
            summariseMetric(series[key]!, session.id),
        ];
        final validity = session.isSetAside
            ? TestValidity.notCounted
            : metrics.every((m) => m.state == MetricState.notMeasured)
            ? TestValidity.notMeasured
            : TestValidity.valid;
        return TestSummary(
          id: id,
          validity: validity,
          metrics: metrics,
          contextReasons: session.isSetAside
              ? confoundingNotes(session.checkIn)
              : const [],
        );
      }(),
  ];
}

// -- the session as a whole ---------------------------------------------------------------

/// The measurements that moved the index most in one scored test.
class TopContributor {
  const TopContributor({required this.key, required this.share});

  final String key;

  /// Its share of the deviation index, in index units (they add up to the index).
  final double share;
}

/// The (up to) [count] measurements that contributed most to the index, largest first.
///
/// Only measurements that pushed the index up count: one that moved the good way offsets a
/// little of the change but is not a reason for it. Empty when nothing deviated.
List<TopContributor> topContributors({
  required SessionRecord session,
  required Baseline baseline,
  int count = 3,
}) {
  if (!session.isCounted) return const [];
  final parts = featureContributions(
    session.features,
    baseline.median,
    baseline.scale,
  );
  final positive = [
    for (final entry in parts.entries)
      if (entry.value > 1e-12)
        TopContributor(key: entry.key, share: entry.value),
  ]..sort((a, b) => b.share.compareTo(a.share));
  return positive.take(count).toList();
}

// -- the log ------------------------------------------------------------------------------

/// What kind of entry a test is in the session log.
enum LogKind { practice, baseline, full }

/// One row of the session log.
class SessionLogRow {
  const SessionLogRow({
    required this.session,
    required this.kind,
    required this.counted,
    this.reasons = const [],
  });

  final SessionRecord session;
  final LogKind kind;

  /// True if it counts in the statistics: a scored full test.
  final bool counted;

  /// Why it does not, in the user's terms, when it does not.
  final List<ContextNote> reasons;
}

/// Every test of the current baseline, oldest first, counted or not.
///
/// Nothing is dropped: a test the check-in set aside, and the practice run, appear with the
/// reason they are not counted.
List<SessionLogRow> buildSessionLog(List<SessionRecord> sessions) {
  final rows = <SessionLogRow>[];
  for (var i = 0; i < sessions.length; i++) {
    final session = sessions[i];
    if (session.isFullTest) {
      rows.add(
        SessionLogRow(
          session: session,
          kind: LogKind.full,
          counted: session.isCounted,
          reasons: session.isSetAside
              ? confoundingNotes(session.checkIn)
              : const [],
        ),
      );
    } else {
      final practice = session.epoch == 0 && i < kFamiliarisationSessions;
      rows.add(
        SessionLogRow(
          session: session,
          kind: practice ? LogKind.practice : LogKind.baseline,
          counted: false,
          reasons: session.checkIn.isConfounded
              ? confoundingNotes(session.checkIn)
              : const [],
        ),
      );
    }
  }
  return rows;
}

// -- domains and the overall index --------------------------------------------------------

/// One area's score in one scored test.
class DomainPoint {
  const DomainPoint({
    required this.sessionId,
    required this.at,
    required this.score,
  });

  final String sessionId;
  final DateTime at;

  /// Spreads from the baseline, positive meaning worse.
  final double score;
}

/// The area scores of [domain] over the scored full tests, oldest first.
List<DomainPoint> buildDomainSeries(
  Domain domain,
  List<SessionRecord> sessions,
) => [
  for (final session in sessions)
    if (session.isCounted && session.domainScores?[domain] != null)
      DomainPoint(
        sessionId: session.id,
        at: session.completedAt,
        score: session.domainScores![domain]!,
      ),
];

/// The overall index of one scored test and its smoothed value.
class IndexPoint {
  const IndexPoint({
    required this.sessionId,
    required this.at,
    required this.index,
    required this.ewma,
    required this.contributions,
  });

  final String sessionId;
  final DateTime at;
  final double index;
  final double ewma;

  /// Each area's share of the index; always sums to one.
  final Map<Domain, double> contributions;
}

/// The index over the scored full tests, oldest first.
List<IndexPoint> buildIndexSeries(List<SessionRecord> sessions) => [
  for (final session in sessions)
    if (session.isCounted && session.index != null && session.ewma != null)
      IndexPoint(
        sessionId: session.id,
        at: session.completedAt,
        index: session.index!,
        ewma: session.ewma!,
        contributions: session.contributions ?? const {},
      ),
];
