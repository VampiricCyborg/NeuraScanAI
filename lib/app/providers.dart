/// Dependency wiring.
///
/// Everything the app needs is reached through a provider here, and every one of
/// them can be overridden in a test. That is what lets the screens be tested
/// without an emulator, a device or a cloud project: a widget test overrides the
/// database with an in-memory one and the auth service with a fake, and the rest of
/// the app does not know the difference.
///
/// The choice of whether the cloud is used at all is made in exactly one place --
/// [syncBackendProvider] -- so there is no `if (syncEnabled)` scattered through the
/// repository waiting to be forgotten in one of them.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/auth_service.dart';
import '../data/local_db.dart';
import '../data/models.dart';
import '../data/repository.dart';
import '../data/sync_service.dart';
import '../engine/constants.dart';
import '../engine/screening_engine.dart';
import '../services/notifications.dart';

// -- infrastructure -----------------------------------------------------------

/// The encrypted local database.
///
/// Overridden with [LocalDatabase.forTesting] in tests.
final localDatabaseProvider = Provider<LocalDatabase>((ref) {
  final database = LocalDatabase.encrypted();
  ref.onDispose(database.close);
  return database;
});

/// Where derived scores go when the user has turned sync on.
///
/// The disabled backend is the default, and it is the only thing that needs to
/// change to bring a cloud project into play: override this with a Firestore
/// implementation and the rest of the app is unchanged.
final syncBackendProvider = Provider<SyncBackend>(
  (ref) => const DisabledSyncBackend(),
);

/// The retrying upload queue.
final syncQueueProvider = Provider<SyncQueue>(
  (ref) => SyncQueue(backend: ref.watch(syncBackendProvider)),
);

/// Reads and writes everything the app stores.
final repositoryProvider = Provider<Repository>(
  (ref) => Repository(
    database: ref.watch(localDatabaseProvider),
    syncQueue: ref.watch(syncQueueProvider),
  ),
);

/// Sign-in. Local by default, so the app works with no cloud project.
final authServiceProvider = Provider<AuthService>((ref) {
  final service = LocalAuthService();
  ref.onDispose(service.dispose);
  return service;
});

/// Schedules the session reminders.
final notificationServiceProvider = Provider<NotificationService>(
  (ref) => NotificationService(),
);

// -- authentication state -----------------------------------------------------

/// The signed-in account, and every later change.
///
/// The router redirects on this, so a token expiring or an account deleted
/// elsewhere takes the user back to sign-in without anything having to poll.
final authStateProvider = StreamProvider<AuthAccount?>(
  (ref) => ref.watch(authServiceProvider).authStateChanges(),
);

/// The signed-in account, or null while loading or signed out.
final currentAccountProvider = Provider<AuthAccount?>(
  (ref) => ref.watch(authStateProvider).value,
);

/// The signed-in user's id.
final currentUserIdProvider = Provider<String?>(
  (ref) => ref.watch(currentAccountProvider)?.id,
);

// -- profile ------------------------------------------------------------------

/// The signed-in user's profile, kept current as settings change.
///
/// Creates the row on first sight of a new account, so no screen has to remember
/// to do it. Returns null when signed out.
final profileProvider = StreamProvider<UserProfile?>((ref) async* {
  final account = ref.watch(currentAccountProvider);
  if (account == null) {
    yield null;
    return;
  }

  final repository = ref.watch(repositoryProvider);
  await repository.ensureProfile(
    userId: account.id,
    email: account.email,
    displayName: account.displayName,
  );
  yield* repository.watchProfile(account.id);
});

/// The locale the user chose, or null to follow the device.
final localeProvider = Provider<Locale?>((ref) {
  final code = ref.watch(profileProvider).value?.languageCode;
  return code == null ? null : Locale(code);
});

// -- sessions and engine ------------------------------------------------------

/// Every stored session for the signed-in user, oldest first.
final sessionsProvider = StreamProvider<List<SessionRecord>>((ref) {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return Stream.value(const []);
  return ref.watch(repositoryProvider).watchSessions(userId);
});

/// The engine, rebuilt from stored state.
///
/// A future rather than a value because the baseline has to be read from the
/// database. Screens show a spinner for the moment it takes; there is no useful
/// dashboard to draw before it resolves anyway.
final engineProvider = FutureProvider<ScreeningEngine>((ref) async {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return ScreeningEngine();

  // Rebuilt whenever the sessions change, so the dashboard's baseline progress
  // reflects a session that has just been saved.
  ref.watch(sessionsProvider);
  return ref.watch(repositoryProvider).loadEngine(userId);
});

/// The most recent scored session, which is what the dashboard shows.
///
/// The last *scored* one rather than the last attempt: an invalid or confounded
/// session should not blank out the standing result.
final latestScoredSessionProvider = Provider<SessionRecord?>((ref) {
  final sessions = ref.watch(sessionsProvider).value ?? const [];
  for (final session in sessions.reversed) {
    if (session.countsTowardsTrend) return session;
  }
  return null;
});

/// The status to show on the dashboard.
final currentStatusProvider = Provider<ScreeningStatus>((ref) {
  final engine = ref.watch(engineProvider).value;
  if (engine == null || !engine.baselineReady) {
    return ScreeningStatus.buildingBaseline;
  }
  return ref.watch(latestScoredSessionProvider)?.status ??
      ScreeningStatus.buildingBaseline;
});

/// The full tests taken after the baseline that were scored, oldest first.
///
/// Tests the check-in set aside, and those that went into the baseline itself, are not
/// included. Each of these was compared with the baseline, so each is a point on the trend
/// and something to compare the next test with.
final actualTestsProvider = Provider<List<SessionRecord>>((ref) {
  final sessions = ref.watch(sessionsProvider).value ?? const [];
  return [
    for (final session in sessions)
      if (session.countsTowardsTrend) session,
  ];
});

/// How many full tests have been scored.
final scoredSessionCountProvider = Provider<int>(
  (ref) => ref.watch(actualTestsProvider).length,
);

/// Whether there is a result to show: a status, a comparison and a report.
///
/// True from the first full test. Each of those tests is eight steps with every measurement
/// taken several times, so a single one is a measurement in its own right, and the app does
/// not make the user wait for a run of them. What it does not do is call a change "notable"
/// from one test: that needs the smoothed score to stay above the line for
/// [kDefaultPersistence] tests, so the first results are honest about being early.
final verdictReadyProvider = Provider<bool>((ref) {
  final baselineReady = ref.watch(engineProvider).value?.baselineReady ?? false;
  return baselineReady && ref.watch(scoredSessionCountProvider) >= 1;
});

/// How far the baseline is: tests done, out of how many.
///
/// The first baseline is four tests, the first a practice run; a later one is three, because
/// the user has already met the tasks.
typedef BaselineTestProgress = ({int done, int total, bool practicePending});

final baselineTestProgressProvider = Provider<BaselineTestProgress>((ref) {
  final sessions = ref.watch(sessionsProvider).value ?? const [];
  final hasPractice =
      (ref.watch(profileProvider).value?.baselineEpoch ?? 0) == 0;
  final remaining = ref
      .watch(repositoryProvider)
      .baselineSessionsRemaining(sessions);
  final practiceDone = hasPractice && sessions.isNotEmpty;
  final total = hasPractice ? kBaselineTests : kBaselineSessions;
  final done = (kBaselineSessions - remaining) + (practiceDone ? 1 : 0);
  return (
    done: done.clamp(0, total),
    total: total,
    practicePending: hasPractice && !practiceDone,
  );
});
