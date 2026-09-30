/// A whole session, driven through the real screens.
///
/// This is the test that would catch a broken app. Everything else checks a piece; this walks
/// the check-in, five tasks and the stored result the way a user does, and asserts on what
/// ended up in the database.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neurascan_ai/engine/constants.dart';
import 'package:neurascan_ai/engine/screening_engine.dart';
import 'package:neurascan_ai/features/dashboard/dashboard_screen.dart';
import 'package:neurascan_ai/features/session/session_screen.dart';
import 'package:neurascan_ai/features/session/summary_screen.dart';
import 'package:neurascan_ai/features/session/tasks/reaction_task.dart';
import 'package:neurascan_ai/features/session/tasks/recall_task.dart';
import 'package:neurascan_ai/features/session/tasks/speech_task.dart';
import 'package:neurascan_ai/features/session/tasks/spiral_task.dart';
import 'package:neurascan_ai/services/audio_capture.dart';

import 'test_harness.dart';

void main() {
  /// Signs in, consents, and opens a session.
  Future<TestApp> startSession(
    WidgetTester tester, {
    AudioCaptureService? audio,
  }) async {
    final app = await pumpApp(
      tester,
      signedIn: consentPendingAccount,
      audio: audio ?? SimulatedAudioCapture(seed: 1),
    );
    await completeOnboarding(app);
    await tester.pumpAndSettle();

    expect(find.byType(DashboardScreen), findsOneWidget);
    await tester.tap(find.text('Start a session'));
    await tester.pumpAndSettle();

    expect(find.byType(SessionScreen), findsOneWidget);
    return app;
  }

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

  /// Plays the reaction task through, responding on time each trial.
  Future<void> playReaction(WidgetTester tester, {int anticipate = 0}) async {
    final target = find.byType(ReactionTask);
    expect(target, findsOneWidget);

    // The first tap starts the first trial.
    await tester.tap(target);
    await tester.pump();

    // Anticipations first. They do not count as completed trials, so the task still needs
    // its full set of real ones afterwards.
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

  /// Records the speech task through to the end.
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
      // One character at a time with a realistic gap, as a person types. Entering the
      // whole word at once would record every keystroke at the same instant.
      for (var i = 1; i <= word.length; i++) {
        await tester.enterText(find.byType(TextField), word.substring(0, i));
        await tester.pump(const Duration(milliseconds: 230));
      }
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text('That is all I remember'));
    await tester.pumpAndSettle();
  }

  testWidgets('a full session is completed and stored', (tester) async {
    final app = await startSession(tester);

    await answerCheckIn(tester);
    await readWords(tester);
    await playReaction(tester);
    await playSpeech(tester);
    await traceSpiral(tester);
    await recallWords(tester, ['elephant', 'harbour', 'ribbon']);

    expect(find.byType(SummaryScreen), findsOneWidget);

    final sessions = await app.repository.loadSessions('user-1');
    expect(sessions, hasLength(1));

    final session = sessions.single;
    expect(session.valid, isTrue, reason: session.invalidReasons.join('; '));
    // The first session is familiarisation, so no score yet.
    expect(session.status, ScreeningStatus.buildingBaseline);
    expect(session.features.keys.length, 9);
    expect(session.recallDetail, isNotNull);
  });

  testWidgets('all nine features are extracted from real task output', (
    tester,
  ) async {
    final app = await startSession(tester);

    await answerCheckIn(tester);
    await readWords(tester);
    await playReaction(tester);
    await playSpeech(tester);
    await traceSpiral(tester);
    await recallWords(tester, ['elephant', 'harbour']);

    final session = (await app.repository.loadSessions('user-1')).single;

    // Every feature present and finite. A zero would mean an extractor was never fed.
    for (final key in [
      'delayed_recall',
      'reaction_median',
      'reaction_cv',
      'speaking_rate',
      'pause_ratio',
      'spiral_rmse',
      'tremor_index',
      'inter_key_interval',
      'inter_key_cv',
    ]) {
      final value = session.features[key];
      expect(value, isNotNull, reason: key);
      expect(value!.isFinite, isTrue, reason: key);
    }

    // The ones that cannot legitimately be zero after a real attempt.
    expect(session.features['reaction_median'], greaterThan(0));
    expect(session.features['speaking_rate'], greaterThan(0));
    expect(session.features['spiral_rmse'], greaterThan(0));
    expect(session.features['inter_key_interval'], greaterThan(0));
  });

  testWidgets('a tired day is stored but kept out of the trend', (
    tester,
  ) async {
    // Test case TC3.
    final app = await startSession(tester);

    await answerCheckIn(tester, fatigue: 'Very tired');
    await readWords(tester);
    await playReaction(tester);
    await playSpeech(tester);
    await traceSpiral(tester);
    await recallWords(tester, ['elephant']);

    final session = (await app.repository.loadSessions('user-1')).single;
    expect(session.checkIn.isConfounded, isTrue);
    expect(session.countsTowardsTrend, isFalse);
  });

  testWidgets('the check-in warns before the session that it will not count', (
    tester,
  ) async {
    // Told beforehand, while the user can still choose to come back later.
    await startSession(tester);
    await tester.tap(find.text('Badly'));
    await tester.pumpAndSettle();

    expect(find.textContaining('kept out of your trend'), findsOneWidget);
  });

  testWidgets('the check-in must be answered before the tasks start', (
    tester,
  ) async {
    await startSession(tester);

    final button = tester.widget<FilledButton>(
      find.ancestor(
        of: find.text('Continue'),
        matching: find.byType(FilledButton),
      ),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('silence invalidates the session', (tester) async {
    // Test case TC5: under eight voiced seconds cannot be scored.
    final app = await startSession(tester, audio: SilentAudioCapture());

    await answerCheckIn(tester);
    await readWords(tester);
    await playReaction(tester);
    await playSpeech(tester);
    await traceSpiral(tester);
    await recallWords(tester, ['elephant']);

    final session = (await app.repository.loadSessions('user-1')).single;
    expect(session.valid, isFalse);
    expect(session.status, ScreeningStatus.invalidSession);
    expect(session.invalidReasons.join(), contains('speech'));
    // An invalid session stores no features rather than unusable ones.
    expect(session.features, isEmpty);
  });

  testWidgets('too many anticipations invalidate the session', (tester) async {
    // Test case TC4.
    final app = await startSession(tester);

    await answerCheckIn(tester);
    await readWords(tester);
    await playReaction(tester, anticipate: 4);
    await playSpeech(tester);
    await traceSpiral(tester);
    await recallWords(tester, ['elephant']);

    final session = (await app.repository.loadSessions('user-1')).single;
    expect(session.valid, isFalse);
    expect(session.invalidReasons.join(), contains('before the stimulus'));
  });

  testWidgets('the spiral cannot be finished before the coverage gate', (
    tester,
  ) async {
    // Test case TC6.
    await startSession(tester);

    await answerCheckIn(tester);
    await readWords(tester);
    await playReaction(tester);
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

  testWidgets('leaving a session asks first and saves nothing', (tester) async {
    final app = await startSession(tester);
    await answerCheckIn(tester);
    await readWords(tester);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    expect(find.text('Leave this session?'), findsOneWidget);

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

  testWidgets('the recall step can be finished with no words remembered', (
    tester,
  ) async {
    // Remembering none is a legitimate result; blocking it would exclude the users the app
    // exists to notice.
    final app = await startSession(tester);

    await answerCheckIn(tester);
    await readWords(tester);
    await playReaction(tester);
    await playSpeech(tester);
    await traceSpiral(tester);
    await recallWords(tester, const []);

    final session = (await app.repository.loadSessions('user-1')).single;
    expect(session.features['delayed_recall'], 0.0);
  });
}
