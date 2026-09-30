/// The single place the rest of the app reads and writes data.
///
/// Two rules hold everywhere in this file, and most of its shape follows from
/// them.
///
/// The local database is written first and the upload is queued afterwards, never
/// the other way round. A session the user just completed must be visible whether
/// or not there is a connection, and the UI never awaits the network.
///
/// The engine's state is persisted rather than recomputed. Replaying the whole
/// history on every launch would give the same answer today, but it would also
/// mean that deleting one old session silently changed the current status -- and
/// a user deleting a single bad session is not asking to have their trend
/// rewritten.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:drift/drift.dart';

import '../engine/baseline.dart';
import '../engine/constants.dart';
import '../engine/features.dart';
import '../engine/screening_engine.dart';
import 'local_db.dart';
import 'models.dart';
import 'sync_service.dart';

/// Reads and writes everything the app stores.
class Repository {
  Repository({
    required LocalDatabase database,
    required SyncQueue syncQueue,
  })  : _db = database,
        _sync = syncQueue;

  final LocalDatabase _db;
  final SyncQueue _sync;

  /// The drain started in the background by the last write, if one is still going.
  Future<void>? _backgroundDrain;

  /// The upload queue, exposed so the privacy screen can report its depth.
  SyncQueue get syncQueue => _sync;

  /// Completes when any background upload started by a write has finished.
  ///
  /// The UI never waits on an upload, so a write returns before its drain does.
  /// This exists so that the few callers who genuinely need to wait -- the privacy
  /// screen's "sync now", and the tests -- can, without the write path changing.
  Future<void> get inFlightSync => _backgroundDrain ?? Future<void>.value();

  // -- profile --------------------------------------------------------------

  /// The stored profile for [userId], or null if this is a new account.
  Future<UserProfile?> loadProfile(String userId) async {
    final row = await (_db.select(_db.users)
          ..where((table) => table.id.equals(userId)))
        .getSingleOrNull();
    return row == null ? null : _profileFromRow(row);
  }

  /// Watches the profile, so the dashboard reflects a settings change at once.
  Stream<UserProfile?> watchProfile(String userId) =>
      (_db.select(_db.users)..where((table) => table.id.equals(userId)))
          .watchSingleOrNull()
          .map((row) => row == null ? null : _profileFromRow(row));

  /// Creates the profile row for a newly signed-in account, or returns the
  /// existing one.
  ///
  /// Does not queue an upload: a profile with no consent yet has nothing the cloud
  /// should hold, and sync cannot be on before the consent screen has been seen.
  Future<UserProfile> ensureProfile({
    required String userId,
    String? email,
    String? displayName,
  }) async {
    final existing = await loadProfile(userId);
    if (existing != null) return existing;

    final profile = UserProfile(
      id: userId,
      createdAt: DateTime.now(),
      email: email,
      displayName: displayName,
    );
    await _db.into(_db.users).insert(_profileToRow(profile));
    // Reloaded rather than returned directly: Drift stores a DateTime to the
    // second, so the in-memory object and the stored row would otherwise disagree
    // on createdAt, and this method would return different precision depending on
    // whether the row already existed.
    return (await loadProfile(userId))!;
  }

  /// Saves [profile] and queues an upload if sync is on.
  Future<void> saveProfile(UserProfile profile) async {
    await _db.update(_db.users).replace(_profileToRow(profile));
    if (profile.syncEnabled) {
      _sync.enqueueProfile(profile);
    }
  }

  /// Records the user's consent and their sync choice.
  ///
  /// Turning sync off drops anything queued rather than sending it. A user who has
  /// just withdrawn permission to upload should not have the last few sessions go
  /// up because they were already in the queue.
  Future<UserProfile> recordConsent({
    required UserProfile profile,
    required bool syncEnabled,
  }) async {
    final updated = profile.copyWith(
      consent: ConsentRecord(
        version: ConsentRecord.currentVersion,
        acceptedAt: DateTime.now(),
        syncEnabled: syncEnabled,
      ),
    );

    if (!syncEnabled) _sync.clear();
    await saveProfile(updated);
    return updated;
  }

  // -- engine ---------------------------------------------------------------

  /// Rebuilds the engine for [userId] from the stored baseline and state.
  ///
  /// When no baseline has been frozen yet, the pool has to be replayed, because a
  /// pool of whole sessions is not something the state row can hold. That is
  /// bounded work: it happens at most eight times in a user's life.
  Future<ScreeningEngine> loadEngine(String userId) async {
    final baselineRow = await (_db.select(_db.baselines)
          ..where((table) => table.userId.equals(userId)))
        .getSingleOrNull();
    final stateRow = await (_db.select(_db.engineStates)
          ..where((table) => table.userId.equals(userId)))
        .getSingleOrNull();

    if (baselineRow != null) {
      return ScreeningEngine(
        baseline: Baseline(
          median: _decodeDoubles(baselineRow.medianJson),
          scale: _decodeDoubles(baselineRow.scaleJson),
          sessionCount: baselineRow.sessionCount,
        ),
        ewma: stateRow?.ewma ?? 0.0,
        run: stateRow?.runLength ?? 0,
        seen: stateRow?.sessionsSeen ?? 0,
      );
    }

    final engine = ScreeningEngine();
    for (final session in await loadSessions(userId)) {
      engine.update(_toEngineSession(session));
    }
    return engine;
  }

  /// Persists the engine's state, and its baseline the first time it freezes.
  Future<void> saveEngineState(String userId, ScreeningEngine engine) async {
    await _db.into(_db.engineStates).insertOnConflictUpdate(
          EngineStatesCompanion.insert(
            userId: userId,
            ewma: Value(engine.ewma),
            runLength: Value(engine.run),
            sessionsSeen: Value(engine.sessionsSeen),
            updatedAt: DateTime.now(),
          ),
        );

    final baseline = engine.baseline;
    if (baseline == null) return;

    final alreadyStored = await (_db.select(_db.baselines)
          ..where((table) => table.userId.equals(userId)))
        .getSingleOrNull();
    if (alreadyStored != null) return;

    await _db.into(_db.baselines).insert(
          BaselinesCompanion.insert(
            userId: userId,
            frozenAt: DateTime.now(),
            medianJson: jsonEncode(baseline.median),
            scaleJson: jsonEncode(baseline.scale),
            sessionCount: baseline.sessionCount,
          ),
        );

    final profile = await loadProfile(userId);
    if (profile?.syncEnabled ?? false) {
      _sync.enqueueBaseline(userId, baseline);
    }
  }

  // -- sessions -------------------------------------------------------------

  /// Every stored session for [userId], oldest first.
  ///
  /// Oldest first because that is replay order; the UI reverses it where it wants
  /// the most recent at the top.
  Future<List<SessionRecord>> loadSessions(String userId) async {
    final rows = await (_db.select(_db.sessions)
          ..where((table) => table.userId.equals(userId))
          ..orderBy([(table) => OrderingTerm.asc(table.startedAt)]))
        .get();
    return rows.map(_sessionFromRow).toList();
  }

  /// Watches the sessions, so the dashboard and trends update as they are added.
  Stream<List<SessionRecord>> watchSessions(String userId) =>
      (_db.select(_db.sessions)
            ..where((table) => table.userId.equals(userId))
            ..orderBy([(table) => OrderingTerm.asc(table.startedAt)]))
          .watch()
          .map((rows) => rows.map(_sessionFromRow).toList());

  /// The most recent session that was actually scored.
  ///
  /// The dashboard shows the last *scored* status, not the last attempt: an invalid
  /// or confounded session should not blank out the standing result.
  Future<SessionRecord?> lastScoredSession(String userId) async {
    final sessions = await loadSessions(userId);
    for (final session in sessions.reversed) {
      if (session.countsTowardsTrend) return session;
    }
    return null;
  }

  /// Stores a completed session and queues its upload.
  ///
  /// The local write and the engine-state write happen in one transaction: a
  /// session stored without its state, or the reverse, would leave the smoothed
  /// index disagreeing with the history it was computed from.
  Future<void> saveSession({
    required SessionRecord session,
    required ScreeningEngine engine,
  }) async {
    await _db.transaction(() async {
      await _db.into(_db.sessions).insertOnConflictUpdate(
            _sessionToRow(session),
          );
      await saveEngineState(session.userId, engine);
    });

    final profile = await loadProfile(session.userId);
    if (profile?.syncEnabled ?? false) {
      _sync.enqueueSession(session);
      // Not awaited: the UI moves straight to the result screen, and a drain that
      // has to retry through a back-off could take minutes.
      _startBackgroundDrain();
    }
  }

  /// Starts a drain without waiting for it, keeping a handle on it.
  void _startBackgroundDrain() {
    final drain = _drainQuietly();
    _backgroundDrain = drain;
    unawaited(drain);
  }

  /// Marks a session as having reached the cloud.
  Future<void> markSynced(String sessionId) async {
    await (_db.update(_db.sessions)
          ..where((table) => table.id.equals(sessionId)))
        .write(const SessionsCompanion(synced: Value(true)));
  }

  /// Drains the upload queue, swallowing failures.
  ///
  /// Failures are the queue's business: it retries the transient ones and counts
  /// the rest, which the privacy screen reports. An exception escaping here would
  /// surface as a crash during an ordinary offline session.
  Future<void> _drainQuietly() async {
    try {
      final sent = await _sync.drain();
      for (final id in sent) {
        if (id.startsWith('session:')) {
          await markSynced(id.substring('session:'.length));
        }
      }
    } on Object {
      // Deliberately swallowed; see above.
    }
  }

  /// Sends whatever is queued, for the privacy screen's "sync now" action.
  ///
  /// Waits for any background drain to settle first: [SyncQueue.drain] refuses to
  /// run twice at once, so without this a "sync now" tapped moments after a session
  /// would return having sent nothing.
  Future<void> syncNow() async {
    await inFlightSync;
    await _drainQuietly();
  }

  // -- reports --------------------------------------------------------------

  /// Records that a PDF report was exported. The file itself stays on the phone.
  Future<String> recordReport({
    required String userId,
    required DateTime periodStart,
    required DateTime periodEnd,
    required ScreeningStatus status,
    required Map<Domain, double> contributions,
    required int sessionCount,
  }) async {
    final id = _generateId();
    final encoded = {
      for (final entry in contributions.entries) entry.key.key: entry.value,
    };

    await _db.into(_db.reports).insert(
          ReportsCompanion.insert(
            id: id,
            userId: userId,
            createdAt: DateTime.now(),
            periodStart: periodStart,
            periodEnd: periodEnd,
            status: status.key,
            contributionsJson: jsonEncode(encoded),
            sessionCount: sessionCount,
          ),
        );

    final profile = await loadProfile(userId);
    if (profile?.syncEnabled ?? false) {
      _sync.enqueue(
        'report:$id',
        () => _sync.backend.recordReport(
          userId: userId,
          reportId: id,
          periodStart: periodStart,
          periodEnd: periodEnd,
          status: status.key,
          contributions: encoded,
        ),
      );
      _startBackgroundDrain();
    }

    return id;
  }

  // -- export and erasure ---------------------------------------------------

  /// Everything stored for [userId], as JSON.
  ///
  /// This is the data-portability half of the privacy requirement, and it
  /// deliberately includes more than the sync payload does: the user is entitled to
  /// their own recall words, which the cloud never receives.
  Future<Map<String, dynamic>> exportEverything(String userId) async {
    final profile = await loadProfile(userId);
    final sessions = await loadSessions(userId);
    final baselineRow = await (_db.select(_db.baselines)
          ..where((table) => table.userId.equals(userId)))
        .getSingleOrNull();
    final reports = await (_db.select(_db.reports)
          ..where((table) => table.userId.equals(userId)))
        .get();

    return {
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'appVersion': '1.0.0',
      'note': 'Behavioural screening data from NeuraScan AI. '
          'These are derived measurements, not a medical diagnosis.',
      'profile': profile?.toJson(),
      'baseline': baselineRow == null
          ? null
          : {
              'frozenAt': baselineRow.frozenAt.toUtc().toIso8601String(),
              'median': _decodeDoubles(baselineRow.medianJson),
              'scale': _decodeDoubles(baselineRow.scaleJson),
              'sessionCount': baselineRow.sessionCount,
            },
      'sessions': [for (final session in sessions) session.toJson()],
      'reports': [
        for (final report in reports)
          {
            'id': report.id,
            'createdAt': report.createdAt.toUtc().toIso8601String(),
            'periodStart': report.periodStart.toUtc().toIso8601String(),
            'periodEnd': report.periodEnd.toUtc().toIso8601String(),
            'status': report.status,
            'contributions': _decodeDoubles(report.contributionsJson),
            'sessionCount': report.sessionCount,
          },
      ],
    };
  }

  /// Deletes everything for [userId], locally and in the cloud.
  ///
  /// Local first, and deliberately so. If the network is down, a user who asked to
  /// be forgotten must not be left with their data still on the phone because the
  /// remote call failed. The cloud delete is attempted and its outcome reported,
  /// but it cannot block the local wipe.
  ///
  /// Returns true when the remote side was also cleared.
  Future<bool> deleteEverything(String userId) async {
    _sync.clear();

    await _db.transaction(() async {
      // Foreign keys cascade from users, but the deletes are explicit so that this
      // does not depend on the pragma having been applied.
      await (_db.delete(_db.sessions)
            ..where((table) => table.userId.equals(userId)))
          .go();
      await (_db.delete(_db.baselines)
            ..where((table) => table.userId.equals(userId)))
          .go();
      await (_db.delete(_db.engineStates)
            ..where((table) => table.userId.equals(userId)))
          .go();
      await (_db.delete(_db.reports)
            ..where((table) => table.userId.equals(userId)))
          .go();
      await (_db.delete(_db.users)..where((table) => table.id.equals(userId)))
          .go();
    });

    try {
      await _sync.backend.deleteEverything(userId);
      return true;
    } on Object {
      return false;
    }
  }

  // -- derived views --------------------------------------------------------

  /// The per-domain history for the trend charts.
  ///
  /// Only scored sessions appear. Plotting a confounded or invalid session as a
  /// gap-free point would show the user a change in their trend that the engine
  /// explicitly decided to ignore.
  Map<Domain, List<({DateTime at, double score})>> domainSeries(
    List<SessionRecord> sessions,
  ) {
    final series = {for (final domain in Domain.values) domain: <({DateTime at, double score})>[]};
    for (final session in sessions) {
      final scores = session.domainScores;
      if (!session.countsTowardsTrend || scores == null) continue;
      for (final domain in Domain.values) {
        final score = scores[domain];
        if (score != null) {
          series[domain]!.add((at: session.completedAt, score: score));
        }
      }
    }
    return series;
  }

  /// The smoothed deviation history, for the main trend chart.
  List<({DateTime at, double ewma})> deviationSeries(
    List<SessionRecord> sessions,
  ) =>
      [
        for (final session in sessions)
          if (session.countsTowardsTrend && session.ewma != null)
            (at: session.completedAt, ewma: session.ewma!),
      ];

  /// How many more sessions before the baseline freezes.
  ///
  /// Counts the sessions that would actually be pooled -- valid, unconfounded, and
  /// past familiarisation -- so the number shown on the dashboard matches what the
  /// engine will do rather than the raw session count.
  int baselineSessionsRemaining(List<SessionRecord> sessions) {
    var seen = 0;
    var pooled = 0;
    for (final session in sessions) {
      seen++;
      if (!session.valid) continue;
      if (seen <= kFamiliarisationSessions) continue;
      if (session.checkIn.isConfounded) continue;
      pooled++;
    }
    return (kBaselineSessions - pooled).clamp(0, kBaselineSessions);
  }

  // -- mapping --------------------------------------------------------------

  EngineSession _toEngineSession(SessionRecord session) => EngineSession(
        features: session.features,
        valid: session.valid,
        confounded: session.checkIn.isConfounded,
        sessionId: session.id,
      );

  UserProfile _profileFromRow(UserRow row) => UserProfile(
        id: row.id,
        createdAt: row.createdAt,
        email: row.email,
        displayName: row.displayName,
        dominantHand: DominantHand.fromKey(row.dominantHand),
        languageCode: row.languageCode,
        consent: row.consentJson == null
            ? null
            : ConsentRecord.fromJson(
                (jsonDecode(row.consentJson!) as Map).cast<String, dynamic>(),
              ),
        reminderEnabled: row.reminderEnabled,
        reminderIntervalDays: row.reminderIntervalDays,
      );

  UsersCompanion _profileToRow(UserProfile profile) => UsersCompanion.insert(
        id: profile.id,
        createdAt: profile.createdAt,
        email: Value(profile.email),
        displayName: Value(profile.displayName),
        dominantHand: Value(profile.dominantHand.key),
        languageCode: Value(profile.languageCode),
        consentJson: Value(
          profile.consent == null ? null : jsonEncode(profile.consent!.toJson()),
        ),
        reminderEnabled: Value(profile.reminderEnabled),
        reminderIntervalDays: Value(profile.reminderIntervalDays),
      );

  SessionRecord _sessionFromRow(SessionRow row) => SessionRecord(
        id: row.id,
        userId: row.userId,
        startedAt: row.startedAt,
        completedAt: row.completedAt,
        checkIn: CheckIn.fromJson(
          (jsonDecode(row.checkInJson) as Map).cast<String, dynamic>(),
        ),
        features: _decodeDoubles(row.featuresJson),
        valid: row.valid,
        status: ScreeningStatus.fromKey(row.status),
        invalidReasons: [
          for (final reason in jsonDecode(row.invalidReasonsJson) as List)
            reason as String,
        ],
        index: row.deviationIndex,
        ewma: row.ewma,
        run: row.runLength,
        domainScores: _decodeDomains(row.domainScoresJson),
        contributions: _decodeDomains(row.contributionsJson),
        recallDetail: row.recallDetailJson == null
            ? null
            : RecallDetail.fromJson(
                (jsonDecode(row.recallDetailJson!) as Map)
                    .cast<String, dynamic>(),
              ),
        synced: row.synced,
      );

  SessionsCompanion _sessionToRow(SessionRecord session) =>
      SessionsCompanion.insert(
        id: session.id,
        userId: session.userId,
        startedAt: session.startedAt,
        completedAt: session.completedAt,
        checkInJson: jsonEncode(session.checkIn.toJson()),
        featuresJson: jsonEncode(session.features),
        valid: session.valid,
        status: session.status.key,
        invalidReasonsJson: Value(jsonEncode(session.invalidReasons)),
        deviationIndex: Value(session.index),
        ewma: Value(session.ewma),
        runLength: Value(session.run),
        domainScoresJson: Value(_encodeDomains(session.domainScores)),
        contributionsJson: Value(_encodeDomains(session.contributions)),
        recallDetailJson: Value(
          session.recallDetail == null
              ? null
              : jsonEncode(session.recallDetail!.toJson()),
        ),
        synced: Value(session.synced),
      );

  static Map<String, double> _decodeDoubles(String json) {
    final decoded = jsonDecode(json) as Map<String, dynamic>;
    return {
      for (final entry in decoded.entries)
        entry.key: (entry.value as num).toDouble(),
    };
  }

  static Map<Domain, double>? _decodeDomains(String? json) {
    if (json == null) return null;
    final decoded = jsonDecode(json) as Map<String, dynamic>;
    return {
      for (final entry in decoded.entries)
        Domain.fromKey(entry.key): (entry.value as num).toDouble(),
    };
  }

  static String? _encodeDomains(Map<Domain, double>? scores) {
    if (scores == null) return null;
    return jsonEncode({
      for (final entry in scores.entries) entry.key.key: entry.value,
    });
  }

  static String _generateId() {
    final random = Random.secure();
    return List<int>.generate(12, (_) => random.nextInt(256))
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
  }
}
