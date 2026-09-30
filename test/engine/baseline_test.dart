/// UT3, UT4 and UT5 -- building the personal baseline.
///
/// Mirrors `engine_lab/tests/test_baseline.py`, covering Table 9.2 rows UT3
/// (familiarisation sessions excluded), UT4 (the median resists an outlier) and
/// UT5 (the scale floor prevents division by zero).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:neurascan_ai/engine/baseline.dart';
import 'package:neurascan_ai/engine/constants.dart';
import 'package:neurascan_ai/engine/features.dart';
import 'package:neurascan_ai/engine/screening_engine.dart';

import 'engine_test_support.dart';

void main() {
  group(
    'UT3 -- the first sessions are discarded so practice is not baked in',
    () {
      test('the baseline is not frozen before enough sessions', () {
        final engine = ScreeningEngine();
        for (
          var i = 0;
          i < kFamiliarisationSessions + kBaselineSessions - 1;
          i++
        ) {
          final result = engine.update(makeSession(sessionId: '$i'));
          expect(result.status, ScreeningStatus.buildingBaseline);
        }
        expect(engine.baselineReady, isFalse);
      });

      test('the baseline freezes on the eighth session (TC7)', () {
        final engine = ScreeningEngine();
        for (var i = 0; i < kFamiliarisationSessions + kBaselineSessions; i++) {
          engine.update(makeSession(sessionId: '$i'));
        }
        expect(engine.baselineReady, isTrue);
        expect(engine.baseline!.sessionCount, kBaselineSessions);
      });

      test('familiarisation values never reach the baseline medians', () {
        final engine = ScreeningEngine();
        engine.update(makeSession(overrides: {'delayed_recall': 0.10}));
        engine.update(makeSession(overrides: {'delayed_recall': 0.10}));
        for (var i = 0; i < kBaselineSessions; i++) {
          engine.update(makeSession(overrides: {'delayed_recall': 0.80}));
        }
        expect(engine.baseline!.median['delayed_recall'], closeTo(0.80, 1e-9));
      });

      test('progress climbs from zero to one', () {
        final engine = ScreeningEngine();
        engine.update(makeSession());
        engine.update(makeSession());
        expect(engine.baselineProgress, 0.0);

        final seen = <double>[];
        for (var i = 0; i < kBaselineSessions; i++) {
          seen.add(
            engine.update(makeSession(sessionId: '$i')).baselineProgress!,
          );
        }
        expect(seen.first, closeTo(1 / kBaselineSessions, 1e-9));
        expect(seen.last, closeTo(1.0, 1e-9));
        expect(engine.baselineProgress, 1.0);
        expect(engine.baselineRemaining, 0);
      });

      test('a tired day must not define what normal looks like', () {
        final engine = ScreeningEngine();
        engine.update(makeSession());
        engine.update(makeSession());
        for (var i = 0; i < kBaselineSessions; i++) {
          engine.update(
            makeSession(confounded: true, overrides: {'delayed_recall': 0.3}),
          );
        }
        expect(engine.baselineReady, isFalse);

        for (var i = 0; i < kBaselineSessions; i++) {
          engine.update(makeSession(overrides: {'delayed_recall': 0.8}));
        }
        expect(engine.baseline!.median['delayed_recall'], closeTo(0.8, 1e-9));
      });
    },
  );

  group(
    'UT4 -- one unusual session cannot drag the centre of the baseline',
    () {
      test('the median ignores a single extreme value', () {
        const clean = [300.0, 310.0, 320.0, 330.0, 340.0, 350.0];
        const polluted = [300.0, 310.0, 320.0, 330.0, 340.0, 5000.0];
        expect(median(clean), 325.0);
        expect(median(polluted), 325.0);
      });

      test('a mean would have moved a long way, which is why this matters', () {
        const polluted = [300.0, 310.0, 320.0, 330.0, 340.0, 5000.0];
        final mean = polluted.reduce((a, b) => a + b) / polluted.length;
        expect(mean, greaterThan(1000.0));
        expect(median(polluted), 325.0);
      });

      test('the baseline median survives one bad session', () {
        const values = [300.0, 310.0, 320.0, 330.0, 340.0, 5000.0];
        final sessions = [
          for (var i = 0; i < values.length; i++)
            makeSession(
              sessionId: '$i',
              overrides: {'reaction_median': values[i]},
            ),
        ];
        expect(
          Baseline.fit(sessions).median['reaction_median'],
          closeTo(325.0, 1e-9),
        );
      });

      test('the MAD is the median of the absolute deviations', () {
        const values = [1.0, 2.0, 3.0, 4.0, 100.0];
        expect(median(values), 3.0);
        expect(medianAbsoluteDeviation(values), 1.0);
      });

      test('the median averages the middle pair on an even-length list', () {
        expect(median(const [1.0, 2.0, 3.0, 4.0]), 2.5);
      });

      test('the median of an empty list is a programming error', () {
        expect(() => median(const []), throwsArgumentError);
      });
    },
  );

  group(
    'UT5 -- a perfectly consistent baseline must not produce infinite z',
    () {
      test('identical values still give a positive scale', () {
        final values = List<double>.filled(kBaselineSessions, 0.75);
        expect(medianAbsoluteDeviation(values), 0.0);
        final scale = robustScale(values);
        expect(scale, greaterThan(0.0));
        expect(scale, closeTo(kScaleFloorFraction * 0.75, 1e-12));
      });

      test('a z-score stays finite on a flat baseline', () {
        final sessions = [
          for (var i = 0; i < kBaselineSessions; i++)
            makeSession(sessionId: '$i'),
        ];
        final z = Baseline.fit(sessions).z('delayed_recall', 0.50);
        expect(z.isFinite, isTrue);
        expect(z, lessThan(0.0));
      });

      test('an all-zero feature still yields a usable scale', () {
        final scale = robustScale(List<double>.filled(kBaselineSessions, 0.0));
        expect(scale, greaterThan(0.0));
        expect((1.0 / scale).isFinite, isTrue);
      });

      test('real spread is preferred over the floor', () {
        const values = [300.0, 310.0, 320.0, 330.0, 340.0, 350.0];
        expect(
          robustScale(values),
          closeTo(kMadToSigma * medianAbsoluteDeviation(values), 1e-9),
        );
      });

      test('the engine never divides by zero with a flat baseline', () {
        final engine = ScreeningEngine();
        engine.update(makeSession());
        engine.update(makeSession());
        for (var i = 0; i < kBaselineSessions; i++) {
          engine.update(makeSession(sessionId: '$i'));
        }
        final result = engine.update(
          makeSession(overrides: {'delayed_recall': 0.70}),
        );
        expect(result.index!.isFinite, isTrue);
        expect(result.ewma!.isFinite, isTrue);
      });
    },
  );

  group('Baseline.fit contract', () {
    test('rejects an empty pool', () {
      expect(() => Baseline.fit(const []), throwsArgumentError);
    });

    test('rejects a session missing a feature', () {
      final incomplete = Map<String, double>.of(kNominal)
        ..remove('tremor_index');
      final sessions = List.generate(
        kBaselineSessions,
        (_) => EngineSession(features: incomplete),
      );
      expect(() => Baseline.fit(sessions), throwsArgumentError);
    });

    test('round-trips through JSON', () {
      final baseline = Baseline.fit(variedBaselineSessions());
      final restored = Baseline.fromJson(baseline.toJson());
      for (final key in kFeatureKeys) {
        expect(restored.median[key], closeTo(baseline.median[key]!, 1e-12));
        expect(restored.scale[key], closeTo(baseline.scale[key]!, 1e-12));
      }
      expect(restored.sessionCount, baseline.sessionCount);
    });

    test('holds twenty-odd numbers, small enough to sync as one document', () {
      final baseline = Baseline.fit(variedBaselineSessions());
      expect(baseline.median, hasLength(9));
      expect(baseline.scale, hasLength(9));
    });

    test('a session reports the features it is missing', () {
      final incomplete = Map<String, double>.of(kNominal)
        ..remove('pause_ratio');
      expect(EngineSession(features: incomplete).missingFeatures(), [
        'pause_ratio',
      ]);
    });
  });
}
