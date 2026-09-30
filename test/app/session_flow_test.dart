/// Whole tests, driven through the real screens.
///
/// This is the test that would catch a broken app. Everything else checks a piece; this walks
/// the check-in, the steps and the stored result the way a user does, for both kinds of test,
/// and asserts on what ended up in the database.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neurascan_ai/engine/constants.dart';
import 'package:neurascan_ai/engine/screening_engine.dart';
import 'package:neurascan_ai/features/dashboard/dashboard_screen.dart';
import 'package:neurascan_ai/features/session/session_screen.dart';
import 'package:neurascan_ai/features/session/summary_screen.dart';
import 'package:neurascan_ai/features/session/tasks/recall_task.dart';
import 'package:neurascan_ai/features/session/tasks/speech_task.dart';
import 'package:neurascan_ai/features/session/tasks/spiral_task.dart';
import 'package:neurascan_ai/features/session/word_lists.dart';
import 'package:neurascan_ai/services/audio_capture.dart';

import 'seed_history.dart';
import 'test_harness.dart';

void main() {
  /// Signs in, consents, and opens a test from the dashboard button called [button].
  ///
  /// With [seeded] set, those tests are stored first, so the test starts partway through the
  /// journey instead of at the very beginning.
  Future<TestApp> startTest(
    WidgetTester tester, {
    required String button,
    List<SeededTest>? seeded,
    AudioCaptureService? audio,
  }) async {
    final app = await pumpApp(
      tester,
      signedIn: consentPendingAccount,
      audio: audio ?? SimulatedAudioCapture(seed: 1),
    );
    await completeOnboarding(app);
    if (seeded != null) await seed(app, seeded);
    await tester.pumpAndSettle();

    expect(find.byType(DashboardScreen), findsOneWidget);
    await tester.tap(find.text(button));
    await tester.pumpAndSettle();

    expect(find.byType(SessionScreen), findsOneWidget);
    return app;
  }

  Future<TestApp> startPractice(
    WidgetTester tester, {
    AudioCaptureService? audio,
  }) => startTest(tester, button: 'Start the practice test', audio: audio);

  /// A user whose baseline is set, opening their first full test.
  Future<TestApp> startFullTest(WidgetTester tester) =>
      startTest(tester, button: 'Take a full test', seeded: history(actual: 0));

  /// Answers the check-in with the given choices.
  Future<void> answerCheckIn(
    WidgetTester tester, {
    String sleep = 'Well',
    String fatigue = 'Not tired',
    String illness = 'No',
  }) async {
    await tester.tap(find.text(sleep));
    await tester.pumpAndSettle();
    await tester.tap(find.text(fatigue));
    await tester.pumpAndSettle();
    await tester.tap(find.text(illness));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
  }

  /// Reads and dismisses the word list.
  Future<void> readWords(WidgetTester tester) async {
    await tester.tap(find.text('I have them'));
    await tester.pumpAndSettle();
  }

  /// Records the speech step through to the end.
  Future<void> playSpeech(WidgetTester tester) async {
    expect(find.byType(SpeechTask), findsOneWidget);
    await tester.tap(find.text('Start'));
    await tester.pumpAndSettle();

    // Let the countdown run out.
    for (var second = 0; second <= kSpeechSeconds; second++) {
      await tester.pump(const Duration(seconds: 1));
    }
    await tester.pumpAndSettle();
  }

  /// Drags a full spiral, following the guide closely enough to pass the gate.
  Future<void> traceSpiral(WidgetTester tester) async {
    expect(find.byType(SpiralTask), findsOneWidget);

    final canvas = find.descendant(
      of: find.byType(SpiralTask),
      matching: find.byType(GestureDetector),
    );
    final box = tester.renderObject<RenderBox>(canvas.first);
    final topLeft = tester.getTopLeft(canvas.first);
    final centre = topLeft + Offset(box.size.width / 2, box.size.height / 2);
    final maxRadius = (box.size.shortestSide / 2) * 0.86;

    final gesture = await tester.startGesture(centre);
    const steps = 180;
    for (var i = 1; i <= steps; i++) {
      final theta = kSpiralTurns * 2 * math.pi * i / steps;
      final radius = maxRadius * i / steps;
      await gesture.moveTo(
        centre + Offset(radius * math.cos(theta), radius * math.sin(theta)),
      );
      await tester.pump(const Duration(milliseconds: 12));
    }
    await gesture.up();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Finish'));
    await tester.pumpAndSettle();
  }

  /// Types back some words and finishes.
  Future<void> recallWords(WidgetTester tester, List<String> words) async {
    expect(find.byType(RecallTask), findsOneWidget);
    for (final word in words) {
      await tester.enterText(find.byType(TextField), word);
      await tester.pump();
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text('That is all I remember'));
    await tester.pumpAndSettle();
  }

  /// Plays a whole baseline test: words, speech, precision, then the closing recall.
  Future<void> playBaselineTest(
    WidgetTester tester, {
    String fatigue = 'Not tired',
    List<String> remembered = const ['elephant', 'harbour', 'ribbon'],
  }) async {
    await answerCheckIn(tester, fatigue: fatigue);
    await readWords(tester);
    await playSpeech(tester);
    await traceSpiral(tester);
    await recallWords(tester, remembered);
  }

  /// The title of the step being shown.
  Finder step(int number, int total) => find.text('Step $number of $total');

  group('a baseline test', () {
    testWidgets('has three steps and a closing recall, then is stored', (
      tester,
    ) async {
      final app = await startPractice(tester);

      await answerCheckIn(tester);
      expect(step(1, kBaselineTestSteps), findsOneWidget);
      await readWords(tester);

      expect(step(2, kBaselineTestSteps), findsOneWidget);
      await playSpeech(tester);

      expect(step(3, kBaselineTestSteps), findsOneWidget);
      await traceSpiral(tester);

      // The words come back at the end, as a closing part rather than a fourth step.
      expect(find.text('Final part'), findsOneWidget);
      await recallWords(tester, ['elephant', 'harbour', 'ribbon']);

      expect(find.byType(SummaryScreen), findsOneWidget);

      final sessions = await app.repository.loadSessions('user-1');
      expect(sessions, hasLength(1));

      final session = sessions.single;
      expect(session.valid, isTrue, reason: session.invalidReasons.join('; '));
      // The first test is practice, so nothing is scored.
      expect(session.status, ScreeningStatus.buildingBaseline);
      expect(session.features.keys.length, kFeatureKeyCount);
      expect(session.recallDetail, isNotNull);
      expect(session.epoch, 0);
    });

    testWidgets('the first is labelled as practice, the next as baseline 2', (
      tester,
    ) async {
      await startPractice(tester);
      await answerCheckIn(tester);
      expect(find.textContaining('Practice test'), findsOneWidget);
    });

    testWidgets('the second is baseline test 2 of 4', (tester) async {
      await startTest(
        tester,
        button: 'Start baseline test 2 of $kBaselineTests',
        seeded: history(actual: 0).take(1).toList(),
      );
      await answerCheckIn(tester);
      expect(
        find.textContaining('Baseline test 2 of $kBaselineTests'),
        findsOneWidget,
      );
    });

    testWidgets('extracts all five measurements from real step output', (
      tester,
    ) async {
      final app = await startPractice(tester);
      await playBaselineTest(tester, remembered: ['elephant', 'harbour']);

      final session = (await app.repository.loadSessions('user-1')).single;

      // Every feature present and finite. A zero would mean an extractor was never fed.
      for (final key in [
        'delayed_recall',
        'speaking_rate',
        'pause_ratio',
        'spiral_rmse',
        'tremor_index',
      ]) {
        final value = session.features[key];
        expect(value, isNotNull, reason: key);
        expect(value!.isFinite, isTrue, reason: key);
      }

      // The ones that cannot legitimately be zero after a real attempt.
      expect(session.features['speaking_rate'], greaterThan(0));
      expect(session.features['spiral_rmse'], greaterThan(0));
    });

    testWidgets('a tired day is stored but kept out of the trend', (
      tester,
    ) async {
      // Test case TC3.
      final app = await startPractice(tester);
      await playBaselineTest(tester, fatigue: 'Very tired');

      final session = (await app.repository.loadSessions('user-1')).single;
      expect(session.checkIn.isConfounded, isTrue);
      expect(session.countsTowardsTrend, isFalse);
    });

    testWidgets('the recall step can be finished with no words remembered', (
      tester,
    ) async {
      // Remembering none is a legitimate result; blocking it would exclude the users the
      // app exists to notice.
      final app = await startPractice(tester);
      await playBaselineTest(tester, remembered: const []);

      final session = (await app.repository.loadSessions('user-1')).single;
      expect(session.features['delayed_recall'], 0.0);
    });
  });

  group('the check-in', () {
    testWidgets('warns before the test that it will not count', (tester) async {
      // Told beforehand, while the user can still choose to come back later.
      await startPractice(tester);
      await tester.tap(find.text('Badly'));
      await tester.pumpAndSettle();

      expect(find.textContaining('kept out of your trend'), findsOneWidget);
    });

    testWidgets('must be answered before the steps start', (tester) async {
      await startPractice(tester);

      final button = tester.widget<FilledButton>(
        find.ancestor(
          of: find.text('Continue'),
          matching: find.byType(FilledButton),
        ),
      );
      expect(button.onPressed, isNull);
    });
  });

  group('a step that does not pass', () {
    testWidgets('silence asks for the speech step again, and stores nothing', (
      tester,
    ) async {
      // Test case TC5: under eight voiced seconds cannot be scored. It costs the user the
      // step, not the whole test.
      final app = await startPractice(tester, audio: SilentAudioCapture());

      await answerCheckIn(tester);
      await readWords(tester);
      await playSpeech(tester);

      // Still on the speech step, told why, and able to try again.
      expect(step(2, kBaselineTestSteps), findsOneWidget);
      expect(find.byType(SpeechTask), findsOneWidget);
      expect(
        find.textContaining('could not hear enough speech'),
        findsOneWidget,
      );
      expect(find.text('Start'), findsOneWidget);
      expect(await app.repository.loadSessions('user-1'), isEmpty);
    });

    testWidgets('the spiral cannot be finished before the coverage gate', (
      tester,
    ) async {
      // Test case TC6.
      await startPractice(tester);

      await answerCheckIn(tester);
      await readWords(tester);
      await playSpeech(tester);

      expect(find.byType(SpiralTask), findsOneWidget);
      final button = tester.widget<FilledButton>(
        find.ancestor(
          of: find.text('Finish'),
          matching: find.byType(FilledButton),
        ),
      );
      expect(button.onPressed, isNull);
    });
  });

  group('leaving', () {
    testWidgets('asks first and saves nothing', (tester) async {
      final app = await startPractice(tester);
      await answerCheckIn(tester);
      await readWords(tester);

      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      expect(find.text('Leave this test?'), findsOneWidget);

      await tester.tap(find.text('Keep going'));
      await tester.pumpAndSettle();
      expect(find.byType(SessionScreen), findsOneWidget);

      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Leave'));
      await tester.pumpAndSettle();

      expect(find.byType(DashboardScreen), findsOneWidget);
      expect(await app.repository.loadSessions('user-1'), isEmpty);
    });
  });

  group('a full test', () {
    /// Plays the eight steps in order, checking where the user is at each.
    ///
    /// Returns the words of each list, so the caller can say which were remembered.
    Future<void> playFullTest(
      WidgetTester tester, {
      required List<List<String>> remembered,
    }) async {
      const total = kActualTestSteps;

      await answerCheckIn(tester);

      // Step 1: the first list.
      expect(step(1, total), findsOneWidget);
      expect(find.textContaining('Full test'), findsOneWidget);
      await readWords(tester);

      // Steps 2 and 3: speech and tracing.
      expect(step(2, total), findsOneWidget);
      await playSpeech(tester);
      expect(step(3, total), findsOneWidget);
      await traceSpiral(tester);

      // Step 4: the first list comes back, and the second is learned.
      expect(step(4, total), findsOneWidget);
      expect(find.text('Word list 1 of $kActualWordSteps'), findsOneWidget);
      await recallWords(tester, remembered[0]);
      expect(step(4, total), findsOneWidget);
      await readWords(tester);

      // Steps 5 and 6.
      expect(step(5, total), findsOneWidget);
      await playSpeech(tester);
      expect(step(6, total), findsOneWidget);
      await traceSpiral(tester);

      // Step 7: the second list comes back, and the third is learned.
      expect(step(7, total), findsOneWidget);
      expect(find.text('Word list 2 of $kActualWordSteps'), findsOneWidget);
      await recallWords(tester, remembered[1]);
      expect(step(7, total), findsOneWidget);
      await readWords(tester);

      // Step 8, then the closing recall.
      expect(step(8, total), findsOneWidget);
      await playSpeech(tester);
      expect(find.text('Final part'), findsOneWidget);
      expect(find.text('Word list 3 of $kActualWordSteps'), findsOneWidget);
      await recallWords(tester, remembered[2]);
    }

    /// The lists the app will pick for the next full test, given four tests already stored.
    List<WordList> nextLists() => pickWordListsForTest(
      testIndex: kBaselineTests,
      count: kActualWordSteps,
    );

    testWidgets('has eight steps, three word lists and is scored', (
      tester,
    ) async {
      final app = await startFullTest(tester);
      final lists = nextLists();

      await playFullTest(
        tester,
        remembered: [lists[0].words, lists[1].words.take(4).toList(), const []],
      );

      expect(find.byType(SummaryScreen), findsOneWidget);

      final sessions = await app.repository.loadSessions('user-1');
      expect(sessions, hasLength(kBaselineTests + 1));

      final session = sessions.last;
      expect(session.valid, isTrue);
      // Compared with the baseline straight away: a scored status, not "building".
      expect(session.countsTowardsTrend, isTrue);
      expect(session.features.keys.length, kFeatureKeyCount);
      expect(session.domainScores, isNotNull);

      // Twenty-four words were shown across the three lists, and each is accounted for.
      final detail = session.recallDetail!;
      expect(
        detail.recalled.length + detail.missed.length,
        kActualWordSteps * kMemoryWordCount,
      );
      // 8 + 4 + 0 remembered.
      expect(detail.recalled.length, kMemoryWordCount + 4);
    });

    testWidgets('the result and its comparison are shown straight away', (
      tester,
    ) async {
      await startFullTest(tester);
      final lists = nextLists();
      await playFullTest(
        tester,
        remembered: [lists[0].words, lists[1].words, lists[2].words],
      );

      expect(find.byType(SummaryScreen), findsOneWidget);
      expect(find.text('How this test compares'), findsOneWidget);
      expect(find.text('Against your usual'), findsWidgets);
      // The summary is a long list now, so the report button is below the fold.
      await tester.scrollUntilVisible(
        find.text('See the full report'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('See the full report'), findsOneWidget);
    });

    testWidgets('each measurement is the median of its repeats', (
      tester,
    ) async {
      // The recall value is the middle of the three lists' scores: 100 %, 50 % and 0 %.
      final app = await startFullTest(tester);
      final lists = nextLists();

      await playFullTest(
        tester,
        remembered: [lists[0].words, lists[1].words.take(4).toList(), const []],
      );

      final session = (await app.repository.loadSessions('user-1')).last;
      expect(session.features['delayed_recall'], closeTo(0.5, 1e-9));
    });
  });
}

/// The number of measurements a test yields, as the engine defines them.
const kFeatureKeyCount = 5;
