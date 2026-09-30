/// Helpers for driving the app in widget tests.
///
/// The point of the provider indirection in `lib/app/providers.dart` is that the whole app
/// can run here: an in-memory database, a fake auth service and a recording sync backend,
/// with no emulator, no platform channels and no cloud project. Everything above the data
/// layer is then testable, including the router's redirects, which are where the consent
/// gate actually lives.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neurascan_ai/app/l10n/generated/app_localizations.dart';
import 'package:neurascan_ai/app/providers.dart';
import 'package:neurascan_ai/app/router.dart';
import 'package:neurascan_ai/app/theme.dart';
import 'package:neurascan_ai/data/auth_service.dart';
import 'package:neurascan_ai/data/local_db.dart';
import 'package:neurascan_ai/data/models.dart';
import 'package:neurascan_ai/data/repository.dart';
import 'package:neurascan_ai/data/sync_service.dart';
import 'package:neurascan_ai/engine/baseline.dart' as engine;
import 'package:neurascan_ai/features/session/session_controller.dart';
import 'package:neurascan_ai/services/audio_capture.dart';

/// An auth service backed by a list, with no storage and no platform channels.
class FakeAuthService implements AuthService {
  FakeAuthService({AuthAccount? signedIn}) : _current = signedIn {
    _controller = StreamController<AuthAccount?>.broadcast(
      // Replays the current account to each new listener, which is what the real
      // implementation does after restoring a stored session.
      onListen: () => _controller.add(_current),
    );
  }

  late final StreamController<AuthAccount?> _controller;
  AuthAccount? _current;

  /// Set to make the next call throw.
  AuthFailure? nextFailure;

  int signOutCount = 0;
  int deleteCount = 0;

  @override
  AuthAccount? get currentAccount => _current;

  @override
  Stream<AuthAccount?> authStateChanges() async* {
    yield _current;
    yield* _controller.stream;
  }

  void _maybeFail() {
    final failure = nextFailure;
    if (failure != null) {
      nextFailure = null;
      throw AuthException(failure);
    }
  }

  @override
  Future<AuthAccount> signIn({
    required String email,
    required String password,
  }) async {
    _maybeFail();
    return _emit(AuthAccount(id: 'user-1', email: email));
  }

  @override
  Future<AuthAccount> register({
    required String email,
    required String password,
    String? displayName,
  }) async {
    _maybeFail();
    return _emit(
      AuthAccount(id: 'user-1', email: email, displayName: displayName),
    );
  }

  @override
  Future<void> signOut() async {
    signOutCount++;
    _current = null;
    _controller.add(null);
  }

  @override
  Future<void> deleteAccount() async {
    deleteCount++;
    await signOut();
  }

  AuthAccount _emit(AuthAccount account) {
    _current = account;
    _controller.add(account);
    return account;
  }

  Future<void> dispose() => _controller.close();
}

/// Records what was uploaded.
class FakeSyncBackend implements SyncBackend {
  final sessions = <SessionRecord>[];
  final profiles = <UserProfile>[];
  final deleted = <String>[];

  @override
  Future<void> upsertProfile(UserProfile profile) async =>
      profiles.add(profile);

  @override
  Future<void> upsertSession(SessionRecord session) async =>
      sessions.add(session);

  @override
  Future<void> upsertBaseline(String userId, engine.Baseline baseline) async {}

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
  Future<void> deleteEverything(String userId) async => deleted.add(userId);
}

/// Everything a test needs to reach into the running app.
class TestApp {
  TestApp({
    required this.container,
    required this.database,
    required this.auth,
    required this.backend,
  });

  final ProviderContainer container;
  final LocalDatabase database;
  final FakeAuthService auth;
  final FakeSyncBackend backend;

  Repository get repository => container.read(repositoryProvider);

  /// Order matters. The container goes first because the app is still subscribed to the auth
  /// stream: closing a broadcast controller waits for its listeners, so closing it while the
  /// router was listening hung the test's teardown until the ten-minute timeout.
  Future<void> dispose() async {
    container.dispose();
    await auth.dispose();
    await database.close();
  }
}

/// Pumps the whole app with test doubles in place.
///
/// Returns the handles a test needs. Registers its own teardown, so a test does not have to
/// remember to close the database.
Future<TestApp> pumpApp(
  WidgetTester tester, {
  AuthAccount? signedIn,
  AudioCaptureService? audio,
  Locale? locale,
  bool settle = true,
}) async {
  // A tall, narrow surface like a phone. The default 800x600 is landscape and short, and the
  // consent and settings screens are lazy lists: whatever is below the fold is never built,
  // so a test looking for the consent checkbox found nothing.
  tester.view
    ..physicalSize = const Size(420, 2400)
    ..devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final database = LocalDatabase.forTesting();
  final auth = FakeAuthService(signedIn: signedIn);
  final backend = FakeSyncBackend();

  final container = ProviderContainer(
    overrides: [
      localDatabaseProvider.overrideWithValue(database),
      authServiceProvider.overrideWithValue(auth),
      syncBackendProvider.overrideWithValue(backend),
      if (audio != null) audioCaptureProvider.overrideWithValue(audio),
    ],
  );

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: _TestRoot(locale: locale),
    ),
  );
  // Settling resolves the auth stream and then the redirect it triggers. A test that wants
  // to observe the loading state passes settle: false and pumps by hand.
  if (settle) {
    await tester.pumpAndSettle();
  }

  final app = TestApp(
    container: container,
    database: database,
    auth: auth,
    backend: backend,
  );
  // Closing the database awaits real asynchronous work, which never completes inside the
  // widget test's fake-async zone -- the teardown hung for the full ten-minute test timeout
  // with the test body itself already finished. runAsync steps outside that zone.
  addTearDown(() async {
    await tester.runAsync(app.dispose);
  });
  return app;
}

/// The app under test.
///
/// Built from the same router and theme as `main.dart` rather than a stand-in, so that the
/// redirects being tested are the real ones.
class _TestRoot extends ConsumerWidget {
  const _TestRoot({this.locale});

  final Locale? locale;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      routerConfig: ref.watch(routerProvider),
      theme: buildTheme(Brightness.light),
      locale: locale ?? ref.watch(localeProvider),
      localizationsDelegates: AppText.localizationsDelegates,
      supportedLocales: AppText.supportedLocales,
    );
  }
}

/// Signs a user in and records consent, so a test can start at the dashboard.
Future<UserProfile> completeOnboarding(
  TestApp app, {
  bool syncEnabled = false,
}) async {
  final account = app.auth.currentAccount!;
  final profile = await app.repository.ensureProfile(
    userId: account.id,
    email: account.email,
    displayName: account.displayName,
  );
  return app.repository.recordConsent(
    profile: profile,
    syncEnabled: syncEnabled,
  );
}

/// Skips the onboarding to reach the sign-in screen.
///
/// A signed-out launch lands on the onboarding, which is the flow the report specifies, so a
/// test that wants the sign-in form has to pass through it.
Future<void> reachLogin(WidgetTester tester) async {
  await tester.tap(find.text('Skip'));
  await tester.pumpAndSettle();
}

/// An account that is signed in but has not consented.
const consentPendingAccount = AuthAccount(
  id: 'user-1',
  email: 'someone@example.com',
  displayName: 'Test User',
);
