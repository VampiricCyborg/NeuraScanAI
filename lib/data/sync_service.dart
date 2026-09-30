/// Optional cloud backup of derived scores, behind an interface.
///
/// This is the file where the app's privacy claim is either true or false, so it is
/// worth being explicit about what it does.
///
/// What may be uploaded: the nine derived features, the domain scores, the
/// deviation index, the smoothed index, the status, and the check-in answers. All
/// of it is numbers and a handful of enum values, about half a kilobyte per
/// session.
///
/// What may never be uploaded: the recorded audio, the touch trace, the keystroke
/// timings, the words the user typed, and the PDF report. Those never leave the
/// phone. The audio is deleted as soon as its two features have been extracted,
/// and the trace and keystroke timings are never written to the database at all.
///
/// That boundary is enforced in two places rather than trusted: [SessionRecord]
/// has a separate `toSyncJson`, and the test suite asserts that the upload payload
/// contains no raw signal. Sync is also off unless the user turned it on.
library;

import 'dart:async';

import '../engine/baseline.dart';
import 'models.dart';

/// Why an upload failed.
///
/// [SyncFailure.offline] is the ordinary case rather than an error: the queue is
/// expected to sit full for days and drain when a connection appears.
enum SyncFailure {
  offline,
  notAuthenticated,
  permissionDenied,
  quotaExceeded,
  unknown;

  /// True when retrying later is worth doing.
  ///
  /// A permission failure means the rules rejected the write, which retrying will
  /// not fix; retrying it forever would be a battery cost with no upside.
  bool get isTransient =>
      this == SyncFailure.offline ||
      this == SyncFailure.quotaExceeded ||
      this == SyncFailure.unknown;
}

/// Thrown by a sync backend when an upload fails.
class SyncException implements Exception {
  const SyncException(this.failure, [this.detail]);

  final SyncFailure failure;
  final String? detail;

  @override
  String toString() =>
      'SyncException(${failure.name}${detail == null ? '' : ': $detail'})';
}

/// Where derived scores go when sync is on.
abstract interface class SyncBackend {
  /// Uploads or replaces the user's profile document.
  ///
  /// Takes a [UserProfile] rather than its JSON so the implementation can pick
  /// which fields travel; the local record holds settings the cloud has no use
  /// for.
  Future<void> upsertProfile(UserProfile profile);

  /// Uploads one session's derived scores.
  ///
  /// Idempotent by session id, so a retry after an ambiguous failure cannot
  /// produce a duplicate. That matters because the queue retries on any transient
  /// error, including a timeout where the write may well have succeeded.
  Future<void> upsertSession(SessionRecord session);

  /// Uploads the frozen baseline. Written once, when it freezes.
  Future<void> upsertBaseline(String userId, Baseline baseline);

  /// Records that a report was exported. The PDF itself stays on the phone.
  Future<void> recordReport({
    required String userId,
    required String reportId,
    required DateTime periodStart,
    required DateTime periodEnd,
    required String status,
    required Map<String, double> contributions,
  });

  /// Deletes everything stored for [userId].
  ///
  /// Part of account deletion, and the part that can fail while the local wipe
  /// cannot. The repository deletes locally first, so a user who asked to be
  /// forgotten is not left with their data on the device because the network was
  /// down.
  Future<void> deleteEverything(String userId);
}

/// A sync backend that does nothing, used when sync is off or unconfigured.
///
/// The null-object here is not laziness: with it, every call site can write to
/// the backend unconditionally, so there is no `if (syncEnabled)` scattered
/// through the repository waiting to be forgotten in one place. Whether sync
/// happens is decided once, where the backend is chosen.
class DisabledSyncBackend implements SyncBackend {
  const DisabledSyncBackend();

  @override
  Future<void> upsertProfile(UserProfile profile) async {}

  @override
  Future<void> upsertSession(SessionRecord session) async {}

  @override
  Future<void> upsertBaseline(String userId, Baseline baseline) async {}

  @override
  Future<void> recordReport({
    required String userId,
    required String reportId,
    required DateTime periodStart,
    required DateTime periodEnd,
    required String status,
    required Map<String, double> contributions,
  }) async {}

  @override
  Future<void> deleteEverything(String userId) async {}
}

/// One queued upload.
class SyncJob {
  SyncJob({
    required this.id,
    required this.run,
    this.attempts = 0,
    this.lastFailure,
  });

  /// Identifies what this job is for, so a second job for the same thing replaces
  /// the first rather than queueing behind it.
  ///
  /// Uploads are last-write-wins on a document, so five queued writes of the same
  /// session are four wasted requests.
  final String id;

  /// The upload itself.
  final Future<void> Function() run;

  int attempts;
  SyncFailure? lastFailure;
}

/// Retries queued uploads with exponential back-off.
///
/// The UI never waits on this. A session is written to the local database and
/// shown to the user immediately; the upload is queued and drains whenever it can,
/// which is what stops a slow connection from making the app feel broken.
class SyncQueue {
  SyncQueue({
    required SyncBackend backend,
    Duration initialBackoff = const Duration(seconds: 2),
    Duration maximumBackoff = const Duration(minutes: 30),
    int maximumAttempts = 8,
    Future<void> Function(Duration)? delay,
  }) : _backend = backend,
       _initialBackoff = initialBackoff,
       _maximumBackoff = maximumBackoff,
       _maximumAttempts = maximumAttempts,
       _delay = delay ?? Future<void>.delayed;

  final SyncBackend _backend;
  final Duration _initialBackoff;
  final Duration _maximumBackoff;
  final int _maximumAttempts;
  final Future<void> Function(Duration) _delay;

  final _pending = <String, SyncJob>{};
  final _abandoned = <String, SyncJob>{};
  bool _draining = false;

  /// Jobs waiting to be sent.
  int get pendingCount => _pending.length;

  /// Jobs that failed permanently or ran out of attempts.
  ///
  /// Surfaced on the privacy screen rather than hidden, so that a user who turned
  /// sync on can see that it is not working instead of assuming a backup exists.
  int get abandonedCount => _abandoned.length;

  /// The backend jobs are sent to.
  SyncBackend get backend => _backend;

  /// Queues [run] under [id], replacing any earlier job with the same id.
  void enqueue(String id, Future<void> Function() run) {
    _pending[id] = SyncJob(id: id, run: run);
  }

  /// Queues a session upload.
  void enqueueSession(SessionRecord session) =>
      enqueue('session:${session.id}', () => _backend.upsertSession(session));

  /// Queues a profile upload.
  void enqueueProfile(UserProfile profile) =>
      enqueue('profile:${profile.id}', () => _backend.upsertProfile(profile));

  /// Queues a baseline upload.
  void enqueueBaseline(String userId, Baseline baseline) => enqueue(
    'baseline:$userId',
    () => _backend.upsertBaseline(userId, baseline),
  );

  /// Sends everything queued, retrying transient failures.
  ///
  /// Returns the ids that were sent. Safe to call while a drain is already
  /// running: the second call returns immediately rather than sending anything
  /// twice.
  Future<List<String>> drain() async {
    if (_draining) return const [];
    _draining = true;
    try {
      final sent = <String>[];
      // Snapshot the ids: a job may be re-enqueued while this runs, and that
      // replacement should wait for the next drain rather than being sent with a
      // stale closure.
      for (final id in _pending.keys.toList()) {
        final job = _pending[id];
        if (job == null) continue;
        if (await _attempt(job)) {
          _pending.remove(id);
          sent.add(id);
        }
      }
      return sent;
    } finally {
      _draining = false;
    }
  }

  /// Runs one job, retrying until it succeeds or gives up.
  Future<bool> _attempt(SyncJob job) async {
    while (true) {
      try {
        await job.run();
        return true;
      } on SyncException catch (error) {
        job.attempts++;
        job.lastFailure = error.failure;

        if (!error.failure.isTransient) {
          _abandoned[job.id] = job;
          return false;
        }
        if (job.attempts >= _maximumAttempts) {
          _abandoned[job.id] = job;
          return false;
        }
        await _delay(_backoffFor(job.attempts));
      }
    }
  }

  /// Back-off before attempt [attempt], doubling and capped.
  ///
  /// Capped rather than unbounded because the common failure is simply being
  /// offline for a day or two; an uncapped doubling would push the next try past
  /// the point where the user is likely to still have the app installed.
  Duration _backoffFor(int attempt) {
    final micros = _initialBackoff.inMicroseconds * (1 << (attempt - 1));
    return micros >= _maximumBackoff.inMicroseconds
        ? _maximumBackoff
        : Duration(microseconds: micros);
  }

  /// Forgets a job that will never succeed, so the count stops alarming the user.
  void discardAbandoned() => _abandoned.clear();

  /// Drops everything without sending it. Used when the user turns sync off.
  void clear() {
    _pending.clear();
    _abandoned.clear();
  }
}
