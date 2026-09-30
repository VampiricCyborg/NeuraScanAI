/// The screens of the five steps only a full test has: trail-making, finger tapping, verbal
/// fluency, the passive typing note and the recall in its immediate form.
///
/// The extractors are tested on synthetic data in test/engine. These tests are about the
/// screens: what they hand over, that they behave under a finger, and that they do not move
/// underneath the user.
library;

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neurascan_ai/app/l10n/generated/app_localizations.dart';
import 'package:neurascan_ai/app/theme.dart';
import 'package:neurascan_ai/engine/constants.dart';
import 'package:neurascan_ai/engine/extractors/fluency_extractor.dart';
import 'package:neurascan_ai/engine/extractors/tapping_extractor.dart';
import 'package:neurascan_ai/engine/extractors/trail_extractor.dart';
import 'package:neurascan_ai/features/session/keystroke_recorder.dart';
import 'package:neurascan_ai/features/session/tasks/fluency_task.dart';
import 'package:neurascan_ai/features/session/tasks/recall_task.dart';
import 'package:neurascan_ai/features/session/tasks/tapping_task.dart';
import 'package:neurascan_ai/features/session/tasks/trail_task.dart';
import 'package:neurascan_ai/features/session/tasks/typing_note.dart';

void main() {
  Future<void> pumpStep(
    WidgetTester tester,
    Widget step, {
    KeystrokeLog? log,
    Locale? locale,
  }) async {
    tester.view
      ..physicalSize = const Size(420, 1000)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    Widget body = Padding(padding: const EdgeInsets.all(20), child: step);
    if (log != null) body = KeystrokeScope(log: log, child: body);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.light),
        locale: locale,
        localizationsDelegates: AppText.localizationsDelegates,
        supportedLocales: AppText.supportedLocales,
        home: Scaffold(body: body),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('trail-making', () {
    TrailPartLog? gotA;
    TrailPartLog? gotB;

    Future<void> pumpTrail(WidgetTester tester, {int seed = 1}) async {
      gotA = null;
      gotB = null;
      await pumpStep(
        tester,
        TrailTask(
          key: ValueKey(seed),
          random: Random(seed),
          onFinished: ({required partA, required partB}) {
            gotA = partA;
            gotB = partB;
          },
        ),
      );
    }

    Finder circle(String label) => find.byKey(ValueKey('trail-circle-$label'));

    Future<void> tapInOrder(WidgetTester tester, List<String> labels) async {
      for (final label in labels) {
        await tester.tap(circle(label));
        await tester.pump(const Duration(milliseconds: 300));
      }
    }

    test('part A is the numbers one to five', () {
      expect(trailLabelsA(), ['1', '2', '3', '4', '5']);
    });

    test('part B alternates numbers and letters', () {
      expect(trailLabelsB(), ['1', 'A', '2', 'B', '3', 'C', '4', 'D']);
    });

    testWidgets('no circles are shown until the step is started', (
      tester,
    ) async {
      await pumpTrail(tester);
      expect(find.byKey(const ValueKey('trail-circle-1')), findsNothing);
      expect(find.text('Start'), findsOneWidget);
    });

    testWidgets('starting shows the five numbered circles of part A', (
      tester,
    ) async {
      await pumpTrail(tester);
      await tester.tap(find.text('Start'));
      await tester.pumpAndSettle();

      for (final label in trailLabelsA()) {
        expect(circle(label), findsOneWidget, reason: label);
      }
      expect(circle('A'), findsNothing);
    });

    testWidgets('the circles do not overlap and all sit inside the canvas', (
      tester,
    ) async {
      for (var seed = 0; seed < 20; seed++) {
        await pumpTrail(tester, seed: seed);
        await tester.tap(find.text('Start'));
        await tester.pumpAndSettle();

        final centres = [
          for (final label in trailLabelsA()) tester.getCenter(circle(label)),
        ];
        for (var i = 0; i < centres.length; i++) {
          for (var j = i + 1; j < centres.length; j++) {
            expect(
              (centres[i] - centres[j]).distance,
              greaterThanOrEqualTo(kTrailCircleRadius * 2),
              reason: 'seed $seed circles $i and $j overlap',
            );
          }
        }
      }
    });

    testWidgets('every circle is a comfortable touch target', (tester) async {
      await pumpTrail(tester);
      await tester.tap(find.text('Start'));
      await tester.pumpAndSettle();
      final size = tester.getSize(circle('1'));
      expect(size.width, greaterThanOrEqualTo(48));
      expect(size.height, greaterThanOrEqualTo(48));
    });

    testWidgets('part A finishes after the fifth circle and offers part B', (
      tester,
    ) async {
      await pumpTrail(tester);
      await tester.tap(find.text('Start'));
      await tester.pumpAndSettle();
      await tapInOrder(tester, trailLabelsA());
      await tester.pumpAndSettle();

      expect(find.text('Start part B'), findsOneWidget);
      expect(gotA, isNull, reason: 'handed over only when both parts are done');
    });

    testWidgets('both parts together are handed over with their taps', (
      tester,
    ) async {
      await pumpTrail(tester);
      await tester.tap(find.text('Start'));
      await tester.pumpAndSettle();
      await tapInOrder(tester, trailLabelsA());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Start part B'));
      await tester.pumpAndSettle();
      await tapInOrder(tester, trailLabelsB());
      await tester.pumpAndSettle();

      expect(gotA!.targets, kTrailPartACircles);
      expect(gotB!.targets, kTrailPartBCircles);
      expect(gotA!.completed, isTrue);
      expect(gotB!.completed, isTrue);
      expect(gotA!.errors, 0);
      expect(gotB!.errors, 0);
    });

    testWidgets('a wrong circle is counted and does not advance the order', (
      tester,
    ) async {
      await pumpTrail(tester);
      await tester.tap(find.text('Start'));
      await tester.pumpAndSettle();

      // 3 before 1.
      await tester.tap(circle('3'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.textContaining('Not that one'), findsOneWidget);

      await tapInOrder(tester, trailLabelsA());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Start part B'));
      await tester.pumpAndSettle();
      await tapInOrder(tester, trailLabelsB());
      await tester.pumpAndSettle();

      expect(gotA!.errors, 1);
      expect(gotA!.completed, isTrue);
    });

    testWidgets('the timings run from when the circles appeared', (
      tester,
    ) async {
      await pumpTrail(tester);
      await tester.tap(find.text('Start'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 2));
      await tapInOrder(tester, trailLabelsA());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Start part B'));
      await tester.pumpAndSettle();
      await tapInOrder(tester, trailLabelsB());
      await tester.pumpAndSettle();

      // The first correct tap came after the two-second wait.
      expect(gotA!.taps.first.timestampMs, greaterThanOrEqualTo(2000));
    });

    testWidgets('the circles stay put while the user taps', (tester) async {
      await pumpTrail(tester);
      await tester.tap(find.text('Start'));
      await tester.pumpAndSettle();
      final before = tester.getCenter(circle('5'));
      await tester.tap(circle('1'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(circle('4')); // wrong: shows a message
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.getCenter(circle('5')), before);
    });

    testWidgets('is labelled for screen readers', (tester) async {
      await pumpTrail(tester);
      await tester.tap(find.text('Start'));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel(RegExp('^1\$')), findsWidgets);
    });
  });

  group('finger tapping', () {
    List<TapEvent>? taps;

    Future<void> pumpTapping(WidgetTester tester) async {
      taps = null;
      await pumpStep(
        tester,
        TappingTask(onFinished: (events) => taps = events),
      );
    }

    testWidgets('starts idle and ignores taps until started', (tester) async {
      await pumpTapping(tester);
      await tester.tap(
        find.byKey(const ValueKey('tap-left')),
        warnIfMissed: false,
      );
      await tester.pump(const Duration(seconds: 11));
      expect(taps, isNull);
    });

    testWidgets('records alternating taps with their sides and times', (
      tester,
    ) async {
      await pumpTapping(tester);
      await tester.tap(find.text('Start'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('tap-left')));
      await tester.pump(const Duration(milliseconds: 250));
      await tester.tap(find.byKey(const ValueKey('tap-right')));
      await tester.pump(const Duration(milliseconds: 250));
      await tester.tap(find.byKey(const ValueKey('tap-left')));
      await tester.pump(const Duration(seconds: 11));
      await tester.pumpAndSettle();

      expect([for (final t in taps!) t.side], [0, 1, 0]);
      expect(taps![1].timestampMs - taps![0].timestampMs, closeTo(250, 60));
    });

    testWidgets('ends by itself after the time, handing the taps over', (
      tester,
    ) async {
      await pumpTapping(tester);
      await tester.tap(find.text('Start'));
      await tester.pumpAndSettle();

      await tester.pump(const Duration(seconds: kTappingSeconds - 1));
      expect(taps, isNull);
      await tester.pump(const Duration(seconds: 2));
      expect(taps, isNotNull);
    });

    testWidgets(
      'a tap on the wrong button is kept, for the extractor to ignore',
      (tester) async {
        await pumpTapping(tester);
        await tester.tap(find.text('Start'));
        await tester.pumpAndSettle();

        for (var i = 0; i < 3; i++) {
          await tester.tap(find.byKey(const ValueKey('tap-left')));
          await tester.pump(const Duration(milliseconds: 200));
        }
        await tester.pump(const Duration(seconds: 11));

        expect(taps, hasLength(3));
        expect(extractTappingFeatures(taps!).validTaps, 1);
      },
    );

    testWidgets('both buttons are big and labelled', (tester) async {
      await pumpTapping(tester);
      for (final key in ['tap-left', 'tap-right']) {
        final size = tester.getSize(find.byKey(ValueKey(key)));
        expect(size.width, greaterThan(100), reason: key);
        expect(size.height, greaterThan(100), reason: key);
      }
      expect(find.text('Left'), findsOneWidget);
      expect(find.text('Right'), findsOneWidget);
    });

    testWidgets('the layout does not change when the step starts', (
      tester,
    ) async {
      await pumpTapping(tester);
      final before = tester.getRect(find.byKey(const ValueKey('tap-left')));
      await tester.tap(find.text('Start'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.getRect(find.byKey(const ValueKey('tap-left'))), before);
    });
  });

  group('verbal fluency', () {
    List<FluencyEntry>? entries;

    Future<void> pumpFluency(WidgetTester tester, {KeystrokeLog? log}) async {
      entries = null;
      await pumpStep(
        tester,
        FluencyTask(onFinished: (e) => entries = e),
        log: log,
      );
    }

    Future<void> addAnimal(WidgetTester tester, String animal) async {
      await tester.enterText(find.byType(TextField), animal);
      await tester.tap(find.text('Add'));
      await tester.pump(const Duration(milliseconds: 500));
    }

    testWidgets('shows no text box until started', (tester) async {
      await pumpFluency(tester);
      expect(find.byType(TextField), findsNothing);
      expect(find.text('Start'), findsOneWidget);
    });

    testWidgets('starting shows the box, the count and the time left', (
      tester,
    ) async {
      await pumpFluency(tester);
      await tester.tap(find.text('Start'));
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('0 entered'), findsOneWidget);
      expect(find.text('30 s left'), findsOneWidget);
    });

    testWidgets('each added animal is listed and counted', (tester) async {
      await pumpFluency(tester);
      await tester.tap(find.text('Start'));
      await tester.pumpAndSettle();

      await addAnimal(tester, 'cat');
      await addAnimal(tester, 'dog');

      expect(find.text('2 entered'), findsOneWidget);
      expect(find.widgetWithText(Chip, 'cat'), findsOneWidget);
      expect(find.widgetWithText(Chip, 'dog'), findsOneWidget);
    });

    testWidgets('an empty entry is not added', (tester) async {
      await pumpFluency(tester);
      await tester.tap(find.text('Start'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add'));
      await tester.pump();
      expect(find.text('0 entered'), findsOneWidget);
    });

    testWidgets('nothing says whether an entry counted', (tester) async {
      // Feedback would change what people do, and the step is meant to measure retrieval.
      await pumpFluency(tester);
      await tester.tap(find.text('Start'));
      await tester.pumpAndSettle();
      await addAnimal(tester, 'table');
      expect(find.byIcon(Icons.check), findsNothing);
      expect(find.byIcon(Icons.close), findsNothing);
      expect(find.text('1 entered'), findsOneWidget);
    });

    testWidgets('ends by itself and hands the entries over with their times', (
      tester,
    ) async {
      await pumpFluency(tester);
      await tester.tap(find.text('Start'));
      await tester.pumpAndSettle();

      await addAnimal(tester, 'cat');
      await tester.pump(const Duration(seconds: 10));
      await addAnimal(tester, 'dog');
      await tester.pump(const Duration(seconds: 25));

      expect([for (final e in entries!) e.text], ['cat', 'dog']);
      expect(entries![0].timestampMs, lessThan(entries![1].timestampMs));
      expect(entries![1].timestampMs, greaterThan(10000));
    });

    testWidgets('a word still being typed when time runs out is not lost', (
      tester,
    ) async {
      await pumpFluency(tester);
      await tester.tap(find.text('Start'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'zebra');
      await tester.pump(const Duration(seconds: 31));

      expect([for (final e in entries!) e.text], ['zebra']);
      expect(entries!.single.timestampMs, lessThanOrEqualTo(30000));
    });

    testWidgets('the typing feeds the session\'s keystroke log', (
      tester,
    ) async {
      final log = KeystrokeLog();
      await pumpFluency(tester, log: log);
      await tester.tap(find.text('Start'));
      await tester.pumpAndSettle();

      for (var i = 1; i <= 5; i++) {
        await tester.enterText(find.byType(TextField), 'zebra'.substring(0, i));
        await tester.pump(const Duration(milliseconds: 200));
      }
      expect(log.length, 5);
    });

    testWidgets('the entries are scored by the extractor as typed', (
      tester,
    ) async {
      await pumpFluency(tester);
      await tester.tap(find.text('Start'));
      await tester.pumpAndSettle();
      await addAnimal(tester, 'cat');
      await addAnimal(tester, 'Cats');
      await addAnimal(tester, 'sofa');
      await tester.pump(const Duration(seconds: 31));

      final result = extractFluencyFeatures(entries!);
      expect(result.validWordCount, 1);
      expect(result.repeats, 1);
      expect(result.intrusions, 1);
    });
  });

  group('the passive typing step', () {
    testWidgets('says nothing is needed and how much has been timed', (
      tester,
    ) async {
      final log = KeystrokeLog()..recordInsertion(inserted: 7);
      await pumpStep(tester, TypingNote(onContinue: () {}), log: log);

      expect(find.textContaining('Nothing to do here'), findsOneWidget);
      expect(find.text('7 key presses timed so far'), findsOneWidget);
    });

    testWidgets('works with no log, for a screen outside a test', (
      tester,
    ) async {
      await pumpStep(tester, TypingNote(onContinue: () {}));
      expect(find.text('0 key presses timed so far'), findsOneWidget);
    });

    testWidgets('continues when asked', (tester) async {
      var continued = false;
      await pumpStep(tester, TypingNote(onContinue: () => continued = true));
      await tester.tap(find.text('Continue'));
      expect(continued, isTrue);
    });

    testWidgets('is translated', (tester) async {
      await pumpStep(
        tester,
        TypingNote(onContinue: () {}),
        locale: const Locale('ta'),
      );
      expect(find.text('Continue'), findsNothing);
      expect(find.text('தொடர்க'), findsOneWidget);
    });
  });

  group('the immediate recall', () {
    testWidgets('asks for the words straight away, not later', (tester) async {
      await pumpStep(
        tester,
        RecallTask(kind: RecallKind.immediate, onFinished: (_) {}),
      );
      expect(find.text('Type the words you just saw'), findsOneWidget);
      expect(find.text('Which words do you remember?'), findsNothing);
    });

    testWidgets('the delayed form keeps its own wording', (tester) async {
      await pumpStep(tester, RecallTask(onFinished: (_) {}));
      expect(find.text('Which words do you remember?'), findsOneWidget);
    });

    testWidgets('records the typing in the log', (tester) async {
      final log = KeystrokeLog();
      await pumpStep(
        tester,
        RecallTask(kind: RecallKind.immediate, onFinished: (_) {}),
        log: log,
      );
      await tester.enterText(find.byType(TextField), 'r');
      await tester.enterText(find.byType(TextField), 'ri');
      expect(log.length, 2);
    });

    testWidgets('can be finished with nothing remembered', (tester) async {
      List<String>? words;
      await pumpStep(
        tester,
        RecallTask(kind: RecallKind.immediate, onFinished: (w) => words = w),
      );
      await tester.tap(find.text('That is all I remember'));
      expect(words, isEmpty);
    });
  });
}
