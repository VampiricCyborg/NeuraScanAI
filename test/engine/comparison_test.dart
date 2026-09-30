/// How a full test compares with the baseline and with the test before it.
///
/// The comparison is what the user reads after each test, so the tests here are about the
/// direction of "better" and "worse" for each measurement -- getting that backwards for one
/// of them would tell someone they had improved when they had not -- and about the band inside
/// which a change is only "about the same".
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:neurascan_ai/engine/baseline.dart';
import 'package:neurascan_ai/engine/comparison.dart';
import 'package:neurascan_ai/engine/features.dart';
import 'package:neurascan_ai/engine/scoring.dart';

import 'engine_test_support.dart';

void main() {
  late Baseline baseline;

  setUp(() {
    baseline = Baseline.fit(variedBaselineSessions());
  });

  /// The baseline's centre, with [sds] of the user's own spread added to one feature.
  Map<String, double> features({Map<String, double> sds = const {}}) => {
    for (final key in kFeatureKeys)
      key: baseline.median[key]! + (sds[key] ?? 0.0) * baseline.scale[key]!,
  };

  MeasurementComparison measurement(TestComparison comparison, String key) =>
      comparison.measurements.firstWhere((m) => m.spec.key == key);

  group('against the baseline', () {
    test('a test at the usual level is about the same everywhere', () {
      final comparison = compareTests(latest: features(), baseline: baseline);
      for (final m in comparison.measurements) {
        expect(m.vsBaseline, Change.similar, reason: m.spec.key);
      }
      for (final area in comparison.areas) {
        expect(area.vsBaseline, Change.similar, reason: area.domain.key);
      }
    });

    test('fewer words remembered is worse', () {
      final comparison = compareTests(
        latest: features(sds: {'delayed_recall': -3.0}),
        baseline: baseline,
      );
      expect(
        measurement(comparison, 'delayed_recall').vsBaseline,
        Change.worse,
      );
    });

    test('more words remembered is better', () {
      final comparison = compareTests(
        latest: features(sds: {'delayed_recall': 3.0}),
        baseline: baseline,
      );
      expect(
        measurement(comparison, 'delayed_recall').vsBaseline,
        Change.better,
      );
    });

    test('each measurement is oriented the right way round', () {
      // Speaking faster is better; pausing more, tracing less accurately and shaking more
      // are worse. A wrong sign for any of these would reverse what the user is told.
      final cases = <String, ({double up, Change expected})>{
        'delayed_recall': (up: 3.0, expected: Change.better),
        'speaking_rate': (up: 3.0, expected: Change.better),
        'pause_ratio': (up: 3.0, expected: Change.worse),
        'spiral_rmse': (up: 3.0, expected: Change.worse),
        'tremor_index': (up: 3.0, expected: Change.worse),
      };
      for (final entry in cases.entries) {
        final comparison = compareTests(
          latest: features(sds: {entry.key: entry.value.up}),
          baseline: baseline,
        );
        expect(
          measurement(comparison, entry.key).vsBaseline,
          entry.value.expected,
          reason: 'a rise in ${entry.key}',
        );
      }
    });

    test('a change inside the usual spread is about the same', () {
      final comparison = compareTests(
        latest: features(sds: {'spiral_rmse': 0.9, 'delayed_recall': -0.9}),
        baseline: baseline,
      );
      expect(measurement(comparison, 'spiral_rmse').vsBaseline, Change.similar);
      expect(
        measurement(comparison, 'delayed_recall').vsBaseline,
        Change.similar,
      );
    });

    test('a change of exactly one spread already counts', () {
      final comparison = compareTests(
        latest: features(sds: {'spiral_rmse': kSimilarBandSds}),
        baseline: baseline,
      );
      expect(measurement(comparison, 'spiral_rmse').vsBaseline, Change.worse);
    });

    test('the distance is in units of the user\'s own spread', () {
      final comparison = compareTests(
        latest: features(sds: {'tremor_index': 2.5}),
        baseline: baseline,
      );
      expect(
        measurement(comparison, 'tremor_index').sdsFromBaseline,
        closeTo(2.5, 1e-9),
      );
    });
  });

  group('against the previous test', () {
    test('the first full test has nothing to compare with', () {
      final comparison = compareTests(latest: features(), baseline: baseline);
      expect(comparison.hasPrevious, isFalse);
      for (final m in comparison.measurements) {
        expect(m.previous, isNull);
        expect(m.vsPrevious, isNull);
      }
      for (final area in comparison.areas) {
        expect(area.vsPrevious, isNull);
      }
    });

    test('a later test is compared with the one before it', () {
      final comparison = compareTests(
        latest: features(sds: {'spiral_rmse': 0.5}),
        previous: features(sds: {'spiral_rmse': 3.0}),
        baseline: baseline,
      );
      expect(comparison.hasPrevious, isTrue);
      // Still a bit off the usual level, but a good deal better than last time.
      final rmse = measurement(comparison, 'spiral_rmse');
      expect(rmse.vsBaseline, Change.similar);
      expect(rmse.vsPrevious, Change.better);
    });

    test('getting worse since last time is reported as such', () {
      final comparison = compareTests(
        latest: features(sds: {'delayed_recall': -2.5}),
        previous: features(),
        baseline: baseline,
      );
      expect(
        measurement(comparison, 'delayed_recall').vsPrevious,
        Change.worse,
      );
    });

    test('a small move since last time is about the same', () {
      final comparison = compareTests(
        latest: features(sds: {'pause_ratio': 0.4}),
        previous: features(sds: {'pause_ratio': -0.4}),
        baseline: baseline,
      );
      expect(measurement(comparison, 'pause_ratio').vsPrevious, Change.similar);
    });

    test('the two comparisons are independent', () {
      // Worse than usual, yet better than last time: both are true and both are shown.
      final comparison = compareTests(
        latest: features(sds: {'speaking_rate': -2.0}),
        previous: features(sds: {'speaking_rate': -5.0}),
        baseline: baseline,
      );
      final rate = measurement(comparison, 'speaking_rate');
      expect(rate.vsBaseline, Change.worse);
      expect(rate.vsPrevious, Change.better);
    });

    test('the previous value is carried through for display', () {
      final previous = features(sds: {'delayed_recall': -1.0});
      final comparison = compareTests(
        latest: features(),
        previous: previous,
        baseline: baseline,
      );
      expect(
        measurement(comparison, 'delayed_recall').previous,
        previous['delayed_recall'],
      );
    });
  });

  group('by area', () {
    test('there is one for each area, in order', () {
      final comparison = compareTests(latest: features(), baseline: baseline);
      expect([for (final a in comparison.areas) a.domain], Domain.values);
    });

    test('an area holds its own measurements', () {
      final comparison = compareTests(latest: features(), baseline: baseline);
      for (final area in comparison.areas) {
        expect(
          [for (final m in area.measurements) m.spec.key],
          [for (final spec in specsFor(area.domain)) spec.key],
        );
      }
    });

    test('an area\'s score is the same one the engine uses', () {
      final latest = features(
        sds: {'delayed_recall': -2.0, 'pause_ratio': 1.0},
      );
      final comparison = compareTests(latest: latest, baseline: baseline);
      final engineScores = domainScores(
        latest,
        baseline.median,
        baseline.scale,
      );
      for (final area in comparison.areas) {
        expect(area.score, closeTo(engineScores[area.domain]!, 1e-12));
      }
    });

    test('a decline in one area does not colour the others', () {
      final comparison = compareTests(
        latest: features(sds: {'delayed_recall': -4.0}),
        baseline: baseline,
      );
      Change of(Domain d) =>
          comparison.areas.firstWhere((a) => a.domain == d).vsBaseline;
      expect(of(Domain.cognitive), Change.worse);
      expect(of(Domain.speech), Change.similar);
      expect(of(Domain.motor), Change.similar);
    });

    test('an area with mixed measurements averages them', () {
      // One speech measurement much worse, the other much better: the area is the mean.
      final comparison = compareTests(
        latest: features(sds: {'speaking_rate': 3.0, 'pause_ratio': 3.0}),
        baseline: baseline,
      );
      final speech = comparison.areas.firstWhere(
        (a) => a.domain == Domain.speech,
      );
      // speaking_rate +3 is better (-3 oriented), pause_ratio +3 is worse (+3).
      expect(speech.score, closeTo(0.0, 1e-9));
      expect(speech.vsBaseline, Change.similar);
    });

    test('the change since last time is measured on the area score', () {
      final comparison = compareTests(
        latest: features(sds: {'delayed_recall': -1.0}),
        previous: features(sds: {'delayed_recall': -4.0}),
        baseline: baseline,
      );
      final cognitive = comparison.areas.firstWhere(
        (a) => a.domain == Domain.cognitive,
      );
      expect(cognitive.changeFromPrevious, closeTo(-3.0, 1e-9));
      expect(cognitive.vsPrevious, Change.better);
    });
  });

  group('incomplete input', () {
    test('a measurement that is missing is left out, not guessed', () {
      final partial = features()..remove('tremor_index');
      final comparison = compareTests(latest: partial, baseline: baseline);
      expect(
        comparison.measurements.any((m) => m.spec.key == 'tremor_index'),
        isFalse,
      );
      expect(comparison.measurements, hasLength(kFeatureKeys.length - 1));
    });

    test('an area with nothing measured is left out', () {
      final motorless = features()
        ..remove('spiral_rmse')
        ..remove('tremor_index');
      final comparison = compareTests(latest: motorless, baseline: baseline);
      expect(comparison.areas.any((a) => a.domain == Domain.motor), isFalse);
    });
  });
}
