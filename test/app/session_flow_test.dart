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
import 'package:neurascan_ai/engine/features.dart';
import 'package:neurascan_ai/engine/screening_engine.dart';
import 'package:neurascan_ai/features/dashboard/dashboard_screen.dart';
import 'package:neurascan_ai/features/session/session_screen.dart';
import 'package:neurascan_ai/features/session/summary_screen.dart';
import 'package:neurascan_ai/features/session/tasks/fluency_task.dart';
import 'package:neurascan_ai/features/session/tasks/reaction_task.dart';
import 'package:neurascan_ai/features/session/tasks/recall_task.dart';
import 'package:neurascan_ai/features/session/tasks/speech_task.dart';
import 'package:neurascan_ai/features/session/tasks/spiral_task.dart';
import 'package:neurascan_ai/features/session/tasks/tapping_task.dart';
import 'package:neurascan_ai/features/session/tasks/trail_task.dart';
import 'package:neurascan_ai/features/session/tasks/typing_note.dart';
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

  /// Types [word] into the only text field one character at a time, with a realistic gap.
  ///
  /// Entering the whole word at once would record every keystroke at the same instant, and the
  /// typing-rhythm measurement would see no usable gaps.
  Future<void> typeWord(WidgetTester tester, String word) async {
    for (var i = 1; i <= word.length; i++) {
      await tester.enterText(find.byType(TextField), word.substring(0, i));
      await tester.pump(const Duration(milliseconds: 230));
    }
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

  /// Types back some words, one at a time, and finishes.
  Future<void> recallWords(WidgetTester tester, List<String> words) async {
    expect(find.byType(RecallTask), findsOneWidget);
    for (final word in words) {
      await typeWord(tester, word);
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text('That is all I remember'));
    await tester.pumpAndSettle();
  }

  /// Plays the reaction step through, responding on time each trial.
  Future<void> playReaction(WidgetTester tester, {int anticipate = 0}) async {
    final target = find.byType(ReactionTask);
    expect(target, findsOneWidget);

    // The first tap starts the first trial.
    await tester.tap(target);
    await tester.pump();

    // Anticipations first. They do not count as completed trials, so the step still needs its
    // full set of real ones afterwards.
    for (var i = 0; i < anticipate; i++) {
      // Tap during the foreperiod, before the stimulus.
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(target, warnIfMissed: false);
      // The warning pause before the next trial begins.
      await tester.pump(const Duration(milliseconds: 1500));
    }

    for (var trial = 0; trial < kReactionTrials; trial++) {
      // Past the longest possible foreperiod, so the stimulus is showing.
      await tester.pump(const Duration(milliseconds: kForeperiodMaxMs + 100));
      // A plausible reaction time.
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(target, warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 800));
    }
    await tester.pumpAndSettle();
  }

  Finder circle(String label) => find.byKey(ValueKey('trail-circle-$label'));

  /// Plays both parts of the trail-making step, optionally with a wrong tap first.
  Future<void> playTrail(WidgetTester tester, {bool wrongFirst = false}) async {
    expect(find.byType(TrailTask), findsOneWidget);

    await tester.tap(find.text('Start'));
    await tester.pumpAndSettle();

    if (wrongFirst) {
      // The first circle to tap is 1; 3 is wrong.
      await tester.tap(circle('3'));
      await tester.pump(const Duration(milliseconds: 300));
    }
    for (final label in trailLabelsA()) {
      await tester.tap(circle(label));
      await tester.pump(const Duration(milliseconds: 500));
    }
    await tester.pumpAndSettle();

    await tester.tap(find.text('Start part B'));
    await tester.pumpAndSettle();
    for (final label in trailLabelsB()) {
      await tester.tap(circle(label));
      await tester.pump(const Duration(milliseconds: 700));
    }
    await tester.pumpAndSettle();
  }

  /// Plays the tapping step, alternating buttons, or hammering one if [alternate] is false.
  Future<void> playTapping(WidgetTester tester, {bool alternate = true}) async {
    expect(find.byType(TappingTask), findsOneWidget);
    await tester.tap(find.text('Start'));
    await tester.pumpAndSettle();

    for (var i = 0; i < 45; i++) {
      final side = alternate && i.isOdd ? 'tap-right' : 'tap-left';
      await tester.tap(find.byKey(ValueKey(side)));
      await tester.pump(const Duration(milliseconds: 200));
    }
    // Let the ten seconds run out.
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    await tester.pumpAndSettle();
  }

  /// Plays the fluency step, typing each of [animals] and adding it.
  Future<void> playFluency(WidgetTester tester, List<String> animals) async {
    expect(find.byType(FluencyTask), findsOneWidget);
    await tester.tap(find.text('Start'));
    await tester.pumpAndSettle();

    for (final animal in animals) {
      await typeWord(tester, animal);
      await tester.tap(find.text('Add'));
      await tester.pump(const Duration(milliseconds: 600));
    }
    // Let the thirty seconds run out.
    for (var second = 0; second <= kFluencySeconds; second++) {
      await tester.pump(const Duration(seconds: 1));
    }
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
      // A baseline test measures the five core features only.
      expect(session.features.keys.toSet(), kCoreFeatureKeys.toSet());
      expect(session.recallDetail, isNotNull);
      expect(session.epoch, 0);
    });

    testWidgets('the first is labelled as practice', (tester) async {
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

    testWidgets('extracts the five core measurements from real step output', (
      tester,
    ) async {
      final app = await startPractice(tester);
      await playBaselineTest(tester, remembered: ['elephant', 'harbour']);

      final session = (await app.repository.loadSessions('user-1')).single;

      // Every feature present and finite. A zero would mean an extractor was never fed.
      for (final key in kCoreFeatureKeys) {
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
    /// The list the app will pick for a full test after the four baseline tests.
    WordList nextList() =>
        pickWordListsForTest(testIndex: kBaselineTests, count: 1).single;

    /// Plays the eight steps in order, checking where the user is at each.
    Future<void> playFullTest(
      WidgetTester tester, {
      required List<String> immediate,
      required List<String> delayed,
      List<String> animals = const ['cat', 'dog', 'lion'],
      bool wrongTrailTap = false,
    }) async {
      const total = kActualTestSteps;

      await answerCheckIn(tester);

      // Step 1: word memory. The words, then straight away the first recall.
      expect(step(1, total), findsOneWidget);
      expect(find.textContaining('Full test'), findsOneWidget);
      await readWords(tester);
      expect(step(1, total), findsOneWidget);
      await recallWords(tester, immediate);

      // Steps 2 to 4.
      expect(step(2, total), findsOneWidget);
      await playReaction(tester);
      expect(step(3, total), findsOneWidget);
      await playSpeech(tester);
      expect(step(4, total), findsOneWidget);
      await traceSpiral(tester);

      // Step 5: typing rhythm, which needs nothing from the user.
      expect(step(5, total), findsOneWidget);
      expect(find.byType(TypingNote), findsOneWidget);
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      // Steps 6 to 8.
      expect(step(6, total), findsOneWidget);
      await playTrail(tester, wrongFirst: wrongTrailTap);
      expect(step(7, total), findsOneWidget);
      await playTapping(tester);
      expect(step(8, total), findsOneWidget);
      await playFluency(tester, animals);

      // The delayed recall, last.
      expect(find.text('Final part'), findsOneWidget);
      await recallWords(tester, delayed);
    }

    testWidgets('has eight different steps and every measurement is stored', (
      tester,
    ) async {
      final app = await startFullTest(tester);
      final list = nextList();

      await playFullTest(
        tester,
        immediate: list.words,
        delayed: list.words.take(4).toList(),
      );

      expect(find.byType(SummaryScreen), findsOneWidget);

      final sessions = await app.repository.loadSessions('user-1');
      expect(sessions, hasLength(kBaselineTests + 1));

      final session = sessions.last;
      expect(session.valid, isTrue);
      // Compared with the baseline straight away: a scored status, not "building".
      expect(session.countsTowardsTrend, isTrue);
      // All eighteen measurements, the typed steps having supplied enough typing.
      expect(session.features.keys.toSet(), kFeatureKeys.toSet());
      for (final entry in session.features.entries) {
        expect(entry.value.isFinite, isTrue, reason: entry.key);
      }
    });

    testWidgets('the two recalls are scored separately', (tester) async {
      final app = await startFullTest(tester);
      final list = nextList();

      await playFullTest(
        tester,
        immediate: list.words,
        delayed: list.words.take(4).toList(),
      );

      final session = (await app.repository.loadSessions('user-1')).last;
      expect(session.features['immediate_recall'], closeTo(1.0, 1e-9));
      expect(session.features['delayed_recall'], closeTo(0.5, 1e-9));
    });

    testWidgets('names only real, different animals count in fluency', (
      tester,
    ) async {
      final app = await startFullTest(tester);
      final list = nextList();

      await playFullTest(
        tester,
        immediate: list.words,
        delayed: list.words,
        animals: const ['cat', 'dog', 'cat', 'table', 'zebra'],
      );

      final session = (await app.repository.loadSessions('user-1')).last;
      // cat, dog and zebra: the repeat and the non-animal do not count.
      expect(session.features['valid_word_count'], 3.0);
    });

    testWidgets('a wrong circle in the trail step is counted as an error', (
      tester,
    ) async {
      final app = await startFullTest(tester);
      final list = nextList();

      await playFullTest(
        tester,
        immediate: list.words,
        delayed: list.words,
        wrongTrailTap: true,
      );

      final session = (await app.repository.loadSessions('user-1')).last;
      expect(session.features['error_count'], 1.0);
    });

    testWidgets('typing rhythm is timed from the typed steps', (tester) async {
      final app = await startFullTest(tester);
      final list = nextList();

      await playFullTest(tester, immediate: list.words, delayed: list.words);

      final session = (await app.repository.loadSessions('user-1')).last;
      // Typed in character by character at about 230 ms a key.
      expect(session.features['inter_key_interval'], closeTo(230, 60));
    });

    testWidgets('the passive typing step says how much has been timed', (
      tester,
    ) async {
      await startFullTest(tester);
      final list = nextList();

      await answerCheckIn(tester);
      await readWords(tester);
      await recallWords(tester, list.words.take(3).toList());
      await playReaction(tester);
      await playSpeech(tester);
      await traceSpiral(tester);

      expect(step(5, kActualTestSteps), findsOneWidget);
      expect(find.textContaining('key presses timed so far'), findsOneWidget);
      // Some typing has been timed by now, from the immediate recall.
      expect(find.text('0 key presses timed so far'), findsNothing);
    });

    testWidgets('the result and its summary are shown straight away', (
      tester,
    ) async {
      await startFullTest(tester);
      final list = nextList();

      await playFullTest(tester, immediate: list.words, delayed: list.words);

      expect(find.byType(SummaryScreen), findsOneWidget);
      // The summary is a long list, so the report button is below the fold.
      await tester.scrollUntilVisible(
        find.text('See the full report'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('See the full report'), findsOneWidget);
    });

    testWidgets('too many early taps ask for the reaction step again', (
      tester,
    ) async {
      final app = await startFullTest(tester);
      final list = nextList();

      await answerCheckIn(tester);
      await readWords(tester);
      await recallWords(tester, list.words);

      expect(step(2, kActualTestSteps), findsOneWidget);
      await playReaction(tester, anticipate: kMaxAnticipations + 1);

      // Still on the reaction step, told why, and nothing stored.
      expect(step(2, kActualTestSteps), findsOneWidget);
      expect(find.byType(ReactionTask), findsOneWidget);
      expect(
        find.textContaining('did not give enough usable reactions'),
        findsOneWidget,
      );
      expect(
        await app.repository.loadSessions('user-1'),
        hasLength(kBaselineTests),
      );

      // A clean second attempt moves on.
      await playReaction(tester);
      expect(step(3, kActualTestSteps), findsOneWidget);
    });

    testWidgets('hammering one button asks for the tapping step again', (
      tester,
    ) async {
      await startFullTest(tester);
      final list = nextList();

      await answerCheckIn(tester);
      await readWords(tester);
      await recallWords(tester, list.words);
      await playReaction(tester);
      await playSpeech(tester);
      await traceSpiral(tester);
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      await playTrail(tester);

      expect(step(7, kActualTestSteps), findsOneWidget);
      await playTapping(tester, alternate: false);

      expect(step(7, kActualTestSteps), findsOneWidget);
      expect(find.byType(TappingTask), findsOneWidget);
      expect(
        find.textContaining('counted too few taps that alternated'),
        findsOneWidget,
      );
    });

    testWidgets('naming no animals is allowed and scores zero', (tester) async {
      // Naming none is a real result; blocking it would exclude the people the test exists
      // to notice.
      final app = await startFullTest(tester);
      final list = nextList();

      await playFullTest(
        tester,
        immediate: list.words,
        delayed: list.words,
        animals: const [],
      );

      final session = (await app.repository.loadSessions('user-1')).last;
      expect(session.features['valid_word_count'], 0.0);
      expect(session.features['fluency_half_ratio'], 1.0);
    });
  });
}
