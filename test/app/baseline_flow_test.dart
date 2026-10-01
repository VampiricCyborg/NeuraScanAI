/// What the user sees from the first test to the results of each full test.
///
/// The baseline is four short tests of three steps, the first a practice run that does not
/// count. After it, the user takes full tests of eight steps whenever they like, and each one
/// is compared with the baseline and with the test before it straight away. Before the first
/// full test the app shows how the measurements work instead of a result.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neurascan_ai/app/router.dart';
import 'package:neurascan_ai/engine/constants.dart';
import 'package:neurascan_ai/features/dashboard/dashboard_screen.dart';

import 'seed_history.dart';
import 'test_harness.dart';

void main() {
  test('the test counts are as decided', () {
    // Pinned so that changing them is a deliberate act, not something a refactor does
    // quietly.
    expect(kFamiliarisationSessions, 1);
    expect(kBaselineSessions, 3);
    expect(kBaselineTests, 4);
    expect(kBaselineTestSteps, 3);
    expect(kActualTestSteps, 8);
  });

  test('a full test is more thorough than a baseline test', () {
    // The reference point can be quick to set; the tests compared with it cannot.
    expect(kActualTestSteps, greaterThan(kBaselineTestSteps));
  });

  Future<TestApp> dashboard(WidgetTester tester) async {
    final app = await pumpApp(tester, signedIn: consentPendingAccount);
    await completeOnboarding(app);
    await tester.pumpAndSettle();
    expect(find.byType(DashboardScreen), findsOneWidget);
    return app;
  }

  const firstFullTest = kFamiliarisationSessions + kBaselineSessions;

  group('the baseline', () {
    testWidgets('no test yet: the practice test is offered', (tester) async {
      await dashboard(tester);

      expect(
        find.text('Building your baseline: 0 of $kBaselineTests tests'),
        findsOneWidget,
      );
      expect(find.text('Start the practice test'), findsOneWidget);
    });

    testWidgets('the practice test counts towards the four', (tester) async {
      final app = await dashboard(tester);
      await seed(app, history(actual: 0).take(1).toList());
      await tester.pumpAndSettle();

      expect(
        find.text('Building your baseline: 1 of $kBaselineTests tests'),
        findsOneWidget,
      );
      expect(find.text('Your baseline is set'), findsNothing);
      expect(
        find.text('Start baseline test 2 of $kBaselineTests'),
        findsOneWidget,
      );
    });

    testWidgets('the countdown is out of four, not more', (tester) async {
      final app = await dashboard(tester);
      // The practice test and one pooled.
      await seed(app, history(actual: 0).take(2).toList());
      await tester.pumpAndSettle();

      expect(
        find.text('Building your baseline: 2 of $kBaselineTests tests'),
        findsOneWidget,
      );
    });

    testWidgets('one short of the end: not set yet', (tester) async {
      final app = await dashboard(tester);
      await seed(app, history(actual: 0).take(firstFullTest - 1).toList());
      await tester.pumpAndSettle();

      expect(find.text('Your baseline is set'), findsNothing);
      expect(find.text('One more test to go'), findsOneWidget);
    });

    testWidgets('the moment it is complete, the dashboard says so', (
      tester,
    ) async {
      final app = await dashboard(tester);
      await seed(app, history(actual: 0));
      await tester.pumpAndSettle();

      expect(find.text('Your baseline is set'), findsOneWidget);
      expect(find.textContaining('Building your baseline'), findsNothing);
    });

    testWidgets('and offers a full test to take whenever the user likes', (
      tester,
    ) async {
      final app = await dashboard(tester);
      await seed(app, history(actual: 0));
      await tester.pumpAndSettle();

      expect(find.text('Take a full test'), findsOneWidget);
      expect(find.textContaining('Eight different steps'), findsOneWidget);
    });
  });

  group('before the first full test', () {
    testWidgets('trends invite a first test and show labelled examples', (
      tester,
    ) async {
      // Right after the baseline the user has no results, so the tab shows how the
      // measurements work: their real baseline, and simulated runs scored against it.
      final app = await dashboard(tester);
      await seed(app, history(actual: 0));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Trends'));
      await tester.pumpAndSettle();

      expect(find.text('Take your first full test'), findsOneWidget);
      expect(find.text('Your baseline'), findsWidgets);
      expect(find.text('Example, not your data'), findsWidgets);
      expect(
        find.textContaining('simulated from your own baseline'),
        findsOneWidget,
      );
    });

    testWidgets('the examples are not shown before the baseline exists', (
      tester,
    ) async {
      final app = await dashboard(tester);
      await seed(app, history(actual: 0).take(2).toList());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Trends'));
      await tester.pumpAndSettle();

      expect(find.text('Example, not your data'), findsNothing);
    });

    testWidgets('the dashboard shows no status yet', (tester) async {
      final app = await dashboard(tester);
      await seed(app, history(actual: 0));
      await tester.pumpAndSettle();

      expect(find.text('Within your usual range'), findsNothing);
      expect(find.text('Mild change'), findsNothing);
      expect(find.text('Notable change that has persisted'), findsNothing);
      expect(find.text('See the full report'), findsNothing);
    });

    testWidgets('the report waits for the first full test', (tester) async {
      final app = await dashboard(tester);
      await seed(app, history(actual: 0));
      await tester.pumpAndSettle();

      app.container.read(routerProvider).go(Routes.report);
      await tester.pumpAndSettle();

      expect(
        find.text('Your report is ready after your first full test.'),
        findsOneWidget,
      );
      expect(find.text('Save or share this report'), findsNothing);
    });

    testWidgets('a test set aside does not count as the first', (tester) async {
      // Reported as tired on the check-in, so it is stored but not scored.
      final app = await dashboard(tester);
      await seed(app, history(actual: 1, setAside: {0}));
      await tester.pumpAndSettle();

      expect(find.text('Your baseline is set'), findsOneWidget);
      expect(find.text('Within your usual range'), findsNothing);
    });
  });

  group('straight after the first full test', () {
    testWidgets('the dashboard shows the status', (tester) async {
      final app = await dashboard(tester);
      await seed(app, history(actual: 1));
      await tester.pumpAndSettle();

      expect(find.text('Your baseline is set'), findsNothing);
      expect(find.text('Within your usual range'), findsOneWidget);
    });

    testWidgets('and the report is available', (tester) async {
      final app = await dashboard(tester);
      await seed(app, history(actual: 1));
      await tester.pumpAndSettle();

      expect(find.text('See the full report'), findsOneWidget);
    });

    testWidgets('and trends show a comparison instead of the invitation', (
      tester,
    ) async {
      final app = await dashboard(tester);
      await seed(app, history(actual: 1));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Trends'));
      await tester.pumpAndSettle();

      expect(find.text('Take your first full test'), findsNothing);
      // The three views, and the first of them is the latest test with its eight cards.
      expect(find.text('Latest test'), findsOneWidget);
      expect(find.text('Every test'), findsOneWidget);
      expect(find.text('Within your usual range'), findsOneWidget);
      expect(find.text('Word memory'), findsOneWidget);

      // Nothing earlier to compare with, and the card says so.
      await tester.tap(find.text('Word memory'));
      await tester.pumpAndSettle();
      expect(find.text('No earlier counted test yet.'), findsWidgets);
    });

    testWidgets('the summary shows an early status and the comparison', (
      tester,
    ) async {
      final app = await dashboard(tester);
      await seed(app, history(actual: 1));
      await tester.pumpAndSettle();

      app.container
          .read(routerProvider)
          .go('${Routes.summary}?sessionId=seed-$firstFullTest');
      await tester.pumpAndSettle();

      expect(find.text('Within your usual range'), findsOneWidget);
      expect(find.textContaining('This is an early result'), findsOneWidget);
      expect(find.text('Word memory'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('See the full report'),
        400,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('See the full report'), findsOneWidget);
    });

    testWidgets('all four areas are broken down on the summary', (
      tester,
    ) async {
      final app = await dashboard(tester);
      await seed(app, history(actual: 1));
      await tester.pumpAndSettle();

      app.container
          .read(routerProvider)
          .go('${Routes.summary}?sessionId=seed-$firstFullTest');
      await tester.pumpAndSettle();

      // All three, including any that contributed nothing: a breakdown that hid the quiet
      // areas would make a single-area change look like the only thing measured.
      for (final label in ['Thinking', 'Speech', 'Movement', 'Typing']) {
        expect(find.text(label), findsWidgets, reason: label);
      }
      expect(find.text('What this is based on'), findsOneWidget);
    });
  });

  group('after each further full test', () {
    testWidgets('the second is compared with the first', (tester) async {
      final app = await dashboard(tester);
      await seed(app, history(actual: 2));
      await tester.pumpAndSettle();

      app.container
          .read(routerProvider)
          .go('${Routes.summary}?sessionId=seed-${firstFullTest + 1}');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Word memory'));
      await tester.pumpAndSettle();
      expect(find.text('Against your earlier tests'), findsWidgets);
      expect(find.textContaining('Last test'), findsWidgets);
      expect(find.text('No earlier counted test yet.'), findsNothing);
      // No longer the first, so no early-result note.
      expect(find.textContaining('This is an early result'), findsNothing);
    });

    testWidgets('trends compare the latest test with the one before', (
      tester,
    ) async {
      final app = await dashboard(tester);
      await seed(app, history(actual: 3));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Trends'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Word memory'));
      await tester.pumpAndSettle();
      expect(find.text('Against your baseline'), findsWidgets);
      expect(find.text('Against your earlier tests'), findsWidgets);

      // The charts are on their own tab.
      await tester.tap(
        find.descendant(of: find.byType(TabBar), matching: find.text('Trends')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Overall deviation index'), findsOneWidget);
    });

    testWidgets('a test set aside in the middle is left out of the count', (
      tester,
    ) async {
      final app = await dashboard(tester);
      await seed(app, history(actual: 3, setAside: {1}));
      await tester.pumpAndSettle();

      // The tired one is stored, but it is not scored.
      final sessions = await app.repository.loadSessions('user-1');
      expect(sessions, hasLength(firstFullTest + 3));
      expect(sessions.where((s) => s.countsTowardsTrend), hasLength(2));
    });
  });

  group('changing the baseline', () {
    testWidgets('sends the user back to building it', (tester) async {
      final app = await dashboard(tester);
      await seed(app, history(actual: 2));
      await tester.pumpAndSettle();
      expect(find.text('Within your usual range'), findsOneWidget);

      await tester.tap(find.text('You'));
      await tester.pumpAndSettle();
      await tester.dragUntilVisible(
        find.text('Change my baseline'),
        find.byType(Scrollable).first,
        const Offset(0, -200),
      );
      await tester.tap(find.text('Change my baseline'));
      await tester.pumpAndSettle();

      // Asked first, and told what happens to the earlier tests.
      expect(find.text('Set a new baseline?'), findsOneWidget);
      expect(find.textContaining('kept in your export'), findsOneWidget);
      await tester.tap(find.text('Start a new baseline'));
      await tester.pumpAndSettle();

      expect(find.byType(DashboardScreen), findsOneWidget);
      // A later baseline has no practice test: three tests, not four.
      expect(
        find.text('Building your baseline: 0 of $kBaselineSessions tests'),
        findsOneWidget,
      );
      expect(find.text('Within your usual range'), findsNothing);
    });

    testWidgets('keeps the earlier tests but stops counting them', (
      tester,
    ) async {
      final app = await dashboard(tester);
      await seed(app, history(actual: 2));
      await tester.pumpAndSettle();

      await app.repository.redoBaseline('user-1');
      await tester.pumpAndSettle();

      expect(await app.repository.loadSessions('user-1'), isEmpty);
      final export = await app.repository.exportEverything('user-1');
      expect(
        (export['sessions']! as List).length,
        kFamiliarisationSessions + kBaselineSessions + 2,
      );
    });

    testWidgets('is not offered before any test has been taken', (
      tester,
    ) async {
      await dashboard(tester);

      await tester.tap(find.text('You'));
      await tester.pumpAndSettle();

      expect(find.text('Change my baseline'), findsNothing);
    });
  });
}
