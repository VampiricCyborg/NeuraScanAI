/// The eighteen features, and calibrating the thirteen a baseline test cannot measure.
///
/// Mirrors `engine_lab/tests/test_extended.py`. A baseline test has three steps, so it supplies
/// only the five core features. The other thirteen come from steps only a full test has. They
/// get their baseline from the user's first few full tests, and until then they are reported
/// as raw values and left out of the deviation index. These tests pin that behaviour, and the
/// scoring rules that let a test be scored on whichever features have a baseline.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:neurascan_ai/engine/baseline.dart';
import 'package:neurascan_ai/engine/constants.dart';
import 'package:neurascan_ai/engine/features.dart';
import 'package:neurascan_ai/engine/scoring.dart';
import 'package:neurascan_ai/engine/screening_engine.dart';

import 'engine_test_support.dart';

void main() {
  /// Which features each of the eight tests yields.
  const tests = <String, List<String>>{
    'word memory': ['immediate_recall', 'delayed_recall'],
    'reaction time': ['reaction_median', 'reaction_cv'],
    'speech description': ['speaking_rate', 'pause_ratio'],
    'spiral tracing': ['spiral_rmse', 'tremor_index'],
    'typing rhythm': ['inter_key_interval', 'inter_key_cv'],
    'trail-making': ['completion_time', 'error_count', 'switch_cost'],
    'finger tapping': ['tap_rate', 'tap_interval_cv', 'fatigue_decay'],
    'verbal fluency': ['valid_word_count', 'fluency_half_ratio'],
  };

  group('the feature table', () {
    test('there are eighteen features', () {
      expect(kFeatureKeys, hasLength(18));
      expect(kFeatureKeys.toSet(), hasLength(18));
    });

    test('every test is covered, in test order, and nothing else', () {
      final listed = [for (final keys in tests.values) ...keys];
      expect(kFeatureKeys, listed);
    });

    test('the core features are the three baseline steps', () {
      expect(kCoreFeatureKeys.toSet(), {
        'delayed_recall',
        'speaking_rate',
        'pause_ratio',
        'spiral_rmse',
        'tremor_index',
      });
    });

    test('core and extended partition the features', () {
      expect({
        ...kCoreFeatureKeys,
        ...kExtendedFeatureKeys,
      }, kFeatureKeys.toSet());
      expect(
        kCoreFeatureKeys.toSet().intersection(kExtendedFeatureKeys.toSet()),
        isEmpty,
      );
      expect(kExtendedFeatureKeys, hasLength(13));
    });

    test('every domain has features', () {
      for (final domain in Domain.values) {
        expect(specsFor(domain), isNotEmpty, reason: domain.key);
      }
    });

    test('there are four areas, typing being the interaction one', () {
      expect(Domain.values.map((d) => d.key).toSet(), {
        'cognitive',
        'speech',
        'motor',
        'interaction',
      });
      for (final key in ['inter_key_interval', 'inter_key_cv']) {
        expect(kSpecByKey[key]!.domain, Domain.interaction);
      }
    });

    test('the direction of each feature', () {
      const lowerIsWorse = {
        'immediate_recall',
        'delayed_recall',
        'speaking_rate',
        'tap_rate',
        'valid_word_count',
        'fluency_half_ratio',
      };
      for (final spec in kFeatureSpecs) {
        expect(
          spec.direction,
          lowerIsWorse.contains(spec.key)
              ? Direction.lowerIsWorse
              : Direction.higherIsWorse,
          reason: spec.key,
        );
      }
    });

    test('the nominal and spread tables match the features', () {
      expect(kNominal.keys.toSet(), kFeatureKeys.toSet());
      expect(kWithinSd.keys.toSet(), kFeatureKeys.toSet());
      for (final spec in kFeatureSpecs) {
        expect(kWithinSd[spec.key], spec.typicalDaySd, reason: spec.key);
      }
    });

    test('only the figures from the report\'s Table A.2 are unflagged', () {
      expect(
        {
          for (final spec in kFeatureSpecs)
            if (!spec.provisional) spec.key,
        },
        {
          'delayed_recall',
          'reaction_median',
          'reaction_cv',
          'speaking_rate',
          'pause_ratio',
          'spiral_rmse',
          'tremor_index',
          'inter_key_interval',
          'inter_key_cv',
        },
      );
    });

    test('the domain weights sum to one', () {
      expect(
        kDomainWeights.values.reduce((a, b) => a + b),
        closeTo(1.0, 1e-12),
      );
    });
  });

  group('a partial baseline', () {
    test('fit from baseline tests covers only the core', () {
      final baseline = Baseline.fit(variedBaselineSessions());
      expect(baseline.median.keys.toSet(), kCoreFeatureKeys.toSet());
      expect(baseline.isComplete, isFalse);
    });

    test('fit ignores extended features a session happens to carry', () {
      final baseline = Baseline.fit([
        for (var i = 0; i < 3; i++) makeFullSession(),
      ]);
      expect(baseline.median.keys.toSet(), kCoreFeatureKeys.toSet());
    });

    test('the pending keys are the extended ones in order', () {
      expect(
        Baseline.fit(variedBaselineSessions()).pendingKeys,
        kExtendedFeatureKeys,
      );
    });

    test('extending with enough full tests completes it', () {
      final extended = Baseline.fit(variedBaselineSessions())
          .extended(variedFullSessions(3), required: 3);
      expect(extended.isComplete, isTrue);
      expect(extended.pendingKeys, isEmpty);
      expect(extended.median['reaction_median'], closeTo(320.0, 1e-9));
    });

    test('extending leaves the core untouched', () {
      final baseline = Baseline.fit(variedBaselineSessions());
      final extended = baseline.extended(variedFullSessions(3), required: 3);
      for (final key in kCoreFeatureKeys) {
        expect(extended.median[key], baseline.median[key]);
        expect(extended.scale[key], baseline.scale[key]);
      }
      expect(extended.sessionCount, baseline.sessionCount);
    });

    test('too few values leave a feature pending', () {
      final extended = Baseline.fit(variedBaselineSessions())
          .extended(variedFullSessions(2), required: 3);
      expect(extended.isComplete, isFalse);
      expect(extended.pendingKeys.toSet(), kExtendedFeatureKeys.toSet());
    });

    test('a feature is fixed from the first values only', () {
      // Later tests must not move a baseline once it is set.
      final extended = Baseline.fit(variedBaselineSessions()).extended([
        ...variedFullSessions(3),
        for (var i = 0; i < 5; i++)
          makeFullSession(overrides: {'reaction_median': 900.0}),
      ], required: 3);
      expect(extended.median['reaction_median'], closeTo(320.0, 1e-9));
    });

    test('a test that lacks a feature does not count for it', () {
      final full = variedFullSessions(3);
      final without = Map<String, double>.of(full[1].features)
        ..remove('inter_key_interval');
      final sessions = [full[0], EngineSession(features: without), full[2]];
      final extended = Baseline.fit(variedBaselineSessions())
          .extended(sessions, required: 3);
      expect(extended.median.containsKey('inter_key_interval'), isFalse);
      expect(extended.median.containsKey('reaction_median'), isTrue);
    });

    test('extended baselines get the same spread floor', () {
      final extended = Baseline.fit(
        variedBaselineSessions(),
      ).extended([for (var i = 0; i < 3; i++) makeFullSession()], required: 3);
      for (final key in kExtendedFeatureKeys) {
        expect(
          extended.scale[key],
          greaterThanOrEqualTo(
            kPriorScaleFloorFraction * kSpecByKey[key]!.typicalDaySd - 1e-12,
          ),
          reason: key,
        );
      }
    });

    test('a partial baseline round-trips through JSON', () {
      final baseline = Baseline.fit(variedBaselineSessions());
      final restored = Baseline.fromJson(baseline.toJson());
      expect(restored.pendingKeys, baseline.pendingKeys);
    });
  });

  group('scoring on whatever has a baseline', () {
    final partial = Baseline.fit(variedBaselineSessions());
    final complete = partial.extended(variedFullSessions(3), required: 3);

    test('a feature without a baseline is left out', () {
      final scores = domainScoresFrom(makeFullSession().features, partial);
      expect(scores.containsKey(Domain.interaction), isFalse);
      expect(scores.keys.toSet(), {
        Domain.cognitive,
        Domain.speech,
        Domain.motor,
      });
    });

    test('weights are re-normalised over the domains present', () {
      final weights = normalisedWeights([
        Domain.cognitive,
        Domain.speech,
        Domain.motor,
      ]);
      expect(weights.values.reduce((a, b) => a + b), closeTo(1.0, 1e-12));
      expect(weights[Domain.cognitive], closeTo(0.35 / 0.85, 1e-12));
      expect(
        weights[Domain.speech]! / weights[Domain.motor]!,
        closeTo(1, 1e-12),
      );
    });

    test('all four domains give the configured weights', () {
      final weights = normalisedWeights(Domain.values);
      for (final domain in Domain.values) {
        expect(weights[domain], closeTo(kDomainWeights[domain]!, 1e-12));
      }
    });

    test('no domains give no weights', () {
      expect(normalisedWeights(const []), isEmpty);
    });

    test('a missing domain does not pull the index towards zero', () {
      final session = makeFullSession(
        jitter: {'spiral_rmse': 4.0, 'tremor_index': 4.0},
      );
      final features = Map<String, double>.of(session.features)
        ..remove('inter_key_interval')
        ..remove('inter_key_cv');

      final scores = domainScoresFrom(features, complete);
      expect(scores.containsKey(Domain.interaction), isFalse);

      final weights = normalisedWeights(scores.keys);
      var expected = 0.0;
      var unnormalised = 0.0;
      scores.forEach((domain, score) {
        expected += weights[domain]! * (score > 0 ? score : 0.0);
        unnormalised += kDomainWeights[domain]! * (score > 0 ? score : 0.0);
      });
      expect(deviationIndex(scores), closeTo(expected, 1e-12));
      // Counting the missing area as zero would have scaled it by 0.85.
      expect(deviationIndex(scores), greaterThan(unnormalised));
    });

    test('the same decline reads the same before and after calibration', () {
      final session = makeSession(
        jitter: {'delayed_recall': -4.0, 'spiral_rmse': 4.0},
      );
      expect(
        deviationIndex(domainScoresFrom(session.features, partial)),
        closeTo(
          deviationIndex(domainScoresFrom(session.features, complete)),
          1e-12,
        ),
      );
    });

    test('contributions always name every domain', () {
      final shares = contributions(
        domainScoresFrom(
          makeSession(jitter: {'delayed_recall': -4.0}).features,
          partial,
        ),
      );
      expect(shares.keys.toSet(), Domain.values.toSet());
      expect(shares[Domain.interaction], 0.0);
      expect(shares.values.reduce((a, b) => a + b), closeTo(1.0, 1e-12));
    });

    test('a steady test falls back to the normalised weights', () {
      final shares = contributions(
        domainScoresFrom(
          makeSession(jitter: {'delayed_recall': 3.0}).features,
          partial,
        ),
      );
      expect(shares.values.reduce((a, b) => a + b), closeTo(1.0, 1e-12));
      expect(shares[Domain.interaction], 0.0);
    });
  });

  group('feature contributions', () {
    final complete = Baseline.fit(variedBaselineSessions())
        .extended(variedFullSessions(3), required: 3);

    Map<String, double> partsFor(EngineSession session) =>
        featureContributions(session.features, complete.median, complete.scale);

    test('they add up to the index', () {
      final session = makeFullSession(
        jitter: {
          'delayed_recall': -3.0,
          'reaction_median': 2.0,
          'tap_rate': -2.0,
          'inter_key_cv': 3.0,
        },
      );
      final index = deviationIndex(
        domainScoresFrom(session.features, complete),
      );
      expect(
        partsFor(session).values.reduce((a, b) => a + b),
        closeTo(index, 1e-12),
      );
    });

    test('the declining feature leads', () {
      final parts = partsFor(makeFullSession(jitter: {'tap_rate': -5.0}));
      final leader = parts.entries.reduce((a, b) => a.value >= b.value ? a : b);
      expect(leader.key, 'tap_rate');
    });

    test('a feature offsetting a decline is negative', () {
      final parts = partsFor(
        makeFullSession(
          jitter: {'delayed_recall': -5.0, 'immediate_recall': 2.0},
        ),
      );
      expect(parts['delayed_recall']!, greaterThan(0.0));
      expect(parts['immediate_recall']!, lessThan(0.0));
    });

    test('a domain that is not worsening contributes nothing', () {
      final parts = partsFor(
        makeFullSession(jitter: {'tap_rate': 4.0, 'delayed_recall': -4.0}),
      );
      expect(parts.containsKey('tap_rate'), isFalse);
      expect(parts.containsKey('spiral_rmse'), isFalse);
    });

    test('only features with a baseline appear', () {
      final partial = Baseline.fit(variedBaselineSessions());
      final session = makeFullSession(
        jitter: {'reaction_median': 5.0, 'delayed_recall': -3.0},
      );
      final parts = featureContributions(
        session.features,
        partial.median,
        partial.scale,
      );
      expect(parts.containsKey('reaction_median'), isFalse);
      expect(parts.containsKey('delayed_recall'), isTrue);
    });
  });

  group('the engine calibrates', () {
    ScreeningEngine ready() {
      final engine = ScreeningEngine();
      feedBaseline(engine);
      expect(engine.baselineReady, isTrue);
      return engine;
    }

    test('a fresh baseline is partial', () {
      final engine = ready();
      expect(engine.baseline!.isComplete, isFalse);
      expect(engine.calibrationCollected, 0);
    });

    test('the first full tests are scored on the core only', () {
      final engine = ready();
      final result = engine.update(makeFullSession(sessionId: 'f1'));
      expect(result.status.isScored, isTrue);
      expect(result.domains!.containsKey(Domain.interaction), isFalse);
      expect(engine.calibrationCollected, 1);
      expect(engine.baseline!.isComplete, isFalse);
    });

    test('the third full test completes the baseline', () {
      final engine = ready();
      final results = [
        for (final s in variedFullSessions(kExtensionTests)) engine.update(s),
      ];
      expect(engine.baseline!.isComplete, isTrue);
      // Scored with the new features: the last test now has all four areas.
      expect(results.last.domains!.keys.toSet(), Domain.values.toSet());
      expect(results.first.domains!.containsKey(Domain.interaction), isFalse);
    });

    test('later full tests cannot move the calibrated baseline', () {
      final engine = ready();
      variedFullSessions(kExtensionTests).forEach(engine.update);
      final before = Map<String, double>.of(engine.baseline!.median);
      for (var i = 0; i < 4; i++) {
        engine.update(makeFullSession(overrides: {'reaction_median': 900.0}));
      }
      expect(engine.baseline!.median, before);
    });

    test('a tired full test does not count towards calibration', () {
      final engine = ready();
      engine.update(
        makeFullSession(
          confounded: true,
          overrides: {'reaction_median': 900.0},
        ),
      );
      expect(engine.calibrationCollected, 0);
    });

    test('an invalid full test does not count', () {
      final engine = ready();
      engine.update(makeFullSession(valid: false));
      expect(engine.calibrationCollected, 0);
    });

    test('a baseline-style test does not count', () {
      final engine = ready();
      engine.update(makeSession());
      expect(engine.calibrationCollected, 0);
    });

    test('calibration does not start before the baseline is frozen', () {
      final engine = ScreeningEngine();
      engine.update(makeFullSession());
      expect(engine.calibrationCollected, 0);
    });

    test('a feature missing from a test delays only that feature', () {
      final engine = ready();
      final sessions = variedFullSessions(3);
      final first = Map<String, double>.of(sessions[0].features)
        ..remove('inter_key_interval');
      engine.update(EngineSession(features: first));
      engine.update(sessions[1]);
      engine.update(sessions[2]);
      expect(
        engine.baseline!.median.containsKey('inter_key_interval'),
        isFalse,
      );
      expect(engine.baseline!.median.containsKey('reaction_median'), isTrue);
      // The fourth test supplies the third typing value.
      engine.update(makeFullSession(overrides: {'inter_key_interval': 265.0}));
      expect(engine.baseline!.median.containsKey('inter_key_interval'), isTrue);
    });

    test('replaying stored tests rebuilds the same calibration', () {
      // The pool is not serialised: it is replayed from the stored tests.
      final live = ready();
      final stored = variedFullSessions(kExtensionTests);
      stored.forEach(live.update);

      final restored = ScreeningEngine(
        baseline: Baseline.fit(variedBaselineSessions()),
      )..calibrateFrom(stored);

      for (final key in kFeatureKeys) {
        expect(
          restored.baseline!.median[key],
          closeTo(live.baseline!.median[key]!, 1e-12),
          reason: key,
        );
        expect(
          restored.baseline!.scale[key],
          closeTo(live.baseline!.scale[key]!, 1e-12),
          reason: key,
        );
      }
    });

    test('replay does not touch the smoothing state', () {
      final engine = ScreeningEngine(
        baseline: Baseline.fit(variedBaselineSessions()),
      )..calibrateFrom(variedFullSessions(3));
      expect(engine.ewma, 0.0);
      expect(engine.run, 0);
    });

    test('a complete baseline ignores further calibration', () {
      final engine = ready();
      variedFullSessions(3).forEach(engine.update);
      final collected = engine.calibrationCollected;
      engine.update(makeFullSession());
      expect(engine.calibrationCollected, collected);
    });

    test('the serialised state reports calibration', () {
      final engine = ready();
      engine.update(makeFullSession());
      expect(engine.toJson()['calibrationCollected'], 1);
    });
  });

  test('a session reports only missing core features', () {
    final incomplete = EngineSession(features: const {'delayed_recall': 0.7});
    expect(
      incomplete.missingFeatures().toSet(),
      kCoreFeatureKeys.toSet()..remove('delayed_recall'),
    );
    expect(makeFullSession().missingFeatures(), isEmpty);
  });
}
