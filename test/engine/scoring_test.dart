/// UT6, UT7 and UT8 -- scoring, orientation and the exactness of explanations.
///
/// Mirrors `engine_lab/tests/test_scoring.py`, covering Table 9.2 rows UT6-7
/// (lower recall raises the cognitive score, and improvements never raise the
/// index) and UT8 (domain contributions sum to 1).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:neurascan_ai/engine/baseline.dart';
import 'package:neurascan_ai/engine/features.dart';
import 'package:neurascan_ai/engine/scoring.dart';

import 'engine_test_support.dart';

void main() {
  late Baseline baseline;

  setUp(() {
    baseline = Baseline.fit(variedBaselineSessions());
  });

  double indexFor(Map<String, double> jitter) => deviationIndex(
    domainScoresFrom(makeSession(jitter: jitter).features, baseline),
  );

  Map<Domain, double> scoresFor(Map<String, double> jitter) =>
      domainScoresFrom(makeSession(jitter: jitter).features, baseline);

  group('UT6 -- worse performance produces a positive domain score', () {
    test('lower recall raises the cognitive score', () {
      expect(
        scoresFor({'delayed_recall': -3.0})[Domain.cognitive],
        greaterThan(0.0),
      );
    });

    test('higher recall lowers the cognitive score', () {
      expect(
        scoresFor({'delayed_recall': 3.0})[Domain.cognitive],
        lessThan(0.0),
      );
    });

    test('slower, more halting speech raises the speech score', () {
      final scores = scoresFor({'speaking_rate': -3.0, 'pause_ratio': 3.0});
      expect(scores[Domain.speech], greaterThan(0.0));
    });

    test('shakier tracing raises the motor score', () {
      final scores = scoresFor({'spiral_rmse': 3.0, 'tremor_index': 3.0});
      expect(scores[Domain.motor], greaterThan(0.0));
    });

    test('a typical session scores near zero in every domain', () {
      final scores = domainScoresFrom(makeSession().features, baseline);
      for (final entry in scores.entries) {
        expect(
          entry.value.abs(),
          lessThan(1.0),
          reason: '${entry.key.label} drifted without any change',
        );
      }
    });

    test('every feature is oriented so that positive means worse', () {
      for (final spec in kFeatureSpecs) {
        if (spec.direction == Direction.lowerIsWorse) {
          expect(spec.orient(-2.0), greaterThan(0.0), reason: spec.key);
          expect(spec.orient(2.0), lessThan(0.0), reason: spec.key);
        } else {
          expect(spec.orient(2.0), greaterThan(0.0), reason: spec.key);
          expect(spec.orient(-2.0), lessThan(0.0), reason: spec.key);
        }
      }
    });

    test('every domain owns at least one feature', () {
      for (final domain in Domain.values) {
        expect(specsFor(domain), isNotEmpty, reason: domain.key);
      }
    });

    test('the domain weights sum to one', () {
      final total = kDomainWeights.values.reduce((a, b) => a + b);
      expect(total, closeTo(1.0, 1e-12));
    });
  });

  group(
    'UT7 -- the index is one-sided; getting better cannot look like decline',
    () {
      test('an all-round improvement gives a zero index', () {
        final scores = scoresFor({
          'delayed_recall': 2.0,
          'speaking_rate': 2.0,
          'pause_ratio': -2.0,
          'spiral_rmse': -2.0,
          'tremor_index': -2.0,
        });
        expect(scores.values.every((score) => score < 0.0), isTrue);
        expect(deviationIndex(scores), 0.0);
      });

      test('improving one domain cannot mask another declining', () {
        final declining = indexFor({'delayed_recall': -4.0});
        final mixed = indexFor({
          'delayed_recall': -4.0,
          'spiral_rmse': -6.0,
          'tremor_index': -6.0,
        });
        expect(mixed, closeTo(declining, 1e-12));
      });

      test('the index is never negative', () {
        for (final sds in [-5.0, -2.0, 0.0, 2.0, 5.0]) {
          expect(indexFor({'delayed_recall': sds}), greaterThanOrEqualTo(0.0));
        }
      });

      test('the index grows with the size of the decline', () {
        final indices = [
          for (final sds in [1.0, 2.0, 3.0, 4.0])
            indexFor({'delayed_recall': -sds}),
        ];
        final sorted = List<double>.of(indices)..sort();
        expect(indices, sorted);
        expect(indices.first, lessThan(indices.last));
      });

      test(
        'a pure single-domain deviation is that domain weight times its score',
        () {
          final scores = scoresFor({'spiral_rmse': 4.0, 'tremor_index': 4.0});
          final expected =
              kDomainWeights[Domain.motor]! * scores[Domain.motor]!;
          expect(deviationIndex(scores), closeTo(expected, 1e-12));
        },
      );
    },
  );

  group(
    'UT8 -- the explanation is exact, so the shares must total exactly 1',
    () {
      test('contributions sum to one for a single-domain decline', () {
        final shares = contributions(scoresFor({'delayed_recall': -4.0}));
        expect(shares.values.reduce((a, b) => a + b), closeTo(1.0, 1e-12));
      });

      test('contributions sum to one for a mixed decline', () {
        final shares = contributions(
          scoresFor({
            'delayed_recall': -3.0,
            'speaking_rate': -2.0,
            'spiral_rmse': 2.0,
          }),
        );
        expect(shares.values.reduce((a, b) => a + b), closeTo(1.0, 1e-12));
      });

      test(
        'contributions fall back to the weights with no deviation at all',
        () {
          final shares = contributions({
            for (final domain in Domain.values) domain: 0.0,
          });
          expect(shares.values.reduce((a, b) => a + b), closeTo(1.0, 1e-12));
          for (final domain in Domain.values) {
            expect(shares[domain], kDomainWeights[domain]);
          }
        },
      );

      test('contributions sum to one when everything improved', () {
        final shares = contributions({
          for (final domain in Domain.values) domain: -3.0,
        });
        expect(shares.values.reduce((a, b) => a + b), closeTo(1.0, 1e-12));
      });

      test('an improving domain contributes nothing', () {
        final shares = contributions(
          scoresFor({
            'delayed_recall': -4.0,
            'spiral_rmse': -5.0,
            'tremor_index': -5.0,
          }),
        );
        expect(shares[Domain.motor], 0.0);
        expect(shares[Domain.cognitive], greaterThan(0.0));
      });

      test('a share equals the weighted score over the index, exactly', () {
        final scores = scoresFor({
          'delayed_recall': -3.0,
          'pause_ratio': 3.0,
          'tremor_index': 3.0,
        });
        final index = deviationIndex(scores);
        final shares = contributions(scores);
        for (final domain in Domain.values) {
          final expected =
              kDomainWeights[domain]! *
              (scores[domain]! > 0 ? scores[domain]! : 0.0) /
              index;
          expect(shares[domain], closeTo(expected, 1e-12), reason: domain.key);
        }
      });

      test('the top contributor names the declining domain', () {
        final scores = scoresFor({'spiral_rmse': 6.0, 'tremor_index': 6.0});
        expect(topContributor(scores), Domain.motor);
      });

      test('percentages always total one hundred', () {
        final shares = contributions(
          scoresFor({
            'delayed_recall': -5.0,
            'pause_ratio': 3.0,
            'tremor_index': 2.0,
          }),
        );
        final percentages = contributionPercentages(shares);
        expect(percentages.values.reduce((a, b) => a + b), 100);
      });

      test(
        'percentages of an even three-way split still total one hundred',
        () {
          final shares = {for (final domain in Domain.values) domain: 1 / 3};
          expect(
            contributionPercentages(shares).values.reduce((a, b) => a + b),
            100,
          );
        },
      );

      test('percentages of an uneven split still total one hundred', () {
        final shares = {
          Domain.cognitive: 0.5,
          Domain.speech: 0.3,
          Domain.motor: 0.2,
        };
        expect(
          contributionPercentages(shares).values.reduce((a, b) => a + b),
          100,
        );
      });
    },
  );
}
