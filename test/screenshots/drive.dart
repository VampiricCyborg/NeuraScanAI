/// Drives the real session steps while recording frames.
///
/// The same moves as `test/app/session_flow_test.dart` makes, with a hook after each
/// one so a capture can take a picture. Kept separate from the assertions so that a
/// change to a step breaks the test that guards it, not only the screenshots.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neurascan_ai/engine/constants.dart';
import 'package:neurascan_ai/features/session/tasks/reaction_task.dart';
import 'package:neurascan_ai/features/session/tasks/spiral_task.dart';
import 'package:neurascan_ai/features/session/tasks/trail_task.dart';

import 'capture.dart';

/// Answers the check-in.
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

/// Dismisses the word list.
Future<void> readWords(WidgetTester tester) async {
  await tester.tap(find.text('I have them'));
  await tester.pumpAndSettle();
}

/// Types [word] one character at a time, so the typing rhythm has real gaps.
Future<void> typeWord(WidgetTester tester, String word) async {
  for (var i = 1; i <= word.length; i++) {
    await tester.enterText(find.byType(TextField), word.substring(0, i));
    await tester.pump(const Duration(milliseconds: 230));
  }
}

/// Types back [words] and finishes the recall.
Future<void> recallWords(
  WidgetTester tester,
  List<String> words, {
  String? gif,
}) async {
  for (final word in words) {
    await typeWord(tester, word);
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    if (gif != null) await frame(tester, gif);
  }
  await tester.tap(find.text('That is all I remember'));
  await tester.pumpAndSettle();
}

/// Records the speech step through to the end.
Future<void> playSpeech(WidgetTester tester, {String? gif}) async {
  await tester.tap(find.text('Start'));
  await tester.pumpAndSettle();
  for (var second = 0; second <= kSpeechSeconds; second++) {
    await tester.pump(const Duration(seconds: 1));
    if (gif != null && second.isEven) await frame(tester, gif);
  }
  await tester.pumpAndSettle();
}

/// Drags a full spiral, following the guide closely enough to pass the gate.
Future<void> traceSpiral(WidgetTester tester, {String? gif}) async {
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
    // A human hand does not track a guide perfectly, and a screenshot of a
    // mathematically exact trace would not look like one.
    final wobble = 2.4 * math.sin(i * 0.9);
    await gesture.moveTo(
      centre +
          Offset(
            (radius + wobble) * math.cos(theta),
            (radius + wobble) * math.sin(theta),
          ),
    );
    await tester.pump(const Duration(milliseconds: 12));
    if (gif != null && i % 15 == 0) await frame(tester, gif);
  }
  await gesture.up();
  await tester.pumpAndSettle();
  if (gif != null) await frame(tester, gif);

  await tester.tap(find.text('Finish'));
  await tester.pumpAndSettle();
}

/// Plays the reaction step, responding on time each trial.
Future<void> playReaction(
  WidgetTester tester, {
  String? gif,
  String? still,
}) async {
  final target = find.byType(ReactionTask);
  await tester.tap(target);
  await tester.pump();

  for (var trial = 0; trial < kReactionTrials; trial++) {
    await tester.pump(const Duration(milliseconds: 400));
    if (gif != null && trial < 3) await frame(tester, gif);
    await tester.pump(const Duration(milliseconds: kForeperiodMaxMs - 300));
    if (gif != null && trial < 3) await frame(tester, gif);
    // The stimulus is showing: the moment the step is about.
    if (still != null && trial == 1) await shoot(tester, still);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(target, warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 400));
    if (gif != null && trial < 3) await frame(tester, gif);
    await tester.pump(const Duration(milliseconds: 400));
  }
  await tester.pumpAndSettle();
}

Finder _circle(String label) => find.byKey(ValueKey('trail-circle-$label'));

/// Plays both parts of the trail-making step.
Future<void> playTrail(
  WidgetTester tester, {
  String? gif,
  String? still,
}) async {
  await tester.tap(find.text('Start'));
  await tester.pumpAndSettle();
  if (gif != null) await frame(tester, gif);

  var tapped = 0;
  for (final label in trailLabelsA()) {
    await tester.tap(_circle(label));
    await tester.pump(const Duration(milliseconds: 500));
    if (gif != null) await frame(tester, gif);
    if (still != null && ++tapped == 4) await shoot(tester, still);
  }
  await tester.pumpAndSettle();

  await tester.tap(find.text('Start part B'));
  await tester.pumpAndSettle();
  for (final label in trailLabelsB()) {
    await tester.tap(_circle(label));
    await tester.pump(const Duration(milliseconds: 700));
  }
  await tester.pumpAndSettle();
}

/// Plays the tapping step, alternating buttons.
Future<void> playTapping(
  WidgetTester tester, {
  String? gif,
  String? still,
}) async {
  await tester.tap(find.text('Start'));
  await tester.pumpAndSettle();

  for (var i = 0; i < 45; i++) {
    await tester.tap(find.byKey(ValueKey(i.isOdd ? 'tap-right' : 'tap-left')));
    await tester.pump(const Duration(milliseconds: 200));
    if (gif != null && i < 10) await frame(tester, gif);
    if (still != null && i == 12) await shoot(tester, still);
  }
  for (var i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
  await tester.pumpAndSettle();
}

/// Plays the fluency step, typing each of [animals].
Future<void> playFluency(
  WidgetTester tester,
  List<String> animals, {
  String? gif,
  String? still,
}) async {
  await tester.tap(find.text('Start'));
  await tester.pumpAndSettle();

  for (final animal in animals) {
    await typeWord(tester, animal);
    await tester.tap(find.text('Add'));
    await tester.pump(const Duration(milliseconds: 600));
    if (gif != null) await frame(tester, gif);
    if (still != null && animal == animals.last) await shoot(tester, still);
  }
  for (var second = 0; second <= kFluencySeconds; second++) {
    await tester.pump(const Duration(seconds: 1));
  }
  await tester.pumpAndSettle();
}
