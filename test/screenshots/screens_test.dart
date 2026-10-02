/// Renders the screenshots and animation frames used by the README.
///
/// Not a test of anything: it drives the real app through the real screens and writes
/// what it sees to `docs/images/raw`, so every picture in the README is the app rather
/// than a mock-up. `tool/screenshots/compose.py` turns the output into the files the
/// README links to.
///
/// Run it with:
///
/// ```
/// flutter test test/screenshots --dart-define=capture=true
/// python tool/screenshots/compose.py
/// ```
///
/// Without the define every case is skipped, so an ordinary `flutter test` run and CI
/// do not spend a minute writing PNGs nobody asked for.
@Tags(['screenshots'])
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neurascan_ai/app/providers.dart';
import 'package:neurascan_ai/app/router.dart';
import 'package:neurascan_ai/engine/constants.dart';
import 'package:neurascan_ai/features/dashboard/dashboard_screen.dart';
import 'package:neurascan_ai/features/report/export/pdf/report_pdf.dart';
import 'package:neurascan_ai/features/report/export/report_model.dart';
import 'package:neurascan_ai/features/report/providers.dart';
import 'package:neurascan_ai/features/report/reference_ranges.dart';
import 'package:neurascan_ai/features/session/session_screen.dart';
import 'package:neurascan_ai/features/session/word_lists.dart';
import 'package:neurascan_ai/services/audio_capture.dart';

import '../app/seed_history.dart';
import '../app/test_harness.dart';
import 'capture.dart';
import 'drive.dart';
import 'story.dart';

/// Set by `--dart-define=capture=true`.
const bool kCapture = bool.fromEnvironment('capture');

void main() {
  setUpAll(loadRealFonts);

  /// A signed-in, consented user with [tests] full tests behind them.
  Future<TestApp> ready(
    WidgetTester tester, {
    int tests = 0,
    Story story = Story.steady,
    Set<int> setAside = const {3},
  }) async {
    final app = await pumpForCapture(
      tester,
      signedIn: consentPendingAccount,
      audio: SimulatedAudioCapture(seed: 1),
    );
    await completeOnboarding(app);
    if (tests >= 0) {
      await seed(
        app,
        storyHistory(
          full: tests,
          story: story,
          setAside: {
            for (final i in setAside)
              if (i < tests) i,
          },
        ),
      );
    }
    await tester.pumpAndSettle();
    return app;
  }

  /// Scrolls the first scrollable down by [by] and settles.
  Future<void> scroll(WidgetTester tester, double by) async {
    await tester.drag(find.byType(Scrollable).first, Offset(0, -by));
    await tester.pumpAndSettle();
  }

  group('capture', () {
    testWidgets('the way in: onboarding, consent and the check-in', (
      tester,
    ) async {
      final app = await pumpForCapture(tester);
      await shoot(tester, 'onboarding');

      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();
      await shoot(tester, 'login');

      await app.auth.signIn(email: 'someone@example.com', password: 'secret');
      await tester.pumpAndSettle();
      await shoot(tester, 'consent');
      await scroll(tester, 520);
      await shoot(tester, 'consent-choices');
    });

    testWidgets('the dashboard, before and after a baseline', (tester) async {
      final app = await ready(tester, tests: -1);
      await shoot(tester, 'dashboard-start');

      await seed(app, storyHistory(full: 0));
      await tester.pumpAndSettle();
      await shoot(tester, 'dashboard-baseline-done');

      await seed(app, storyHistory(full: 9, setAside: const {3}));
      await tester.pumpAndSettle();
      expect(find.byType(DashboardScreen), findsOneWidget);
      await shoot(tester, 'dashboard');
    });

    testWidgets('a full test, step by step', (tester) async {
      await ready(tester);
      await tester.tap(find.text('Take a full test'));
      await tester.pumpAndSettle();
      expect(find.byType(SessionScreen), findsOneWidget);

      await shoot(tester, 'checkin');
      await frame(tester, 'full-test');
      await answerCheckIn(tester);

      final words = pickWordListsForTest(
        testIndex: kBaselineTests,
        count: 1,
      ).single.words;

      // Step 1: the words, then the immediate recall.
      await shoot(tester, 'step-1-words');
      await frame(tester, 'full-test');
      await readWords(tester);
      await shoot(tester, 'step-1-recall');
      await recallWords(tester, words.take(6).toList());

      // Step 2: reaction time.
      await shoot(tester, 'step-2-reaction');
      await frame(tester, 'full-test');
      await playReaction(tester, gif: 'reaction', still: 'step-2-reaction-go');

      // Step 3: speech.
      await shoot(tester, 'step-3-speech');
      await frame(tester, 'full-test');
      await playSpeech(tester);

      // Step 4: the spiral.
      await shoot(tester, 'step-4-spiral');
      await frame(tester, 'full-test');
      await traceSpiral(tester, gif: 'spiral');

      // Step 5: typing rhythm, which asks nothing of the user.
      await shoot(tester, 'step-5-typing');
      await frame(tester, 'full-test');
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      // Step 6: trail making.
      await shoot(tester, 'step-6-trail');
      await frame(tester, 'full-test');
      await playTrail(tester, gif: 'trail', still: 'step-6-trail-active');

      // Step 7: finger tapping.
      await shoot(tester, 'step-7-tapping');
      await frame(tester, 'full-test');
      await playTapping(tester, gif: 'tapping', still: 'step-7-tapping-active');

      // Step 8: verbal fluency.
      await shoot(tester, 'step-8-fluency');
      await frame(tester, 'full-test');
      await playFluency(
        tester,
        const ['cat', 'dog', 'lion', 'tiger', 'horse', 'otter'],
        gif: 'fluency',
        still: 'step-8-fluency-active',
      );

      // The delayed recall closes the test.
      await shoot(tester, 'step-delayed-recall');
      await frame(tester, 'full-test');
      await recallWords(tester, words.take(4).toList());

      // And the result, straight away.
      await tester.pumpAndSettle();
      await shoot(tester, 'summary');
      await frame(tester, 'full-test');
    });

    testWidgets('the results of a test', (tester) async {
      final app = await ready(tester, tests: 9);
      app.container.read(routerProvider).go(Routes.trends);
      await tester.pumpAndSettle();

      await shoot(tester, 'results-status');
      await scroll(tester, 430);
      await shoot(tester, 'results-cards');
      await scroll(tester, 430);
      await shoot(tester, 'results-cards-2');

      // The same screen as an animation, in smaller steps so it reads as a scroll
      // rather than as a slideshow.
      await scroll(tester, -4000);
      await frame(tester, 'results');
      for (var i = 0; i < 8; i++) {
        await scroll(tester, 145);
        await frame(tester, 'results');
      }

      // A card opened, which is where a measurement's own numbers are.
      await scroll(tester, -4000);
      await tester.tap(find.text('Word memory'));
      await tester.pumpAndSettle();
      await shoot(tester, 'results-card-open');
      await scroll(tester, 300);
      await shoot(tester, 'results-card-open-2');
    });

    testWidgets('a change that persists', (tester) async {
      final app = await ready(tester, tests: 9, story: Story.drifting);
      await shoot(tester, 'dashboard-change');

      app.container.read(routerProvider).go(Routes.trends);
      await tester.pumpAndSettle();
      await shoot(tester, 'results-status-change');

      await tester.tap(
        find.descendant(of: find.byType(TabBar), matching: find.text('Trends')),
      );
      await tester.pumpAndSettle();
      await shoot(tester, 'trends-change');
      await scroll(tester, 420);
      await shoot(tester, 'trends-change-2');
    });

    testWidgets('one measurement, three ways', (tester) async {
      final app = await ready(tester, tests: 7);
      app.container
          .read(routerProvider)
          .go('${Routes.metric}?key=delayed_recall');
      await tester.pumpAndSettle();
      await shoot(tester, 'metric-detail');
      await scroll(tester, 430);
      await shoot(tester, 'metric-detail-2');
      await scroll(tester, 430);
      await shoot(tester, 'metric-detail-3');
    });

    testWidgets('the trends', (tester) async {
      final app = await ready(tester, tests: 9);
      app.container.read(routerProvider).go(Routes.trends);
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(of: find.byType(TabBar), matching: find.text('Trends')),
      );
      await tester.pumpAndSettle();
      await shoot(tester, 'trends');
      await scroll(tester, 420);
      await shoot(tester, 'trends-2');
      await scroll(tester, 420);
      await shoot(tester, 'trends-3');

      await tester.tap(
        find.descendant(
          of: find.byType(TabBar),
          matching: find.text('Every test'),
        ),
      );
      await tester.pumpAndSettle();
      await shoot(tester, 'every-test');
    });

    testWidgets('the report', (tester) async {
      final app = await ready(tester, tests: 9);
      app.container.read(routerProvider).go(Routes.report);
      await tester.pumpAndSettle();
      await shoot(tester, 'report-options');
      await scroll(tester, 450);
      await shoot(tester, 'report-options-2');
      await scroll(tester, 450);
      await shoot(tester, 'report-contents');

      // The PDF itself, written out for `compose.py` to rasterise.
      final sessions = await app.repository.loadSessions('user-1');
      final model = buildReportModel(
        sessions: sessions,
        baseline: app.container.read(engineProvider).value?.baseline,
        ranges:
            app.container.read(referenceRangesProvider).value ??
            ReferenceRanges.none,
        options: const ReportOptions(),
        now: DateTime.now(),
      );
      await tester.runAsync(() async {
        final report = await buildReportPdf(model);
        final file = File('$kOutDir/report.pdf');
        await file.parent.create(recursive: true);
        await file.writeAsBytes(report.bytes);
      });
    });

    testWidgets('privacy and settings', (tester) async {
      final app = await ready(tester, tests: 7);
      app.container.read(routerProvider).go(Routes.profile);
      await tester.pumpAndSettle();
      await shoot(tester, 'profile');
      await scroll(tester, 450);
      await shoot(tester, 'profile-2');

      app.container.read(routerProvider).go(Routes.privacy);
      await tester.pumpAndSettle();
      await shoot(tester, 'privacy');
      await scroll(tester, 450);
      await shoot(tester, 'privacy-2');
    });
  }, skip: !kCapture);
}
