/// The analysis behind the results screens and the report.
///
/// What is protected: that a measurement is set against all three references and each is the
/// right number; that a test the check-in set aside is listed and never counted; that a
/// measurement still calibrating, or not measured, says so instead of inventing a value; and
/// that the shares of the index add up.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:neurascan_ai/data/models.dart';
import 'package:neurascan_ai/engine/comparison.dart';
import 'package:neurascan_ai/engine/constants.dart';
import 'package:neurascan_ai/engine/features.dart';
import 'package:neurascan_ai/features/report/calculators/analysis.dart';
import 'package:neurascan_ai/features/report/models.dart';
import 'package:neurascan_ai/features/report/reference_ranges.dart';

import 'report_fixtures.dart';

void main() {
  /// The first three full tests define the baseline of the extended measurements, so the
  /// offsets below are measured against a baseline of exactly nominal: a spread of half the
  /// typical day-to-day variation (the floor), since the three values are equal.
  ///
  /// Reaction time nominal 320 ms, floor spread 9 ms.
  const reactionOffsets = [0.0, 0.0, 0.0, 1.0, 2.0, 3.0, 4.0, -1.0];

  Fixture fixture({
    Set<int> setAside = const {},
    Set<String> omit = const {},
  }) => buildFixture(
    fullTests: reactionOffsets.length,
    setAside: setAside,
    omit: omit,
    jitterFor: (i) => {'reaction_median': reactionOffsets[i]},
  );

  /// The session id of the `i`th full test in a fixture: after the baseline tests.
  String idOf(int i) => 'fx-${kBaselineTests + i}';

  MetricSeries seriesOf(
    Fixture f,
    String key, {
    ReferenceRanges ranges = ReferenceRanges.none,
  }) => buildMetricSeries(
    spec: kSpecByKey[key]!,
    sessions: f.sessions,
    baseline: f.baseline,
    ranges: ranges,
  );

  group('what kind of test a record is', () {
    final f = fixture(setAside: {3});

    test('baseline tests are baseline tests, not full tests', () {
      for (final s in f.sessions.take(kBaselineTests)) {
        expect(s.isBaselineTest, isTrue);
        expect(s.isFullTest, isFalse);
        expect(s.isCounted, isFalse);
      }
    });

    test('a scored test is a counted full test', () {
      final s = f.sessions.firstWhere((s) => s.id == idOf(0));
      expect(s.isFullTest, isTrue);
      expect(s.isCounted, isTrue);
      expect(s.isSetAside, isFalse);
    });

    test('a tired test is a full test that is set aside and not counted', () {
      final s = f.sessions.firstWhere((s) => s.id == idOf(3));
      expect(s.isFullTest, isTrue);
      expect(s.isSetAside, isTrue);
      expect(s.isCounted, isFalse);
    });
  });

  group('a measurement over time', () {
    test('has a point for every full test that measured it', () {
      final series = seriesOf(fixture(), 'reaction_median');
      expect(series.points, hasLength(reactionOffsets.length));
    });

    test('points are oldest first', () {
      final series = seriesOf(fixture(), 'reaction_median');
      for (var i = 1; i < series.points.length; i++) {
        expect(series.points[i].at.isAfter(series.points[i - 1].at), isTrue);
      }
    });

    test('a test set aside is a point, but not a counted one', () {
      final series = seriesOf(fixture(setAside: {3}), 'reaction_median');
      expect(series.points, hasLength(reactionOffsets.length));
      expect(series.counted, hasLength(reactionOffsets.length - 1));
      expect(series.points[3].counted, isFalse);
    });

    test('baseline tests are not points of a full-test series', () {
      final f = fixture();
      final series = seriesOf(f, 'delayed_recall');
      final ids = series.points.map((p) => p.sessionId).toSet();
      for (final s in f.sessions.take(kBaselineTests)) {
        expect(ids, isNot(contains(s.id)));
      }
    });

    test('carries the baseline median and spread', () {
      final f = fixture();
      final series = seriesOf(f, 'reaction_median');
      expect(series.hasBaseline, isTrue);
      expect(series.baselineMedian, closeTo(320.0, 1e-9));
      expect(
        series.baselineScale,
        closeTo(f.baseline.scale['reaction_median']!, 1e-12),
      );
    });

    test('oriented deviations are positive when worse', () {
      final series = seriesOf(fixture(), 'reaction_median');
      // Test index 3 is a rise of one within-person spread (18 ms) over a 9 ms floor.
      expect(series.oriented(338.0), closeTo(2.0, 1e-9));
      expect(series.oriented(302.0), closeTo(-2.0, 1e-9));
    });

    test('a lower-is-worse measurement is oriented the other way', () {
      final series = seriesOf(fixture(), 'valid_word_count');
      final median = series.baselineMedian!;
      expect(series.oriented(median - 4.0)!, greaterThan(0.0));
      expect(series.oriented(median + 4.0)!, lessThan(0.0));
    });

    test('the counted deviations leave out a test set aside', () {
      final series = seriesOf(fixture(setAside: {3}), 'reaction_median');
      expect(series.orientedCounted, hasLength(reactionOffsets.length - 1));
    });

    test('the smoothed curve has one entry per counted test', () {
      final series = seriesOf(fixture(setAside: {3}), 'reaction_median');
      expect(series.smoothed, hasLength(series.counted.length));
    });

    test('the smoothed curve starts from the baseline and follows the engine\'s rule', () {
      final series = seriesOf(fixture(), 'reaction_median');
      // The first three tests equal the baseline, so the curve is flat at the median.
      for (final point in series.smoothed.take(3)) {
        expect(point.value, closeTo(320.0, 1e-9));
      }
      // The fourth is 18 ms above, so the curve moves by a third of that.
      expect(series.smoothed[3].value, closeTo(320.0 + 0.3 * 18.0, 1e-9));
    });

    test('carries the population reference for context', () {
      final ranges = ReferenceRanges.parse(
        '{"ranges":[{"metric":"reaction_median","age_band":"all","low":null,'
        '"high":null,"unit":"ms","source_citation":null,"evidence_level":"placeholder"}]}',
      );
      final series = seriesOf(fixture(), 'reaction_median', ranges: ranges);
      expect(series.reference, isNotNull);
      expect(series.reference!.isValidated, isFalse);
    });

    test('a measurement nobody took has no points', () {
      final series = seriesOf(
        fixture(omit: {'inter_key_interval'}),
        'inter_key_interval',
      );
      expect(series.points, isEmpty);
    });
  });

  group('the three-way comparison', () {
    final f = fixture();
    final series = seriesOf(f, 'reaction_median');

    // Full test 6: +4 spreads, 392 ms; the one before was +3 (374 ms).
    final summary = summariseMetric(series, idOf(6));

    test('is measured, with the value', () {
      expect(summary.state, MetricState.measured);
      expect(summary.value, closeTo(392.0, 1e-9));
    });

    test('against the personal baseline: median, spread and distance', () {
      expect(summary.baselineMedian, closeTo(320.0, 1e-9));
      expect(summary.baselineScale, closeTo(9.0, 1e-9));
      expect(summary.zOriented, closeTo(8.0, 1e-9));
      expect(summary.vsBaseline, Change.worse);
      expect(summary.deltaFromBaseline, closeTo(72.0, 1e-9));
    });

    test('against the previous test', () {
      expect(summary.previous, closeTo(374.0, 1e-9));
      // 18 ms over a 9 ms spread is two spreads worse.
      expect(summary.vsPrevious, Change.worse);
    });

    test('against the average of the four before', () {
      // Tests 2 to 5: 320, 338, 356, 374 -> 347.
      expect(summary.rollingMean, closeTo(347.0, 1e-9));
      expect(summary.vsRolling, Change.worse);
    });

    test('the best and the worst valid test so far', () {
      expect(summary.best, closeTo(320.0, 1e-9));
      expect(summary.worst, closeTo(392.0, 1e-9));
    });

    test('a later, better test leaves the worst where it was', () {
      final later = summariseMetric(series, idOf(7));
      expect(later.value, closeTo(302.0, 1e-9));
      expect(later.worst, closeTo(392.0, 1e-9));
      expect(later.best, closeTo(302.0, 1e-9));
      expect(later.vsBaseline, Change.better);
    });

    test('best and worst are in the sense of the measurement', () {
      // Lower is worse for the number of animals named: the worst is the smallest.
      final words = buildFixture(
        fullTests: 6,
        jitterFor: (i) => {
          'valid_word_count': [0.0, 0.0, 0.0, -3.0, 2.0, -1.0][i],
        },
      );
      final s = summariseMetric(
        buildMetricSeries(
          spec: kSpecByKey['valid_word_count']!,
          sessions: words.sessions,
          baseline: words.baseline,
        ),
        'fx-${kBaselineTests + 5}',
      );
      expect(s.worst, closeTo(16.0 - 6.0, 1e-9));
      expect(s.best, closeTo(16.0 + 4.0, 1e-9));
    });

    test('the population reference is carried, apart from the rest', () {
      final withRange = summariseMetric(
        seriesOf(
          f,
          'reaction_median',
          ranges: ReferenceRanges.parse(
            '{"ranges":[{"metric":"reaction_median","age_band":"all","low":null,'
            '"high":null,"unit":"ms","source_citation":null,'
            '"evidence_level":"placeholder"}]}',
          ),
        ),
        idOf(6),
      );
      expect(withRange.reference, isNotNull);
      // Its presence changes nothing about the personal comparison.
      expect(withRange.vsBaseline, summary.vsBaseline);
      expect(withRange.zOriented, summary.zOriented);
    });

    test('the first test has nothing before it', () {
      final first = summariseMetric(series, idOf(0));
      expect(first.previous, isNull);
      expect(first.rollingMean, isNull);
      expect(first.vsPrevious, isNull);
      expect(first.vsRolling, isNull);
      // But it is still set against the baseline.
      expect(first.vsBaseline, isNotNull);
    });

    test('the second test is compared with the first only', () {
      final second = summariseMetric(series, idOf(1));
      expect(second.previous, closeTo(320.0, 1e-9));
      expect(second.rollingMean, closeTo(320.0, 1e-9));
    });

    test('a change inside the usual spread reads as about the same', () {
      final steady = buildFixture(
        fullTests: 5,
        jitterFor: (i) => {
          'reaction_median': [0.0, 0.0, 0.0, 0.2, 0.3][i],
        },
      );
      final s = summariseMetric(
        buildMetricSeries(
          spec: kSpecByKey['reaction_median']!,
          sessions: steady.sessions,
          baseline: steady.baseline,
        ),
        'fx-${kBaselineTests + 4}',
      );
      expect(s.vsBaseline, Change.similar);
      expect(s.vsPrevious, Change.similar);
    });
  });

  group('a test set aside is listed and never counted', () {
    final f = fixture(setAside: {3});
    final series = seriesOf(f, 'reaction_median');

    test('its measurement is shown, marked not counted', () {
      final s = summariseMetric(series, idOf(3));
      expect(s.state, MetricState.notCounted);
      expect(s.value, closeTo(338.0, 1e-9));
    });

    test('it is given no comparison', () {
      final s = summariseMetric(series, idOf(3));
      expect(s.vsBaseline, isNull);
      expect(s.vsPrevious, isNull);
      expect(s.zOriented, isNull);
    });

    test('it is left out of the average of the tests before a later one', () {
      // Full test 4: the four counted tests before it are 0, 1, 2 (test 3 is set aside), so
      // 320, 320, 320 -> mean 320, not dragged by the tired day.
      final s = summariseMetric(series, idOf(4));
      expect(s.rollingMean, closeTo(320.0, 1e-9));
    });

    test('the previous test for the next one is the last counted, not the tired day', () {
      final s = summariseMetric(series, idOf(4));
      expect(s.previous, closeTo(320.0, 1e-9));
    });

    test('it cannot be the best or the worst', () {
      // The tired day was +1 spread; the worst valid test is unaffected by it being skipped.
      final s = summariseMetric(series, idOf(6));
      expect(s.worst, closeTo(392.0, 1e-9));
    });

    test('the whole test is marked not counted, with the reason', () {
      final session = f.sessions.firstWhere((s) => s.id == idOf(3));
      final tests = summariseTests(
        series: buildAllSeries(sessions: f.sessions, baseline: f.baseline),
        session: session,
      );
      for (final test in tests) {
        expect(test.validity, TestValidity.notCounted, reason: test.id.name);
        expect(test.contextReasons, contains(ContextNote.sleepPoor));
      }
    });

    test('it stays in the log, with the reason', () {
      final log = buildSessionLog(f.sessions);
      final row = log.firstWhere((r) => r.session.id == idOf(3));
      expect(row.kind, LogKind.full);
      expect(row.counted, isFalse);
      expect(row.reasons, isNotEmpty);
    });
  });

  group('a measurement still calibrating', () {
    // Two full tests: the baseline of the extended measurements is not set yet.
    final f = buildFixture(fullTests: 2);
    final all = buildAllSeries(sessions: f.sessions, baseline: f.baseline);

    test('has no baseline', () {
      expect(all['reaction_median']!.hasBaseline, isFalse);
      expect(all['delayed_recall']!.hasBaseline, isTrue);
    });

    test('is shown as a raw value with no comparison', () {
      final s = summariseMetric(
        all['reaction_median']!,
        'fx-${kBaselineTests + 1}',
      );
      expect(s.state, MetricState.calibrating);
      expect(s.value, isNotNull);
      expect(s.zOriented, isNull);
      expect(s.vsBaseline, isNull);
      expect(s.baselineMedian, isNull);
    });

    test('says how many of the tests it needs have been taken', () {
      final first = summariseMetric(
        all['reaction_median']!,
        'fx-$kBaselineTests',
      );
      final second = summariseMetric(
        all['reaction_median']!,
        'fx-${kBaselineTests + 1}',
      );
      expect(first.calibrationCollected, 1);
      expect(second.calibrationCollected, 2);
    });

    test('never says more than the number it needs', () {
      final many = buildFixture(fullTests: 2);
      expect(
        many.engine.calibrationCollected,
        lessThanOrEqualTo(kExtensionTests),
      );
    });

    test('still compares with the previous test, which needs no baseline', () {
      final s = summariseMetric(
        all['reaction_median']!,
        'fx-${kBaselineTests + 1}',
      );
      expect(s.previous, isNotNull);
      // No baseline spread to judge the change by, so no better/worse word either.
      expect(s.vsPrevious, isNull);
    });

    test('has no smoothed curve and no oriented deviations', () {
      expect(all['reaction_median']!.smoothed, isEmpty);
      expect(all['reaction_median']!.orientedCounted, isEmpty);
    });

    test('a core measurement in the same test is measured normally', () {
      final s = summariseMetric(
        all['delayed_recall']!,
        'fx-${kBaselineTests + 1}',
      );
      expect(s.state, MetricState.measured);
    });
  });

  group('a measurement that was not taken', () {
    final f = fixture(omit: {'inter_key_interval', 'inter_key_cv'});
    final all = buildAllSeries(sessions: f.sessions, baseline: f.baseline);

    test('is not measured, with no value', () {
      final s = summariseMetric(all['inter_key_interval']!, idOf(5));
      expect(s.state, MetricState.notMeasured);
      expect(s.value, isNull);
    });

    test('the typing test as a whole is not measured', () {
      final session = f.sessions.firstWhere((s) => s.id == idOf(5));
      final tests = summariseTests(series: all, session: session);
      final typing = tests.firstWhere((t) => t.id == TestId.typing);
      expect(typing.validity, TestValidity.notMeasured);
    });

    test('the other tests are unaffected', () {
      final session = f.sessions.firstWhere((s) => s.id == idOf(5));
      final tests = summariseTests(series: all, session: session);
      for (final test in tests.where((t) => t.id != TestId.typing)) {
        expect(test.validity, TestValidity.valid, reason: test.id.name);
      }
    });
  });

  group('the eight tests', () {
    final f = fixture();
    final all = buildAllSeries(sessions: f.sessions, baseline: f.baseline);
    final session = f.sessions.firstWhere((s) => s.id == idOf(6));
    final tests = summariseTests(series: all, session: session);

    test('there are eight, in order', () {
      expect([for (final t in tests) t.id], TestId.values);
    });

    test('each holds its own measurements', () {
      for (final test in tests) {
        expect([for (final m in test.metrics) m.spec.key], test.id.featureKeys);
      }
    });

    test('together they cover every measurement once', () {
      final keys = [
        for (final t in tests)
          for (final m in t.metrics) m.spec.key,
      ];
      expect(keys.toSet(), kFeatureKeys.toSet());
      expect(keys, hasLength(kFeatureKeys.length));
    });

    test('a normal test is valid throughout', () {
      for (final test in tests) {
        expect(test.validity, TestValidity.valid, reason: test.id.name);
      }
    });

    test('every measurement belongs to one test', () {
      for (final key in kFeatureKeys) {
        expect(testOf(key).featureKeys, contains(key));
      }
    });

    test('tests know their areas', () {
      expect(TestId.typing.domains, [Domain.interaction]);
      expect(TestId.wordMemory.domains, [Domain.cognitive]);
      expect(TestId.tapping.domains, [Domain.motor]);
    });
  });

  group('the measurements that moved the index', () {
    test('are the ones that declined, largest first, at most three', () {
      final f = buildFixture(
        fullTests: 6,
        jitterFor: (i) => i == 5
            ? {
                'tap_rate': -6.0,
                'delayed_recall': -5.0,
                'spiral_rmse': 4.0,
                'pause_ratio': 2.0,
              }
            : const {},
      );
      final last = f.sessions.last;
      final top = topContributors(session: last, baseline: f.baseline);

      expect(top.length, lessThanOrEqualTo(3));
      expect(top, isNotEmpty);
      for (var i = 1; i < top.length; i++) {
        expect(top[i].share, lessThanOrEqualTo(top[i - 1].share));
      }
      // The two that dropped furthest in their areas are among them.
      expect(top.map((t) => t.key), contains('tap_rate'));
    });

    test('never include a measurement that moved the good way', () {
      final f = buildFixture(
        fullTests: 6,
        jitterFor: (i) => i == 5
            ? {
                'tap_rate': -6.0,
                'immediate_recall': 3.0,
                'delayed_recall': -6.0,
              }
            : const {},
      );
      final top = topContributors(
        session: f.sessions.last,
        baseline: f.baseline,
        count: 18,
      );
      expect(top.map((t) => t.key), isNot(contains('immediate_recall')));
      for (final t in top) {
        expect(t.share, greaterThan(0));
      }
    });

    test('are empty for a steady test', () {
      final f = buildFixture(fullTests: 5, noiseSds: 0);
      expect(
        topContributors(session: f.sessions.last, baseline: f.baseline),
        isEmpty,
      );
    });

    test('are empty for a test set aside', () {
      final f = buildFixture(fullTests: 5, setAside: {4});
      expect(
        topContributors(session: f.sessions.last, baseline: f.baseline),
        isEmpty,
      );
    });

    test('the counts can be changed', () {
      final f = buildFixture(
        fullTests: 6,
        jitterFor: (i) => i == 5
            ? {'tap_rate': -6.0, 'delayed_recall': -5.0, 'spiral_rmse': 4.0}
            : const {},
      );
      expect(
        topContributors(
          session: f.sessions.last,
          baseline: f.baseline,
          count: 1,
        ),
        hasLength(1),
      );
    });

    test('add up to the index, all of them together', () {
      final f = buildFixture(
        fullTests: 6,
        jitterFor: (i) => i == 5
            ? {'tap_rate': -6.0, 'delayed_recall': -5.0, 'spiral_rmse': 4.0}
            : const {},
      );
      final last = f.sessions.last;
      final parts = topContributors(
        session: last,
        baseline: f.baseline,
        count: 18,
      );
      // Positive parts only, so they can exceed the index when something offset them, but
      // they are never less than it.
      final sum = parts.fold<double>(0, (a, b) => a + b.share);
      expect(sum, greaterThanOrEqualTo(last.index! - 1e-9));
    });
  });

  group('the session log', () {
    final f = fixture(setAside: {3});
    final log = buildSessionLog(f.sessions);

    test('has a row for every test, none dropped', () {
      expect(log, hasLength(f.sessions.length));
    });

    test('the first test is the practice run', () {
      expect(log.first.kind, LogKind.practice);
      expect(log.first.counted, isFalse);
    });

    test('the next ones are baseline tests', () {
      for (final row in log.skip(1).take(kBaselineSessions)) {
        expect(row.kind, LogKind.baseline);
        expect(row.counted, isFalse);
      }
    });

    test('the rest are full tests, counted unless set aside', () {
      final full = log.skip(kBaselineTests).toList();
      expect(full.every((r) => r.kind == LogKind.full), isTrue);
      expect(full.where((r) => r.counted), hasLength(full.length - 1));
    });

    test('is oldest first', () {
      for (var i = 1; i < log.length; i++) {
        expect(
          log[i].session.completedAt.isAfter(log[i - 1].session.completedAt),
          isTrue,
        );
      }
    });

    test('a later baseline has no practice run', () {
      final later = buildFixture(fullTests: 2, epoch: 1);
      // Tests of a later baseline: the first is a baseline test, not practice.
      expect(buildSessionLog(later.sessions).first.kind, LogKind.baseline);
    });
  });

  group('areas and the overall index', () {
    final f = fixture(setAside: {3});

    test('an area has a score for every counted test', () {
      final series = buildDomainSeries(Domain.cognitive, f.sessions);
      expect(series, hasLength(f.counted.length));
    });

    test('a test set aside has no area score and is not in the series', () {
      final series = buildDomainSeries(Domain.cognitive, f.sessions);
      expect(series.map((p) => p.sessionId), isNot(contains(idOf(3))));
    });

    test('the index series has a point for every counted test', () {
      expect(buildIndexSeries(f.sessions), hasLength(f.counted.length));
    });

    test('each test\'s shares of the index add up to one', () {
      for (final point in buildIndexSeries(f.sessions)) {
        final total = point.contributions.values.fold<double>(
          0,
          (a, b) => a + b,
        );
        expect(total, closeTo(1.0, 1e-9), reason: point.sessionId);
      }
    });

    test('every area appears in every test\'s shares', () {
      for (final point in buildIndexSeries(f.sessions)) {
        expect(point.contributions.keys.toSet(), Domain.values.toSet());
      }
    });

    test('the smoothed index is the engine\'s, not recomputed', () {
      final points = buildIndexSeries(f.sessions);
      for (final point in points) {
        final session = f.sessions.firstWhere((s) => s.id == point.sessionId);
        expect(point.ewma, session.ewma);
        expect(point.index, session.index);
      }
    });
  });

  group('the things the user logged', () {
    CheckIn check({
      SleepQuality sleep = SleepQuality.good,
      FatigueLevel fatigue = FatigueLevel.none,
      bool illness = false,
    }) => CheckIn(
      sleep: sleep,
      fatigue: fatigue,
      illnessOrMedicationChange: illness,
      answeredAt: DateTime(2026),
    );

    test('an ordinary day logs nothing', () {
      expect(contextNotes(check()), isEmpty);
    });

    test('middling sleep is noted', () {
      expect(contextNotes(check(sleep: SleepQuality.fair)), [
        ContextNote.sleepFair,
      ]);
    });

    test('poor sleep is noted', () {
      expect(contextNotes(check(sleep: SleepQuality.poor)), [
        ContextNote.sleepPoor,
      ]);
    });

    test('tiredness is noted at both levels', () {
      expect(contextNotes(check(fatigue: FatigueLevel.some)), [
        ContextNote.fatigueSome,
      ]);
      expect(contextNotes(check(fatigue: FatigueLevel.very)), [
        ContextNote.fatigueVery,
      ]);
    });

    test('illness or a medication change is noted', () {
      expect(contextNotes(check(illness: true)), [
        ContextNote.illnessOrMedication,
      ]);
    });

    test('several are all listed', () {
      expect(
        contextNotes(
          check(
            sleep: SleepQuality.fair,
            fatigue: FatigueLevel.some,
            illness: true,
          ),
        ),
        hasLength(3),
      );
    });
  });

  group('better, the same or worse', () {
    test('within one spread is the same', () {
      expect(classifyChange(0.9), Change.similar);
      expect(classifyChange(-0.9), Change.similar);
      expect(classifyChange(0.0), Change.similar);
    });

    test('one spread or more is a change', () {
      expect(classifyChange(kSimilarBandSds), Change.worse);
      expect(classifyChange(-kSimilarBandSds), Change.better);
    });

    test('positive is worse and negative is better', () {
      expect(classifyChange(3.0), Change.worse);
      expect(classifyChange(-3.0), Change.better);
    });
  });

  test('a summary of a session that is not in the series is not measured', () {
    final series = seriesOf(fixture(), 'reaction_median');
    expect(
      summariseMetric(series, 'no-such-session').state,
      MetricState.notMeasured,
    );
  });
}
