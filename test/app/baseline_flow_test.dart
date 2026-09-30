/// What the user sees from the first session to the first verdict.
///
/// The baseline is three sessions after two of familiarisation, and it only sets the
/// reference point. A status, trends and a report then wait for eight more tests, because a
/// verdict from fewer points is mostly noise. Until then the app shows how far along the user
/// is instead.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:neurascan_ai/app/router.dart';
import 'package:neurascan_ai/data/models.dart';
import 'package:neurascan_ai/engine/constants.dart';
import 'package:neurascan_ai/engine/features.dart' show EngineSession;
import 'package:neurascan_ai/engine/screening_engine.dart';
import 'package:neurascan_ai/features/dashboard/dashboard_screen.dart';

import '../engine/engine_test_support.dart';
import 'test_harness.dart';

void main() {
  test('the session counts are as decided', () {
    // Pinned so that changing them is a deliberate act, not something a refactor does
    // quietly. See the notes on kBaselineSessions and kMinMonitoringSessions.
    expect(kBaselineSessions, 3);
    expect(kFamiliarisationSessions, 2);
    expect(kMinMonitoringSessions, 8);
  });

  test('the verdict needs more evidence than the baseline does', () {
    // The reference point can be quick to set; the trend built on it cannot.
    expect(kMinMonitoringSessions, greaterThan(kBaselineSessions));
  });

  /// Sessions that make up a user's history, in order: familiarisation, the baseline, then
  /// [monitoring] tests. Entries in [setAside] are reported as tired on the check-in.
  List<({EngineSession session, bool setAside})> history({
    required int monitoring,
    Set<int> setAside = const {},
  }) => [
    for (var i = 0; i < kFamiliarisationSessions; i++)
      (session: makeSession(), setAside: false),
    for (final s in variedBaselineSessions()) (session: s, setAside: false),
    for (var i = 0; i < monitoring; i++)
      (
        session: makeSession(confounded: setAside.contains(i)),
        setAside: setAside.contains(i),
      ),
  ];

  /// Stores [plan] for the signed-in user, driving a real engine so the stored statuses are
  /// the ones the app would have produced.
  Future<void> seed(
    TestApp app,
    List<({EngineSession session, bool setAside})> plan,
  ) async {
    final engine = ScreeningEngine();
    for (var i = 0; i < plan.length; i++) {
      final at = DateTime.now().subtract(Duration(days: (plan.length - i) * 2));
      final result = engine.update(plan[i].session);
      await app.repository.saveSession(
        session: SessionRecord(
          id: 'seed-$i',
          userId: 'user-1',
          startedAt: at,
          completedAt: at.add(const Duration(minutes: 4)),
          checkIn: plan[i].setAside
              ? CheckIn(
                  sleep: SleepQuality.poor,
                  fatigue: FatigueLevel.none,
                  illnessOrMedicationChange: false,
                  answeredAt: at,
                )
              : CheckIn.unremarkable(at),
          features: plan[i].session.features,
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

  group('the baseline', () {
    testWidgets('one session in: still building', (tester) async {
      final app = await dashboard(tester);
      await seed(app, history(monitoring: 0).take(1).toList());
      await tester.pumpAndSettle();

      expect(find.textContaining('Building your baseline'), findsOneWidget);
      expect(find.text('Your baseline is set'), findsNothing);
    });

    testWidgets('the countdown is out of the pool size, not more', (
      tester,
    ) async {
      final app = await dashboard(tester);
      // Two familiarisation and one pooled.
      await seed(app, history(monitoring: 0).take(3).toList());
      await tester.pumpAndSettle();

      expect(
        find.textContaining(
          'Building your baseline: 1 of $kBaselineSessions sessions',
        ),
        findsOneWidget,
      );
    });

    testWidgets('one short of the end: not set yet', (tester) async {
      final app = await dashboard(tester);
      await seed(
        app,
        history(monitoring: 0)
            .take(kFamiliarisationSessions + kBaselineSessions - 1)
            .toList(),
      );
      await tester.pumpAndSettle();

      expect(find.text('Your baseline is set'), findsNothing);
    });

    testWidgets('the moment it is complete, the dashboard says so', (
      tester,
    ) async {
      final app = await dashboard(tester);
      await seed(app, history(monitoring: 0));
      await tester.pumpAndSettle();

      expect(find.text('Your baseline is set'), findsOneWidget);
      expect(find.textContaining('Building your baseline'), findsNothing);
    });

    testWidgets('and says how many more tests are needed', (tester) async {
      final app = await dashboard(tester);
      await seed(app, history(monitoring: 0));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('$kMinMonitoringSessions more tests'),
        findsWidgets,
      );
      expect(
        find.text('0 of $kMinMonitoringSessions tests after your baseline'),
        findsOneWidget,
      );
    });
  });

  group('before eight tests', () {
    testWidgets('trends show progress, not a chart', (tester) async {
      final app = await dashboard(tester);
      await seed(app, history(monitoring: 3));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Trends'));
      await tester.pumpAndSettle();

      expect(
        find.text('3 of $kMinMonitoringSessions tests after your baseline'),
        findsOneWidget,
      );
      expect(find.textContaining('close to zero by design'), findsNothing);
    });

    testWidgets('the dashboard shows progress and no status', (tester) async {
      final app = await dashboard(tester);
      await seed(app, history(monitoring: 3));
      await tester.pumpAndSettle();

      expect(find.text('Gathering your first results'), findsOneWidget);
      expect(
        find.text('3 of $kMinMonitoringSessions tests after your baseline'),
        findsOneWidget,
      );
      // A verdict from three tests could be mostly noise, so none is shown.
      expect(find.text('Stable'), findsNothing);
      expect(find.text('Worth watching'), findsNothing);
      expect(find.text('A notable change'), findsNothing);
      expect(find.text('See the full report'), findsNothing);
    });

    testWidgets('seven tests is still not enough', (tester) async {
      final app = await dashboard(tester);
      await seed(app, history(monitoring: kMinMonitoringSessions - 1));
      await tester.pumpAndSettle();

      expect(find.text('Gathering your first results'), findsOneWidget);
      expect(find.text('Stable'), findsNothing);
    });

    testWidgets('the report is withheld too', (tester) async {
      final app = await dashboard(tester);
      await seed(app, history(monitoring: 5));
      await tester.pumpAndSettle();

      app.container.read(routerProvider).go(Routes.report);
      await tester.pumpAndSettle();

      expect(
        find.text('5 of $kMinMonitoringSessions tests after your baseline'),
        findsOneWidget,
      );
      expect(find.text('Save or share this report'), findsNothing);
    });

    testWidgets('a scored test is recorded without a verdict', (tester) async {
      final app = await dashboard(tester);
      await seed(app, history(monitoring: 2));
      await tester.pumpAndSettle();

      app.container
          .read(routerProvider)
          .go(
            '${Routes.summary}?sessionId=seed-${kFamiliarisationSessions + kBaselineSessions + 1}',
          );
      await tester.pumpAndSettle();

      expect(
        find.text('This test has been added to your record.'),
        findsOneWidget,
      );
      expect(find.text('Stable'), findsNothing);
      expect(find.text('See the full report'), findsNothing);
    });

    testWidgets('sessions set aside do not count towards the eight', (
      tester,
    ) async {
      // Eight tests were taken, but three were reported as tired, so only five count.
      final app = await dashboard(tester);
      await seed(
        app,
        history(monitoring: kMinMonitoringSessions, setAside: {1, 3, 5}),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('5 of $kMinMonitoringSessions tests after your baseline'),
        findsOneWidget,
      );
      expect(find.text('Stable'), findsNothing);
    });

    testWidgets('the baseline sessions themselves do not count either', (
      tester,
    ) async {
      final app = await dashboard(tester);
      await seed(app, history(monitoring: 0));
      await tester.pumpAndSettle();

      expect(
        find.text('0 of $kMinMonitoringSessions tests after your baseline'),
        findsOneWidget,
      );
    });
  });

  group('at eight tests', () {
    testWidgets('the verdict appears', (tester) async {
      final app = await dashboard(tester);
      await seed(app, history(monitoring: kMinMonitoringSessions));
      await tester.pumpAndSettle();

      expect(find.text('Gathering your first results'), findsNothing);
      expect(find.text('Stable'), findsOneWidget);
    });

    testWidgets('and the report becomes available', (tester) async {
      final app = await dashboard(tester);
      await seed(app, history(monitoring: kMinMonitoringSessions));
      await tester.pumpAndSettle();

      expect(find.text('See the full report'), findsOneWidget);
    });

    testWidgets('and trends appear, from the user\'s own data', (tester) async {
      final app = await dashboard(tester);
      await seed(app, history(monitoring: kMinMonitoringSessions));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Trends'));
      await tester.pumpAndSettle();

      expect(find.textContaining('tests after your baseline'), findsNothing);
      expect(find.textContaining('close to zero by design'), findsOneWidget);
    });

    testWidgets('one test set aside in the middle delays it by one', (
      tester,
    ) async {
      final app = await dashboard(tester);
      // Nine taken, one set aside: eight count.
      await seed(
        app,
        history(monitoring: kMinMonitoringSessions + 1, setAside: {4}),
      );
      await tester.pumpAndSettle();

      expect(find.text('Stable'), findsOneWidget);
    });

    testWidgets('the eighth test\'s summary shows its status', (tester) async {
      final app = await dashboard(tester);
      await seed(app, history(monitoring: kMinMonitoringSessions));
      await tester.pumpAndSettle();

      const last =
          kFamiliarisationSessions +
          kBaselineSessions +
          kMinMonitoringSessions -
          1;
      app.container
          .read(routerProvider)
          .go('${Routes.summary}?sessionId=seed-$last');
      await tester.pumpAndSettle();

      expect(find.text('Stable'), findsOneWidget);
      expect(
        find.text('This test has been added to your record.'),
        findsNothing,
      );
      expect(find.text('See the full report'), findsOneWidget);
    });

    testWidgets('all four areas are broken down on the summary', (
      tester,
    ) async {
      final app = await dashboard(tester);
      await seed(app, history(monitoring: kMinMonitoringSessions));
      await tester.pumpAndSettle();

      const last =
          kFamiliarisationSessions +
          kBaselineSessions +
          kMinMonitoringSessions -
          1;
      app.container
          .read(routerProvider)
          .go('${Routes.summary}?sessionId=seed-$last');
      await tester.pumpAndSettle();

      // All four, including any that contributed nothing: a breakdown that hid the quiet
      // areas would make a single-area change look like the only thing measured.
      for (final label in ['Thinking', 'Speech', 'Movement', 'Typing']) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      expect(find.text('What this is based on'), findsOneWidget);
    });
  });
}
