/// The repository: persistence, the sync boundary, and erasure.
///
/// The privacy tests in here are the ones worth reading. The app's claim is that
/// raw signals never leave the phone, and the only way that claim stays true as the
/// code changes is if something fails when it stops being true.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:neurascan_ai/data/local_db.dart';
import 'package:neurascan_ai/data/models.dart';
import 'package:neurascan_ai/data/repository.dart';
import 'package:neurascan_ai/data/sync_service.dart';
import 'package:neurascan_ai/engine/baseline.dart';
import 'package:neurascan_ai/engine/constants.dart';
import 'package:neurascan_ai/engine/features.dart';
import 'package:neurascan_ai/engine/screening_engine.dart';

import '../engine/engine_test_support.dart';

/// Records everything handed to it, so a test can inspect the exact payload.
class RecordingSyncBackend implements SyncBackend {
  final profiles = <UserProfile>[];
  final sessions = <SessionRecord>[];
  final baselines = <String, Baseline>{};
  final reports = <String>[];
  final deleted = <String>[];

  /// When set, every call throws it.
  SyncException? failure;

  void _maybeFail() {
    final error = failure;
    if (error != null) throw error;
  }

  @override
  Future<void> upsertProfile(UserProfile profile) async {
    _maybeFail();
    profiles.add(profile);
  }

  @override
  Future<void> upsertSession(SessionRecord session) async {
    _maybeFail();
    sessions.add(session);
  }

  @override
  Future<void> upsertBaseline(String userId, Baseline baseline) async {
    _maybeFail();
    baselines[userId] = baseline;
  }

  @override
  Future<void> recordReport({
    required String userId,
    required String reportId,
    required DateTime periodStart,
    required DateTime periodEnd,
    required String status,
    required Map<String, double> contributions,
  }) async {
    _maybeFail();
    reports.add(reportId);
  }

  @override
  Future<void> deleteEverything(String userId) async {
    _maybeFail();
    deleted.add(userId);
  }
}

void main() {
  late LocalDatabase db;
  late RecordingSyncBackend backend;
  late SyncQueue queue;
  late Repository repository;

  setUp(() {
    db = LocalDatabase.forTesting();
    backend = RecordingSyncBackend();
    queue = SyncQueue(
      backend: backend,
      // Tests must not actually wait out a back-off.
      delay: (_) async {},
    );
    repository = Repository(database: db, syncQueue: queue);
  });

  tearDown(() => db.close());

  Future<UserProfile> signedUpUser({bool syncEnabled = false}) async {
    final profile = await repository.ensureProfile(
      userId: 'user-1',
      email: 'someone@example.com',
      displayName: 'Test User',
    );
    return repository.recordConsent(profile: profile, syncEnabled: syncEnabled);
  }

  SessionRecord buildSession({
    required String id,
    required SessionResult result,
    Map<String, double>? features,
    CheckIn? checkIn,
    bool valid = true,
    RecallDetail? recallDetail,
    DateTime? at,
  }) {
    final now = at ?? DateTime.utc(2026, 4, 2, 10);
    return SessionRecord(
      id: id,
      userId: 'user-1',
      startedAt: now,
      completedAt: now.add(const Duration(minutes: 4)),
      checkIn: checkIn ?? CheckIn.unremarkable(now),
      features: features ?? Map<String, double>.of(kNominal),
      valid: valid,
      status: result.status,
      index: result.index,
      ewma: result.ewma,
      run: result.run,
      domainScores: result.domains,
      contributions: result.contributions,
      recallDetail: recallDetail,
    );
  }

  group('profile', () {
    test('ensureProfile creates a row, then returns the same one', () async {
      final first = await repository.ensureProfile(userId: 'user-1');
      final second = await repository.ensureProfile(userId: 'user-1');
      expect(second.id, first.id);
      expect(second.createdAt, first.createdAt);
    });

    test('a new profile has no consent, so the gate holds', () async {
      final profile = await repository.ensureProfile(userId: 'user-1');
      expect(profile.hasCurrentConsent, isFalse);
      expect(profile.syncEnabled, isFalse);
    });

    test('recording consent satisfies the gate', () async {
      final profile = await signedUpUser();
      expect(profile.hasCurrentConsent, isTrue);

      final reloaded = await repository.loadProfile('user-1');
      expect(reloaded!.hasCurrentConsent, isTrue);
      expect(reloaded.consent!.version, ConsentRecord.currentVersion);
    });

    test('settings survive a reload', () async {
      final profile = await signedUpUser();
      await repository.saveProfile(
        profile.copyWith(
          dominantHand: DominantHand.left,
          languageCode: 'ta',
          reminderIntervalDays: 3,
          reminderEnabled: false,
        ),
      );

      final reloaded = await repository.loadProfile('user-1');
      expect(reloaded!.dominantHand, DominantHand.left);
      expect(reloaded.languageCode, 'ta');
      expect(reloaded.reminderIntervalDays, 3);
      expect(reloaded.reminderEnabled, isFalse);
    });

    test('a stale consent version reopens the gate', () async {
      // Consent to an earlier description of what the app does is not consent to a
      // later one.
      final profile = await signedUpUser();
      final stale = UserProfile(
        id: profile.id,
        createdAt: profile.createdAt,
        consent: ConsentRecord(
          version: ConsentRecord.currentVersion - 1,
          acceptedAt: DateTime.utc(2026),
          syncEnabled: false,
        ),
      );
      expect(stale.hasCurrentConsent, isFalse);
    });
  });

  group('sync is off by default', () {
    test('a session is stored but nothing is uploaded', () async {
      await signedUpUser();
      final engine = readyEngine();
      final result = engine.update(makeSession());

      await repository.saveSession(
        session: buildSession(id: 'session-1', result: result),
        engine: engine,
      );

      expect(await repository.loadSessions('user-1'), hasLength(1));
      expect(backend.sessions, isEmpty);
      expect(queue.pendingCount, 0);
    });

    test('a profile change is not uploaded', () async {
      final profile = await signedUpUser();
      await repository.saveProfile(profile.copyWith(displayName: 'Changed'));
      expect(backend.profiles, isEmpty);
    });

    test('turning sync on starts uploading later sessions', () async {
      final profile = await signedUpUser();
      await repository.recordConsent(profile: profile, syncEnabled: true);

      final engine = readyEngine();
      final result = engine.update(makeSession());
      await repository.saveSession(
        session: buildSession(id: 'session-1', result: result),
        engine: engine,
      );
      await repository.inFlightSync;

      expect(backend.sessions, hasLength(1));
    });

    test(
      'turning sync off drops what was queued rather than sending it',
      () async {
        // A user who has just withdrawn permission should not have the last few
        // sessions go up because they were already in the queue.
        final profile = await signedUpUser(syncEnabled: true);
        backend.failure = const SyncException(SyncFailure.offline);

        final engine = readyEngine();
        await repository.saveSession(
          session: buildSession(
            id: 'session-1',
            result: engine.update(makeSession()),
          ),
          engine: engine,
        );
        expect(queue.abandonedCount + queue.pendingCount, greaterThan(0));

        backend.failure = null;
        await repository.recordConsent(profile: profile, syncEnabled: false);

        expect(queue.pendingCount, 0);
        expect(queue.abandonedCount, 0);
        await repository.syncNow();
        expect(backend.sessions, isEmpty);
      },
    );
  });

  group('the sync payload carries no raw signal', () {
    test('recall words are stored locally but never uploaded', () async {
      await signedUpUser(syncEnabled: true);
      final engine = readyEngine();
      final result = engine.update(makeSession());

      await repository.saveSession(
        session: buildSession(
          id: 'session-1',
          result: result,
          recallDetail: const RecallDetail(
            listId: 2,
            recalled: ['elephant', 'harbour'],
            missed: ['ribbon'],
          ),
        ),
        engine: engine,
      );

      await repository.inFlightSync;

      final stored = (await repository.loadSessions('user-1')).single;
      expect(stored.recallDetail!.recalled, ['elephant', 'harbour']);

      final uploaded = jsonEncode(backend.sessions.single.toSyncJson());
      expect(uploaded, isNot(contains('elephant')));
      expect(uploaded, isNot(contains('recallDetail')));
    });

    test('the upload holds only derived fields', () async {
      await signedUpUser(syncEnabled: true);
      final engine = readyEngine();
      final result = engine.update(makeSession());
      await repository.saveSession(
        session: buildSession(id: 'session-1', result: result),
        engine: engine,
      );

      await repository.inFlightSync;

      final payload = backend.sessions.single.toSyncJson();
      // An allow-list rather than a deny-list: a new field added to the model has
      // to be named here before it can be uploaded, which is the point.
      expect(payload.keys.toSet(), {
        'id',
        'userId',
        'startedAt',
        'completedAt',
        'checkIn',
        'features',
        'valid',
        'status',
        'invalidReasons',
        'index',
        'ewma',
        'run',
        'domainScores',
        'contributions',
      });
    });

    test('the uploaded features are exactly the nine derived ones', () async {
      await signedUpUser(syncEnabled: true);
      final engine = readyEngine();
      await repository.saveSession(
        session: buildSession(
          id: 'session-1',
          result: engine.update(makeSession()),
        ),
        engine: engine,
      );

      await repository.inFlightSync;

      final features =
          (backend.sessions.single.toSyncJson()['features']! as Map).keys
              .toSet();
      expect(features, kFeatureKeys.toSet());
    });

    test('the payload is small enough to be cheap to sync', () async {
      // The report budgets about half a kilobyte per session. Worth asserting,
      // because a field added carelessly here is a cost the user pays on a metered
      // connection.
      await signedUpUser(syncEnabled: true);
      final engine = readyEngine();
      await repository.saveSession(
        session: buildSession(
          id: 'session-1',
          result: engine.update(makeSession()),
        ),
        engine: engine,
      );

      await repository.inFlightSync;

      final encoded = jsonEncode(backend.sessions.single.toSyncJson());
      expect(encoded.length, lessThan(1400));
    });
  });

  group('engine state', () {
    test('survives a reload without replaying history', () async {
      await signedUpUser();
      final engine = readyEngine();
      for (var i = 0; i < 4; i++) {
        final result = engine.update(makeSession(jitter: kSevere));
        await repository.saveSession(
          session: buildSession(id: 'session-$i', result: result),
          engine: engine,
        );
      }

      final reloaded = await repository.loadEngine('user-1');
      expect(reloaded.baselineReady, isTrue);
      expect(reloaded.ewma, closeTo(engine.ewma, 1e-12));
      expect(reloaded.run, engine.run);
    });

    test('a reloaded engine produces the same next result', () async {
      await signedUpUser();
      final engine = readyEngine();
      final result = engine.update(makeSession(jitter: kSevere));
      await repository.saveSession(
        session: buildSession(id: 'session-1', result: result),
        engine: engine,
      );

      final reloaded = await repository.loadEngine('user-1');
      final fromOriginal = engine.update(makeSession(jitter: kSevere));
      final fromReloaded = reloaded.update(makeSession(jitter: kSevere));

      expect(fromReloaded.status, fromOriginal.status);
      expect(fromReloaded.ewma, closeTo(fromOriginal.ewma!, 1e-12));
    });

    test('the baseline is written once and not rewritten', () async {
      await signedUpUser(syncEnabled: true);
      final engine = readyEngine();
      final firstFrozenAt = engine.baseline;
      expect(firstFrozenAt, isNotNull);

      await repository.saveEngineState('user-1', engine);
      await repository.saveEngineState('user-1', engine);
      await repository.syncNow();

      // Queued under one id, so a second write replaces rather than duplicates.
      expect(backend.baselines, hasLength(1));
    });

    test(
      'a pool that has not frozen yet is rebuilt by replaying sessions',
      () async {
        await signedUpUser();
        final engine = ScreeningEngine();
        // The practice test and two pooled ones: one short of freezing.
        const saved = kFamiliarisationSessions + kBaselineSessions - 1;
        for (var i = 0; i < saved; i++) {
          final result = engine.update(makeSession(sessionId: 'session-$i'));
          await repository.saveSession(
            session: buildSession(id: 'session-$i', result: result),
            engine: engine,
          );
        }

        final reloaded = await repository.loadEngine('user-1');
        expect(reloaded.baselineReady, isFalse);
        expect(reloaded.sessionsSeen, saved);
        // The practice test discarded, the rest pooled.
        expect(
          reloaded.baselineProgress,
          closeTo((kBaselineSessions - 1) / kBaselineSessions, 1e-12),
        );
      },
    );
  });

  group('derived views', () {
    test('only scored sessions appear in the trend', () async {
      // Plotting a confounded session would show the user a change in their trend
      // that the engine explicitly decided to ignore.
      await signedUpUser();
      final engine = readyEngine();

      final scored = engine.update(makeSession());
      await repository.saveSession(
        session: buildSession(id: 'scored', result: scored),
        engine: engine,
      );

      final confounded = engine.update(makeSession(confounded: true));
      await repository.saveSession(
        session: buildSession(
          id: 'confounded',
          result: confounded,
          checkIn: CheckIn(
            sleep: SleepQuality.poor,
            fatigue: FatigueLevel.very,
            illnessOrMedicationChange: false,
            answeredAt: DateTime.utc(2026, 4, 2, 10),
          ),
        ),
        engine: engine,
      );

      final sessions = await repository.loadSessions('user-1');
      expect(sessions, hasLength(2));
      expect(repository.deviationSeries(sessions), hasLength(1));
      expect(repository.domainSeries(sessions)[Domain.cognitive], hasLength(1));
    });

    test(
      'the last scored session is not blanked out by a later bad one',
      () async {
        await signedUpUser();
        final engine = readyEngine();

        await repository.saveSession(
          session: buildSession(
            id: 'good',
            result: engine.update(makeSession()),
          ),
          engine: engine,
        );
        await repository.saveSession(
          session: buildSession(
            id: 'invalid',
            result: engine.update(makeSession(valid: false)),
            valid: false,
          ),
          engine: engine,
        );

        expect((await repository.lastScoredSession('user-1'))!.id, 'good');
      },
    );

    test(
      'there is no last scored session before the baseline freezes',
      () async {
        await signedUpUser();
        final engine = ScreeningEngine();
        await repository.saveSession(
          session: buildSession(
            id: 'first',
            result: engine.update(makeSession()),
          ),
          engine: engine,
        );
        expect(await repository.lastScoredSession('user-1'), isNull);
      },
    );

    test(
      'the baseline countdown matches what the engine will actually pool',
      () async {
        await signedUpUser();
        final engine = ScreeningEngine();

        // The practice test, one invalid, one confounded, two good. Only the two good
        // ones should count.
        final plan = <({String id, bool valid, bool confounded})>[
          (id: 'fam-1', valid: true, confounded: false),
          (id: 'invalid', valid: false, confounded: false),
          (id: 'confounded', valid: true, confounded: true),
          (id: 'good-1', valid: true, confounded: false),
          (id: 'good-2', valid: true, confounded: false),
        ];

        for (final step in plan) {
          final result = engine.update(
            makeSession(valid: step.valid, confounded: step.confounded),
          );
          await repository.saveSession(
            session: buildSession(
              id: step.id,
              result: result,
              valid: step.valid,
              checkIn: step.confounded
                  ? CheckIn(
                      sleep: SleepQuality.poor,
                      fatigue: FatigueLevel.none,
                      illnessOrMedicationChange: false,
                      answeredAt: DateTime.utc(2026, 4, 2, 10),
                    )
                  : null,
            ),
            engine: engine,
          );
        }

        final sessions = await repository.loadSessions('user-1');
        expect(
          repository.baselineSessionsRemaining(sessions),
          kBaselineSessions - 2,
        );
        expect(engine.baselineProgress, closeTo(2 / kBaselineSessions, 1e-12));
      },
    );
  });

  group('trends once the baseline is set', () {
    /// Saves the practice test plus the pooled tests, returning the engine afterwards.
    Future<ScreeningEngine> saveBaselinePeriod({
      List<EngineSession>? pooled,
    }) async {
      final engine = ScreeningEngine();
      final sessions = [
        for (var i = 0; i < kFamiliarisationSessions; i++)
          makeSession(sessionId: 'familiarisation-${i + 1}'),
        ...(pooled ?? variedBaselineSessions()),
      ];
      for (var i = 0; i < sessions.length; i++) {
        final result = engine.update(sessions[i]);
        await repository.saveSession(
          session: buildSession(
            id: 'session-$i',
            result: result,
            features: sessions[i].features,
            at: DateTime.utc(2026, 4, 2 + i * 2, 10),
          ),
          engine: engine,
        );
      }
      return engine;
    }

    test('the sessions that built the baseline appear straight away', () async {
      // Without this, the Trends tab stayed empty until one more session after the
      // baseline was set, which reads as broken.
      await signedUpUser();
      final engine = await saveBaselinePeriod();
      final stored = await repository.loadSessions('user-1');

      expect(
        repository.deviationSeries(stored, baseline: engine.baseline),
        hasLength(kBaselineSessions),
      );
      for (final domain in Domain.values) {
        expect(
          repository.domainSeries(stored, baseline: engine.baseline)[domain],
          hasLength(kBaselineSessions),
          reason: domain.key,
        );
      }
    });

    test('without a baseline nothing is invented', () async {
      await signedUpUser();
      await saveBaselinePeriod();
      final stored = await repository.loadSessions('user-1');

      expect(repository.deviationSeries(stored), isEmpty);
    });

    test('familiarisation sessions are not plotted', () async {
      // They are discarded from the baseline precisely because practice distorts them.
      await signedUpUser();
      final engine = await saveBaselinePeriod();
      final stored = await repository.loadSessions('user-1');

      final plotted = repository
          .deviationSeries(stored, baseline: engine.baseline)
          .map((point) => point.at)
          .toSet();
      for (var i = 0; i < kFamiliarisationSessions; i++) {
        expect(plotted, isNot(contains(stored[i].completedAt)));
      }
    });

    test('the baseline-period values are small, being in-sample', () async {
      await signedUpUser();
      final engine = await saveBaselinePeriod();
      final stored = await repository.loadSessions('user-1');

      for (final point in repository.deviationSeries(
        stored,
        baseline: engine.baseline,
      )) {
        expect(point.ewma, lessThan(kDefaultThreshold));
      }
    });

    test('later sessions follow the baseline period in order', () async {
      await signedUpUser();
      final engine = await saveBaselinePeriod();
      final result = engine.update(makeSession());
      await repository.saveSession(
        session: buildSession(
          id: 'after',
          result: result,
          at: DateTime.utc(2026, 5, 20, 10),
        ),
        engine: engine,
      );

      final stored = await repository.loadSessions('user-1');
      final series = repository.deviationSeries(
        stored,
        baseline: engine.baseline,
      );

      expect(series, hasLength(kBaselineSessions + 1));
      for (var i = 1; i < series.length; i++) {
        expect(
          series[i].at.isBefore(series[i - 1].at),
          isFalse,
          reason: 'point $i is out of order',
        );
      }
    });

    test(
      'a confounded session inside the baseline period is not plotted',
      () async {
        // The engine did not pool it, so it must not appear as though it had.
        await signedUpUser();
        final engine = ScreeningEngine();
        final plan = [
          makeSession(sessionId: 'f1'),
          makeSession(sessionId: 'tired', confounded: true),
          ...variedBaselineSessions(),
        ];
        for (var i = 0; i < plan.length; i++) {
          final result = engine.update(plan[i]);
          await repository.saveSession(
            session: buildSession(
              id: 'session-$i',
              result: result,
              features: plan[i].features,
              at: DateTime.utc(2026, 4, 2 + i * 2, 10),
              checkIn: plan[i].confounded
                  ? CheckIn(
                      sleep: SleepQuality.poor,
                      fatigue: FatigueLevel.none,
                      illnessOrMedicationChange: false,
                      answeredAt: DateTime.utc(2026, 4, 2, 10),
                    )
                  : null,
            ),
            engine: engine,
          );
        }

        final stored = await repository.loadSessions('user-1');
        expect(
          repository.deviationSeries(stored, baseline: engine.baseline),
          hasLength(kBaselineSessions),
        );
      },
    );

    test('showing them does not disturb the engine', () async {
      // Display only: the EWMA and the run length must be exactly what they were.
      await signedUpUser();
      final engine = await saveBaselinePeriod();
      final stored = await repository.loadSessions('user-1');

      final ewmaBefore = engine.ewma;
      final runBefore = engine.run;
      repository
        ..deviationSeries(stored, baseline: engine.baseline)
        ..domainSeries(stored, baseline: engine.baseline);

      expect(engine.ewma, ewmaBefore);
      expect(engine.run, runBefore);
      expect(engine.ewma, 0.0);
    });
  });

  group('changing the baseline', () {
    /// Stores [count] tests for the current baseline, driving a real engine loaded from the
    /// repository, so each test is stamped and scored as the app would.
    Future<ScreeningEngine> saveTests(int count, {String prefix = 't'}) async {
      late ScreeningEngine engine;
      for (var i = 0; i < count; i++) {
        engine = await repository.loadEngine('user-1');
        final result = engine.update(
          makeSession(
            sessionId: '$prefix-$i',
            jitter: {for (final key in kCoreFeatureKeys) key: (i % 3) - 1.0},
          ),
        );
        await repository.saveSession(
          session: buildSession(
            id: '$prefix-$i',
            result: result,
            at: DateTime.utc(2026, 4, 2 + i, 10),
            features: makeSession(
              jitter: {for (final key in kCoreFeatureKeys) key: (i % 3) - 1.0},
            ).features,
          ),
          engine: engine,
        );
      }
      return engine;
    }

    test('a new user is on the first baseline', () async {
      final profile = await signedUpUser();
      expect(profile.baselineEpoch, 0);
    });

    test(
      'redoing it starts a new baseline and hides the earlier tests',
      () async {
        await signedUpUser();
        await saveTests(kFamiliarisationSessions + kBaselineSessions);
        expect((await repository.loadEngine('user-1')).baselineReady, isTrue);

        await repository.redoBaseline('user-1');

        expect(await repository.loadSessions('user-1'), isEmpty);
        final engine = await repository.loadEngine('user-1');
        expect(engine.baselineReady, isFalse);
        expect(engine.ewma, 0.0);
        expect((await repository.loadProfile('user-1'))!.baselineEpoch, 1);
      },
    );

    test('the frozen baseline and the smoothing state are cleared', () async {
      await signedUpUser();
      await saveTests(kFamiliarisationSessions + kBaselineSessions);
      expect(await db.select(db.baselines).get(), isNotEmpty);
      expect(await db.select(db.engineStates).get(), isNotEmpty);

      await repository.redoBaseline('user-1');

      expect(await db.select(db.baselines).get(), isEmpty);
      expect(await db.select(db.engineStates).get(), isEmpty);
    });

    test(
      'earlier tests are kept, and the export includes all of them',
      () async {
        await signedUpUser();
        const first = kFamiliarisationSessions + kBaselineSessions;
        await saveTests(first, prefix: 'old');
        await repository.redoBaseline('user-1');
        await saveTests(2, prefix: 'new');

        // Only the new baseline's tests are loaded...
        final current = await repository.loadSessions('user-1');
        expect(current.map((s) => s.id), ['new-0', 'new-1']);

        // ...but nothing was deleted, and the export has everything, marked by baseline.
        final all = await repository.loadSessions('user-1', allBaselines: true);
        expect(all, hasLength(first + 2));
        final export = await repository.exportEverything('user-1');
        final exported = (export['sessions']! as List)
            .cast<Map<String, dynamic>>();
        expect(exported, hasLength(first + 2));
        expect(exported.where((s) => s['epoch'] == 0), hasLength(first));
        expect(exported.where((s) => s['epoch'] == 1), hasLength(2));
      },
    );

    test('a test is stamped with the baseline that was current', () async {
      await signedUpUser();
      await saveTests(1, prefix: 'a');
      await repository.redoBaseline('user-1');
      await repository.redoBaseline('user-1');
      await saveTests(1, prefix: 'b');

      final all = await repository.loadSessions('user-1', allBaselines: true);
      expect({for (final s in all) s.id: s.epoch}, {'a-0': 0, 'b-0': 2});
    });

    test('the epoch is local: it is not in the sync payload', () async {
      await signedUpUser(syncEnabled: true);
      await repository.redoBaseline('user-1');
      await saveTests(1);
      await repository.inFlightSync;

      expect(backend.sessions, isNotEmpty);
      for (final session in backend.sessions) {
        expect(session.toSyncJson().containsKey('epoch'), isFalse);
      }
    });

    test('a later baseline has no practice test', () async {
      await signedUpUser();
      await saveTests(kFamiliarisationSessions + kBaselineSessions);
      await repository.redoBaseline('user-1');

      // Three tests are enough now: the user has already met the tasks.
      final engine = await saveTests(kBaselineSessions);
      expect(engine.baselineReady, isTrue);
      expect((await repository.loadEngine('user-1')).baselineReady, isTrue);
    });

    test('the countdown of a later baseline is out of three', () async {
      await signedUpUser();
      await saveTests(kFamiliarisationSessions + kBaselineSessions);
      await repository.redoBaseline('user-1');
      await saveTests(1);

      final sessions = await repository.loadSessions('user-1');
      expect(
        repository.baselineSessionsRemaining(sessions),
        kBaselineSessions - 1,
      );
    });

    test('the first baseline still has its practice test', () async {
      await signedUpUser();
      await saveTests(kBaselineSessions);

      // One short: the first of these was the practice test.
      final engine = await repository.loadEngine('user-1');
      expect(engine.baselineReady, isFalse);
    });

    test('watching the tests notices the baseline being redone', () async {
      await signedUpUser();
      await saveTests(2);

      final lengths = <int>[];
      final subscription = repository
          .watchSessions('user-1')
          .listen((sessions) => lengths.add(sessions.length));
      await pumpEventQueue();
      expect(lengths.last, 2);

      await repository.redoBaseline('user-1');
      await pumpEventQueue();
      expect(lengths.last, 0);

      await subscription.cancel();
    });

    test('saving a stale profile does not undo it', () async {
      final stale = await signedUpUser();
      await repository.redoBaseline('user-1');

      await repository.saveProfile(stale.copyWith(languageCode: 'ta'));

      final now = (await repository.loadProfile('user-1'))!;
      expect(now.languageCode, 'ta');
      expect(now.baselineEpoch, 1);
    });
  });

  group('calibrating the extended measurements', () {
    // The baseline tests fix the five core measurements. The other thirteen are fixed from the
    // first three full tests, and the engine has to arrive at the same place whether it stayed
    // running or was rebuilt from the database after a restart.

    /// Stores the practice test and the baseline, so the baseline is frozen.
    Future<void> saveBaselineTests() async {
      late ScreeningEngine engine;
      final sessions = [
        for (var i = 0; i < kFamiliarisationSessions; i++)
          makeSession(sessionId: 'practice-$i'),
        ...variedBaselineSessions(),
      ];
      engine = ScreeningEngine();
      for (var i = 0; i < sessions.length; i++) {
        final result = engine.update(sessions[i]);
        await repository.saveSession(
          session: buildSession(
            id: 'base-$i',
            result: result,
            features: sessions[i].features,
            at: DateTime.utc(2026, 4, 1 + i, 10),
          ),
          engine: engine,
        );
      }
    }

    /// Stores [count] full tests, loading the engine from the repository each time as the app
    /// does, so a restart is part of what is tested.
    Future<ScreeningEngine> saveFullTests(
      int count, {
      int from = 0,
      bool confounded = false,
    }) async {
      late ScreeningEngine engine;
      final sessions = variedFullSessions(from + count).skip(from).toList();
      for (var i = 0; i < sessions.length; i++) {
        engine = await repository.loadEngine('user-1');
        final result = engine.update(
          EngineSession(features: sessions[i].features, confounded: confounded),
        );
        await repository.saveSession(
          session: buildSession(
            id: 'full-${from + i}',
            result: result,
            features: sessions[i].features,
            at: DateTime.utc(2026, 5, 1 + from + i, 10),
            checkIn: confounded
                ? CheckIn(
                    sleep: SleepQuality.poor,
                    fatigue: FatigueLevel.none,
                    illnessOrMedicationChange: false,
                    answeredAt: DateTime.utc(2026, 5, 1 + from + i, 10),
                  )
                : null,
          ),
          engine: engine,
        );
      }
      return engine;
    }

    test(
      'right after the baseline only the core measurements have one',
      () async {
        await signedUpUser();
        await saveBaselineTests();

        final engine = await repository.loadEngine('user-1');
        expect(engine.baselineReady, isTrue);
        expect(engine.baseline!.median.keys.toSet(), kCoreFeatureKeys.toSet());
      },
    );

    test('two full tests leave the others calibrating', () async {
      await signedUpUser();
      await saveBaselineTests();
      await saveFullTests(kExtensionTests - 1);

      final engine = await repository.loadEngine('user-1');
      expect(engine.baseline!.isComplete, isFalse);
      // Rebuilt from the stored tests, not remembered.
      expect(engine.calibrationCollected, kExtensionTests - 1);
    });

    test(
      'the third full test completes the baseline, and it is stored',
      () async {
        await signedUpUser();
        await saveBaselineTests();
        await saveFullTests(kExtensionTests);

        final stored = await db.select(db.baselines).getSingle();
        final median = jsonDecode(stored.medianJson) as Map<String, dynamic>;
        expect(median.keys.toSet(), kFeatureKeys.toSet());

        final engine = await repository.loadEngine('user-1');
        expect(engine.baseline!.isComplete, isTrue);
      },
    );

    test(
      'growing the baseline leaves the core entries and the date alone',
      () async {
        await signedUpUser();
        await saveBaselineTests();
        final before = await db.select(db.baselines).getSingle();
        final coreBefore =
            jsonDecode(before.medianJson) as Map<String, dynamic>;

        await saveFullTests(kExtensionTests);

        final after = await db.select(db.baselines).getSingle();
        final coreAfter = jsonDecode(after.medianJson) as Map<String, dynamic>;
        for (final key in kCoreFeatureKeys) {
          expect(coreAfter[key], coreBefore[key], reason: key);
        }
        expect(after.frozenAt, before.frozenAt);
        expect(after.sessionCount, before.sessionCount);
      },
    );

    test(
      'a restart in the middle reaches the same baseline as not restarting',
      () async {
        await signedUpUser();
        await saveBaselineTests();
        await saveFullTests(kExtensionTests);
        final restarted = await repository.loadEngine('user-1');

        final live = ScreeningEngine();
        feedBaseline(live);
        variedFullSessions(kExtensionTests).forEach(live.update);

        for (final key in kFeatureKeys) {
          expect(
            restarted.baseline!.median[key],
            closeTo(live.baseline!.median[key]!, 1e-9),
            reason: key,
          );
          expect(
            restarted.baseline!.scale[key],
            closeTo(live.baseline!.scale[key]!, 1e-9),
            reason: key,
          );
        }
      },
    );

    test('a tired full test does not count towards calibration', () async {
      await signedUpUser();
      await saveBaselineTests();
      await saveFullTests(2, confounded: true);

      final engine = await repository.loadEngine('user-1');
      expect(engine.calibrationCollected, 0);
      expect(engine.baseline!.isComplete, isFalse);
    });

    test(
      'tired tests among good ones delay the calibration by exactly that many',
      () async {
        await signedUpUser();
        await saveBaselineTests();
        await saveFullTests(2);
        await saveFullTests(1, from: 2, confounded: true);

        var engine = await repository.loadEngine('user-1');
        expect(engine.baseline!.isComplete, isFalse);

        await saveFullTests(1, from: 3);
        engine = await repository.loadEngine('user-1');
        expect(engine.baseline!.isComplete, isTrue);
      },
    );

    test('a grown baseline is queued for backup when sync is on', () async {
      await signedUpUser(syncEnabled: true);
      await saveBaselineTests();
      await repository.inFlightSync;
      final uploadedFirst = backend.baselines['user-1']!;
      expect(uploadedFirst.isComplete, isFalse);

      await saveFullTests(kExtensionTests);
      await repository.inFlightSync;
      expect(backend.baselines['user-1']!.isComplete, isTrue);
    });

    test('redoing the baseline starts calibration again', () async {
      await signedUpUser();
      await saveBaselineTests();
      await saveFullTests(kExtensionTests);
      expect(
        (await repository.loadEngine('user-1')).baseline!.isComplete,
        isTrue,
      );

      await repository.redoBaseline('user-1');

      final engine = await repository.loadEngine('user-1');
      expect(engine.baselineReady, isFalse);
      expect(engine.calibrationCollected, 0);
    });

    test(
      'full tests are scored with the new measurements once calibrated',
      () async {
        await signedUpUser();
        await saveBaselineTests();
        await saveFullTests(kExtensionTests);
        final engine = await saveFullTests(1, from: kExtensionTests);

        // The fourth full test had all four areas, typing included.
        final last = (await repository.loadSessions('user-1')).last;
        expect(last.domainScores!.keys.toSet(), Domain.values.toSet());
        expect(engine.baseline!.isComplete, isTrue);
      },
    );

    test(
      'the earlier full tests were scored without the areas still calibrating',
      () async {
        await signedUpUser();
        await saveBaselineTests();
        await saveFullTests(1);

        final first = (await repository.loadSessions('user-1')).last;
        expect(first.domainScores!.containsKey(Domain.interaction), isFalse);
        expect(first.contributions!.keys.toSet(), Domain.values.toSet());
        expect(first.contributions![Domain.interaction], 0.0);
      },
    );
  });

  group('export', () {
    test('includes the recall words the cloud never receives', () async {
      // The user is entitled to their own data, which is a wider set than the
      // sync payload.
      await signedUpUser();
      final engine = readyEngine();
      await repository.saveSession(
        session: buildSession(
          id: 'session-1',
          result: engine.update(makeSession()),
          recallDetail: const RecallDetail(
            listId: 1,
            recalled: ['violin'],
            missed: ['tunnel'],
          ),
        ),
        engine: engine,
      );

      final exported = jsonEncode(await repository.exportEverything('user-1'));
      expect(exported, contains('violin'));
      expect(exported, contains('tunnel'));
    });

    test('says plainly that it is not a diagnosis', () async {
      await signedUpUser();
      final exported = await repository.exportEverything('user-1');
      expect(exported['note'], contains('not a medical diagnosis'));
    });

    test('includes the baseline once frozen', () async {
      await signedUpUser();
      final engine = readyEngine();
      await repository.saveEngineState('user-1', engine);

      final exported = await repository.exportEverything('user-1');
      expect(exported['baseline'], isNotNull);
    });
  });

  group('erasure', () {
    test('removes every local trace', () async {
      await signedUpUser();
      final engine = readyEngine();
      await repository.saveSession(
        session: buildSession(
          id: 'session-1',
          result: engine.update(makeSession()),
        ),
        engine: engine,
      );
      await repository.recordReport(
        userId: 'user-1',
        periodStart: DateTime.utc(2026, 3, 14, 9),
        periodEnd: DateTime.utc(2026, 4, 14, 9),
        status: ScreeningStatus.stable,
        contributions: const {Domain.cognitive: 1.0},
        sessionCount: 1,
      );

      await repository.deleteEverything('user-1');

      expect(await repository.loadProfile('user-1'), isNull);
      expect(await repository.loadSessions('user-1'), isEmpty);
      expect(await db.select(db.baselines).get(), isEmpty);
      expect(await db.select(db.engineStates).get(), isEmpty);
      expect(await db.select(db.reports).get(), isEmpty);
    });

    test('tells the cloud to delete too', () async {
      await signedUpUser(syncEnabled: true);
      expect(await repository.deleteEverything('user-1'), isTrue);
      expect(backend.deleted, ['user-1']);
    });

    test('still wipes locally when the cloud delete fails', () async {
      // A user who asked to be forgotten must not be left with their data on the
      // phone because the network was down.
      await signedUpUser(syncEnabled: true);
      final engine = readyEngine();
      await repository.saveSession(
        session: buildSession(
          id: 'session-1',
          result: engine.update(makeSession()),
        ),
        engine: engine,
      );

      backend.failure = const SyncException(SyncFailure.offline);
      final remoteCleared = await repository.deleteEverything('user-1');

      expect(remoteCleared, isFalse);
      expect(await repository.loadProfile('user-1'), isNull);
      expect(await repository.loadSessions('user-1'), isEmpty);
    });

    test('empties the upload queue so nothing is sent afterwards', () async {
      await signedUpUser(syncEnabled: true);
      backend.failure = const SyncException(SyncFailure.offline);
      final engine = readyEngine();
      await repository.saveSession(
        session: buildSession(
          id: 'session-1',
          result: engine.update(makeSession()),
        ),
        engine: engine,
      );

      backend.failure = null;
      await repository.deleteEverything('user-1');
      await repository.syncNow();

      expect(backend.sessions, isEmpty);
      expect(queue.pendingCount, 0);
    });
  });

  group('reports', () {
    test('records an export and queues it when sync is on', () async {
      await signedUpUser(syncEnabled: true);
      final id = await repository.recordReport(
        userId: 'user-1',
        periodStart: DateTime.utc(2026, 3, 14, 9),
        periodEnd: DateTime.utc(2026, 4, 14, 9),
        status: ScreeningStatus.notableDeviation,
        contributions: const {Domain.cognitive: 0.55, Domain.speech: 0.45},
        sessionCount: 12,
      );
      await repository.inFlightSync;

      expect(backend.reports, [id]);
      final stored = await db.select(db.reports).getSingle();
      expect(stored.status, 'NOTABLE_DEVIATION');
      expect(stored.sessionCount, 12);
    });

    test('does not queue an export when sync is off', () async {
      await signedUpUser();
      await repository.recordReport(
        userId: 'user-1',
        periodStart: DateTime.utc(2026, 3, 14, 9),
        periodEnd: DateTime.utc(2026, 4, 14, 9),
        status: ScreeningStatus.stable,
        contributions: const {Domain.cognitive: 1.0},
        sessionCount: 3,
      );
      await repository.inFlightSync;
      expect(backend.reports, isEmpty);
    });
  });
}
