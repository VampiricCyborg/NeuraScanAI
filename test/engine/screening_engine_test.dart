/// UT9 through UT12 -- context gating, persistence and invalid sessions.
///
/// Mirrors `engine_lab/tests/test_engine.py`, covering Table 9.2 rows UT9 (a
/// confounded session leaves the EWMA unchanged), UT10-11 (one bad session does
/// not alert but a sustained deviation does) and UT12 (an invalid session is
/// ignored).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:neurascan_ai/engine/constants.dart';
import 'package:neurascan_ai/engine/features.dart';
import 'package:neurascan_ai/engine/screening_engine.dart';

import 'engine_test_support.dart';

void main() {
  group('UT9 -- a self-reported bad day must not move the smoothed trend', () {
    test('a confounded session leaves the EWMA unchanged', () {
      final engine = readyEngine();
      final before = engine.ewma;
      final result =
          engine.update(makeSession(confounded: true, jitter: kSevere));
      expect(result.status, ScreeningStatus.excludedContext);
      expect(engine.ewma, before);
    });

    test('a confounded session leaves the run length unchanged', () {
      final engine = readyEngine();
      engine.update(makeSession(jitter: kSevere));
      final runBefore = engine.run;
      engine.update(makeSession(confounded: true));
      expect(engine.run, runBefore);
    });

    test('a confounded result carries no index', () {
      final engine = readyEngine();
      final result = engine.update(makeSession(confounded: true));
      expect(result.index, isNull);
      expect(result.isScored, isFalse);
    });

    test('a bad day in the middle of a decline does not reset the count', () {
      final engine = readyEngine();
      engine.update(makeSession(jitter: kSevere));
      engine.update(makeSession(jitter: kSevere));
      engine.update(makeSession(confounded: true));
      final result = engine.update(makeSession(jitter: kSevere));
      expect(result.status, ScreeningStatus.notableDeviation);
    });

    test('gating can be switched off for ablation', () {
      final engine = readyEngine(useContext: false);
      final before = engine.ewma;
      final result =
          engine.update(makeSession(confounded: true, jitter: kSevere));
      expect(result.isScored, isTrue);
      expect(engine.ewma, greaterThan(before));
    });
  });

  group('UT10 -- a single spike is not a trend', () {
    test('one severe session does not raise a notable deviation (TC8)', () {
      final engine = readyEngine();
      final result = engine.update(makeSession(jitter: kSevere));
      expect(result.status, isNot(ScreeningStatus.notableDeviation));
    });

    test('two severe sessions still do not alert', () {
      final engine = readyEngine();
      engine.update(makeSession(jitter: kSevere));
      final result = engine.update(makeSession(jitter: kSevere));
      expect(result.status, isNot(ScreeningStatus.notableDeviation));
      expect(engine.run, lessThan(kDefaultPersistence));
    });

    test('the EWMA damps a single spike to lambda of the gap', () {
      final engine = readyEngine();
      final result = engine.update(makeSession(jitter: kSevere));
      expect(result.ewma, closeTo(kEwmaLambda * result.index!, 1e-12));
      expect(result.ewma, lessThan(result.index!));
    });

    test('a spike followed by recovery returns to stable', () {
      final engine = readyEngine();
      engine.update(makeSession(jitter: kSevere));
      SessionResult? result;
      for (var i = 0; i < 12; i++) {
        result = engine.update(makeSession());
      }
      expect(result!.status, ScreeningStatus.stable);
      expect(engine.run, 0);
    });

    test('the run resets when the index falls back', () {
      final engine = readyEngine();
      engine.update(makeSession(jitter: kSevere));
      engine.update(makeSession(jitter: kSevere));
      expect(engine.run, greaterThan(0));
      for (var i = 0; i < 10; i++) {
        engine.update(makeSession());
      }
      expect(engine.run, 0);
    });

    test('with the EWMA off, a single session sets the index directly', () {
      final engine = readyEngine(useEwma: false);
      final result = engine.update(makeSession(jitter: kSevere));
      expect(result.ewma, closeTo(result.index!, 1e-12));
    });
  });

  group('UT11 -- a deviation that persists is reported', () {
    int sessionsUntilAlert(int persistence) {
      final engine = readyEngine(persistence: persistence);
      for (var i = 1; i < 30; i++) {
        if (engine.update(makeSession(jitter: kSevere)).status ==
            ScreeningStatus.notableDeviation) {
          return i;
        }
      }
      fail('no alert raised within 30 sessions');
    }

    test('repeated severe sessions eventually alert', () {
      final engine = readyEngine();
      final statuses = [
        for (var i = 0; i < 10; i++)
          engine.update(makeSession(jitter: kSevere)).status,
      ];
      expect(statuses, contains(ScreeningStatus.notableDeviation));
    });

    test('an alert needs the full persistence window', () {
      final engine = readyEngine();
      for (var i = 0; i < 15; i++) {
        final result = engine.update(makeSession(jitter: kSevere));
        if (result.status == ScreeningStatus.notableDeviation) {
          expect(result.run, greaterThanOrEqualTo(kDefaultPersistence));
          return;
        }
      }
      fail('no alert raised within 15 sessions');
    });

    test('a shorter persistence window alerts sooner', () {
      expect(sessionsUntilAlert(1), lessThan(sessionsUntilAlert(3)));
      expect(sessionsUntilAlert(3), lessThan(sessionsUntilAlert(5)));
    });

    test('a mild band sits between stable and notable', () {
      final engine = readyEngine();
      final seen = <ScreeningStatus>{
        for (var i = 0; i < 6; i++)
          engine.update(makeSession(jitter: kSevere)).status,
      };
      expect(seen, contains(ScreeningStatus.mildDeviation));
      expect(seen, contains(ScreeningStatus.notableDeviation));
    });

    test('mild means elevated but not yet persistent', () {
      // Mild covers two situations rather than one: a smoothed value between
      // the mild fraction and the threshold, and a value already over the
      // threshold whose run has not yet reached the persistence length. Both
      // mean "worth watching" rather than "this has persisted".
      final engine = readyEngine();
      var seenMild = 0;
      for (var i = 0; i < 6; i++) {
        final result = engine.update(makeSession(jitter: kSevere));
        if (result.status == ScreeningStatus.mildDeviation) {
          seenMild++;
          expect(result.ewma, greaterThanOrEqualTo(kMildFraction * engine.threshold));
          expect(result.run, lessThan(engine.persistence));
        }
      }
      expect(seenMild, greaterThan(0), reason: 'never passed through mild');
    });

    test('a value below the mild fraction reads as stable', () {
      final engine = readyEngine();
      final result = engine.update(makeSession());
      expect(result.ewma, lessThan(kMildFraction * engine.threshold));
      expect(result.status, ScreeningStatus.stable);
    });

    test('an alert explains which domains contributed', () {
      final engine = readyEngine();
      const cognitiveDecline = {
        'delayed_recall': -9.0,
        'reaction_median': 9.0,
        'reaction_cv': 9.0,
      };
      for (var i = 0; i < 8; i++) {
        final result = engine.update(makeSession(jitter: cognitiveDecline));
        if (result.status == ScreeningStatus.notableDeviation) {
          expect(result.contributions![Domain.cognitive], closeTo(1.0, 1e-12));
          expect(result.contributionPercent()[Domain.cognitive], 100);
          expect(result.leadingDomain, Domain.cognitive);
          return;
        }
      }
      fail('no alert raised within 8 sessions');
    });

    test('only a notable status invites the user to consult a doctor', () {
      expect(ScreeningStatus.notableDeviation.warrantsConsultation, isTrue);
      expect(ScreeningStatus.mildDeviation.warrantsConsultation, isFalse);
      expect(ScreeningStatus.stable.warrantsConsultation, isFalse);
    });

    test('no status name mentions a disease', () {
      // The app is a screening and awareness tool; the vocabulary it can use is
      // bounded by that, so this is asserted rather than left to review.
      const forbidden = [
        'alzheimer',
        'parkinson',
        'dementia',
        'disease',
        'diagnos',
        'impairment',
      ];
      for (final status in ScreeningStatus.values) {
        final key = status.key.toLowerCase();
        for (final word in forbidden) {
          expect(key.contains(word), isFalse, reason: '${status.key} / $word');
        }
      }
    });
  });

  group('UT12 -- a session that failed a gate changes nothing', () {
    test('it returns the invalid status', () {
      final engine = readyEngine();
      final result = engine.update(makeSession(valid: false, jitter: kSevere));
      expect(result.status, ScreeningStatus.invalidSession);
    });

    test('it leaves the EWMA unchanged', () {
      final engine = readyEngine();
      final before = engine.ewma;
      engine.update(makeSession(valid: false, jitter: kSevere));
      expect(engine.ewma, before);
    });

    test('it leaves the run unchanged', () {
      final engine = readyEngine();
      engine.update(makeSession(jitter: kSevere));
      final runBefore = engine.run;
      engine.update(makeSession(valid: false));
      expect(engine.run, runBefore);
    });

    test('it is not pooled into the baseline', () {
      final engine = ScreeningEngine();
      engine.update(makeSession());
      engine.update(makeSession());
      for (var i = 0; i < 6; i++) {
        engine.update(makeSession(valid: false));
      }
      expect(engine.baselineReady, isFalse);
    });

    test('it still counts as familiarisation', () {
      // A failed attempt still taught the user what the task looks like.
      final engine = ScreeningEngine();
      engine.update(makeSession(valid: false));
      engine.update(makeSession(valid: false));
      expect(engine.sessionsSeen, 2);
      for (var i = 0; i < 6; i++) {
        engine.update(makeSession(sessionId: '$i'));
      }
      expect(engine.baselineReady, isTrue);
    });
  });

  group('the engine must survive an app restart without losing its place', () {
    test('the state holds the baseline and the smoothing state', () {
      final engine = readyEngine();
      engine.update(makeSession(jitter: kSevere));
      final state = engine.toJson();
      expect(state['baseline'], isNotNull);
      expect(state['ewma'], engine.ewma);
      expect(state['run'], engine.run);
    });

    test('restoring reproduces the next result exactly', () {
      final engine = readyEngine();
      engine.update(makeSession(jitter: kSevere));

      final restored = ScreeningEngine.fromJson(engine.toJson());
      final fromOriginal = engine.update(makeSession(jitter: kSevere));
      final fromRestored = restored.update(makeSession(jitter: kSevere));

      expect(fromRestored.status, fromOriginal.status);
      expect(fromRestored.index, closeTo(fromOriginal.index!, 1e-12));
      expect(fromRestored.ewma, closeTo(fromOriginal.ewma!, 1e-12));
      expect(fromRestored.run, fromOriginal.run);
    });

    test('the state before a baseline reports no baseline', () {
      final engine = ScreeningEngine();
      engine.update(makeSession());
      expect(engine.toJson()['baseline'], isNull);
    });

    test('a session result round-trips through JSON', () {
      final engine = readyEngine();
      final result = engine.update(makeSession(jitter: kSevere));
      final restored = SessionResult.fromJson(result.toJson());

      expect(restored.status, result.status);
      expect(restored.index, closeTo(result.index!, 1e-12));
      expect(restored.ewma, closeTo(result.ewma!, 1e-12));
      expect(restored.run, result.run);
      for (final domain in Domain.values) {
        expect(restored.domains![domain], closeTo(result.domains![domain]!, 1e-12));
        expect(
          restored.contributions![domain],
          closeTo(result.contributions![domain]!, 1e-12),
        );
      }
    });

    test('a building result round-trips through JSON', () {
      final engine = ScreeningEngine();
      engine.update(makeSession());
      engine.update(makeSession());
      final result = engine.update(makeSession(sessionId: 'first-pooled'));
      final restored = SessionResult.fromJson(result.toJson());

      expect(restored.status, ScreeningStatus.buildingBaseline);
      expect(restored.baselineCollected, 1);
      expect(restored.sessionId, 'first-pooled');
    });

    test('status keys round-trip', () {
      for (final status in ScreeningStatus.values) {
        expect(ScreeningStatus.fromKey(status.key), status);
      }
    });

    test('domain keys round-trip', () {
      for (final domain in Domain.values) {
        expect(Domain.fromKey(domain.key), domain);
      }
    });
  });
}
