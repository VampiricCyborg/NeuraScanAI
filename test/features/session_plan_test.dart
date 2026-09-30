/// The steps of a test, in order.
///
/// A test is a list of screens and the numbers a user sees ("Step 4 of 8") are worked out from
/// it, so these tests pin the parts a user would notice going wrong: three steps for a baseline
/// test and eight different ones for a full test, the word list recalled twice with the delayed
/// recall at the very end, and that last recall shown as a closing part rather than a ninth
/// step.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:neurascan_ai/engine/constants.dart';
import 'package:neurascan_ai/features/session/session_plan.dart';

void main() {
  final baseline = TestPlan.of(TestKind.baseline);
  final actual = TestPlan.of(TestKind.actual);

  group('a baseline test', () {
    test('has three steps: words, speech and precision', () {
      expect(baseline.totalSteps, kBaselineTestSteps);
      expect(baseline.totalSteps, 3);
      final steps = [
        for (final screen in baseline.screens)
          if (!screen.isFinalPart) screen.step,
      ];
      expect(steps, [StepKind.words, StepKind.speech, StepKind.precision]);
    });

    test('closes with the recall of its one list', () {
      expect(baseline.screens.last.kind, ScreenKind.recallWords);
      expect(baseline.screens.last.isFinalPart, isTrue);
    });

    test('numbers its steps one to three', () {
      expect(
        [for (final screen in baseline.screens) screen.stepNumber],
        [1, 2, 3, null],
      );
    });

    test('has none of the steps only a full test has', () {
      final kinds = {for (final s in baseline.screens) s.kind};
      for (final kind in [
        ScreenKind.immediateRecall,
        ScreenKind.reaction,
        ScreenKind.typingNote,
        ScreenKind.trail,
        ScreenKind.tapping,
        ScreenKind.fluency,
      ]) {
        expect(kinds, isNot(contains(kind)));
      }
    });
  });

  group('a full test', () {
    test('has eight steps', () {
      expect(actual.totalSteps, kActualTestSteps);
      expect(actual.totalSteps, 8);
    });

    test('has eight different steps, each a different kind', () {
      final steps = <StepKind>[];
      for (final screen in actual.screens) {
        if (screen.isFinalPart) continue;
        if (steps.isEmpty || steps.last != screen.step) steps.add(screen.step);
      }
      expect(steps, [
        StepKind.words,
        StepKind.reaction,
        StepKind.speech,
        StepKind.precision,
        StepKind.typing,
        StepKind.trail,
        StepKind.tapping,
        StepKind.fluency,
      ]);
      expect(steps.toSet(), hasLength(8));
    });

    test('numbers its steps one to eight, in order', () {
      final numbers = [
        for (final screen in actual.screens)
          if (screen.stepNumber != null) screen.stepNumber!,
      ];
      expect(numbers.first, 1);
      expect(numbers.last, 8);
      for (var i = 1; i < numbers.length; i++) {
        // Step 1 covers two screens (the words, then the immediate recall), but the numbers
        // never go backwards or skip.
        expect(numbers[i] - numbers[i - 1], inInclusiveRange(0, 1));
      }
      expect(numbers.toSet(), {1, 2, 3, 4, 5, 6, 7, 8});
    });

    test(
      'the first step shows the words, then asks for them straight away',
      () {
        expect(actual.screens[0].kind, ScreenKind.learnWords);
        expect(actual.screens[1].kind, ScreenKind.immediateRecall);
        expect(actual.screens[0].stepNumber, 1);
        expect(actual.screens[1].stepNumber, 1);
      },
    );

    test(
      'the delayed recall is last, as a closing part and not a ninth step',
      () {
        final last = actual.screens.last;
        expect(last.kind, ScreenKind.recallWords);
        expect(last.isFinalPart, isTrue);
        expect(last.stepNumber, isNull);
        expect(
          actual.screens.where((s) => s.isFinalPart),
          hasLength(1),
          reason: 'only the last screen is the closing part',
        );
      },
    );

    test('the delayed recall comes after every other step', () {
      // Recalled after all the others, or it would measure working memory rather than
      // delayed recall.
      final learned = actual.screens.indexWhere(
        (s) => s.kind == ScreenKind.learnWords,
      );
      final recalled = actual.screens.indexWhere(
        (s) => s.kind == ScreenKind.recallWords,
      );
      expect(actual.screens.sublist(learned + 1, recalled), hasLength(8));
    });

    test('has one of each kind of screen, apart from the two recalls', () {
      for (final kind in ScreenKind.values) {
        expect(actual.count(kind), 1, reason: kind.name);
      }
    });

    test('the typing step needs nothing from the user and sits fifth', () {
      final index = actual.screens.indexWhere(
        (s) => s.kind == ScreenKind.typingNote,
      );
      expect(actual.screens[index].stepNumber, 5);
      expect(actual.screens[index].step, StepKind.typing);
    });

    test(
      'the typing step comes after the first typed step and before the others',
      () {
        // Typing rhythm is timed in the word recalls and the fluency step, so the note sits
        // after the first and before the second.
        final note = actual.screens.indexWhere(
          (s) => s.kind == ScreenKind.typingNote,
        );
        final immediate = actual.screens.indexWhere(
          (s) => s.kind == ScreenKind.immediateRecall,
        );
        final fluency = actual.screens.indexWhere(
          (s) => s.kind == ScreenKind.fluency,
        );
        expect(immediate, lessThan(note));
        expect(note, lessThan(fluency));
      },
    );
  });

  group('the two kinds together', () {
    test('a full test repeats the steps a baseline test measures', () {
      // A baseline test measures words, speech and precision; a full test has all three, so
      // the core measurements can be compared between them.
      final baselineSteps = {for (final s in baseline.screens) s.step};
      final actualSteps = {for (final s in actual.screens) s.step};
      expect(actualSteps, containsAll(baselineSteps));
    });

    test('a full test adds five steps the baseline never ran', () {
      final baselineSteps = {for (final s in baseline.screens) s.step};
      final added = {for (final s in actual.screens) s.step}
        ..removeAll(baselineSteps);
      expect(added, {
        StepKind.reaction,
        StepKind.typing,
        StepKind.trail,
        StepKind.tapping,
        StepKind.fluency,
      });
    });

    test('a screen knows which step it belongs to', () {
      expect(StepKind.of(ScreenKind.learnWords), StepKind.words);
      expect(StepKind.of(ScreenKind.immediateRecall), StepKind.words);
      expect(StepKind.of(ScreenKind.recallWords), StepKind.words);
      expect(StepKind.of(ScreenKind.reaction), StepKind.reaction);
      expect(StepKind.of(ScreenKind.speech), StepKind.speech);
      expect(StepKind.of(ScreenKind.precision), StepKind.precision);
      expect(StepKind.of(ScreenKind.typingNote), StepKind.typing);
      expect(StepKind.of(ScreenKind.trail), StepKind.trail);
      expect(StepKind.of(ScreenKind.tapping), StepKind.tapping);
      expect(StepKind.of(ScreenKind.fluency), StepKind.fluency);
    });
  });
}
