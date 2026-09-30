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
  }) {
    final now = DateTime.utc(2026, 4, 2, 10);
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
        for (var i = 0; i < 4; i++) {
          final result = engine.update(makeSession(sessionId: 'session-$i'));
          await repository.saveSession(
            session: buildSession(id: 'session-$i', result: result),
            engine: engine,
          );
        }

        final reloaded = await repository.loadEngine('user-1');
        expect(reloaded.baselineReady, isFalse);
        expect(reloaded.sessionsSeen, 4);
        // Two familiarisation sessions discarded, two pooled.
        expect(
          reloaded.baselineProgress,
          closeTo(2 / kBaselineSessions, 1e-12),
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

        // Two familiarisation, one invalid, one confounded, two good. Only the two
        // good ones should count.
        final plan = <({String id, bool valid, bool confounded})>[
          (id: 'fam-1', valid: true, confounded: false),
          (id: 'fam-2', valid: true, confounded: false),
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
        contributions: const {
          Domain.cognitive: 0.47,
          Domain.speech: 0.39,
          Domain.interaction: 0.14,
        },
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
