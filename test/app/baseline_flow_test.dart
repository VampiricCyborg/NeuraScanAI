/// What the user sees as the baseline completes.
///
/// The baseline is four sessions after two of familiarisation. The moment it is complete the
/// app should say so and show trends built from the user's own data, rather than sitting on
/// "building your baseline" until yet another session.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:neurascan_ai/data/models.dart';
import 'package:neurascan_ai/engine/constants.dart';
import 'package:neurascan_ai/engine/screening_engine.dart';
import 'package:neurascan_ai/features/dashboard/dashboard_screen.dart';

import '../engine/engine_test_support.dart';
import 'test_harness.dart';

void main() {
  test('the baseline is four sessions, as decided', () {
    // Pinned so that changing it is a deliberate act with the report's simulation in mind,
    // not something a refactor does quietly. See the note on kBaselineSessions.
    expect(kBaselineSessions, 4);
    expect(kFamiliarisationSessions, 2);
  });

  /// Stores [count] sessions for the signed-in user, driving a real engine so the stored
  /// statuses are the ones the app would have produced.
  Future<void> seedSessions(TestApp app, int count) async {
    final engine = ScreeningEngine();
    final plan = [
      makeSession(),
      makeSession(),
      ...variedBaselineSessions(),
      for (var i = 0; i < 4; i++) makeSession(),
    ];

    for (var i = 0; i < count; i++) {
      final at = DateTime.now().subtract(Duration(days: (count - i) * 2));
      final result = engine.update(plan[i]);
      await app.repository.saveSession(
        session: SessionRecord(
          id: 'seed-$i',
          userId: 'user-1',
          startedAt: at,
          completedAt: at.add(const Duration(minutes: 4)),
          checkIn: CheckIn.unremarkable(at),
          features: plan[i].features,
          valid: true,
          status: result.status,
          index: result.index,
          ewma: result.ewma,
          run: result.run,
          domainScores: result.domains,
          contributions: result.contributions,
        ),
        engine: engine,
      );
    }
  }

  Future<TestApp> dashboard(WidgetTester tester) async {
    final app = await pumpApp(tester, signedIn: consentPendingAccount);
    await completeOnboarding(app);
    await tester.pumpAndSettle();
    expect(find.byType(DashboardScreen), findsOneWidget);
    return app;
  }

  testWidgets('one session in: the baseline is still building', (tester) async {
    final app = await dashboard(tester);
    await seedSessions(app, 1);
    await tester.pumpAndSettle();

    expect(find.textContaining('Building your baseline'), findsOneWidget);
    expect(find.text('Your baseline is set'), findsNothing);
  });

  testWidgets('the countdown reaches the pool size, not more', (tester) async {
    final app = await dashboard(tester);
    // Two familiarisation and one pooled.
    await seedSessions(app, 3);
    await tester.pumpAndSettle();

    expect(
      find.textContaining(
        'Building your baseline: 1 of $kBaselineSessions sessions',
      ),
      findsOneWidget,
    );
  });

  testWidgets('one session short of the end, trends are still empty', (
    tester,
  ) async {
    final app = await dashboard(tester);
    await seedSessions(app, kFamiliarisationSessions + kBaselineSessions - 1);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Trends'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Your trends will appear'), findsOneWidget);
  });

  testWidgets('the moment the baseline is complete, the dashboard says so', (
    tester,
  ) async {
    final app = await dashboard(tester);
    await seedSessions(app, kFamiliarisationSessions + kBaselineSessions);
    await tester.pumpAndSettle();

    expect(find.text('Your baseline is set'), findsOneWidget);
    // Not the "building" state for a baseline that is finished.
    expect(find.textContaining('Building your baseline'), findsNothing);
  });

  testWidgets('and trends are there immediately, from the user\'s own data', (
    tester,
  ) async {
    // This used to need a fifth session, because the four that built the baseline were never
    // plotted.
    final app = await dashboard(tester);
    await seedSessions(app, kFamiliarisationSessions + kBaselineSessions);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Trends'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Your trends will appear'), findsNothing);
    expect(find.textContaining('close to zero by design'), findsOneWidget);
  });

  testWidgets('a session after the baseline is scored and the card changes', (
    tester,
  ) async {
    final app = await dashboard(tester);
    await seedSessions(app, kFamiliarisationSessions + kBaselineSessions + 1);
    await tester.pumpAndSettle();

    expect(find.text('Your baseline is set'), findsNothing);
    expect(find.text('Stable'), findsOneWidget);
  });
}
