/// The steps of a test, in order.
///
/// A test is a list of screens and the numbers a user sees ("Step 4 of 8") are worked out from
/// it, so these tests pin the parts a user would notice going wrong: three steps for a baseline
/// test and eight for a full one, a word list never recalled straight after it was learned,
/// and the last recall shown as a closing part rather than a ninth step.
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
      expect(baseline.wordLists, 1);
      expect(baseline.screens.last.kind, ScreenKind.recallWords);
      expect(baseline.screens.last.isFinalPart, isTrue);
    });

    test('numbers its steps one to three', () {
      expect(
        [for (final screen in baseline.screens) screen.stepNumber],
        [1, 2, 3, null],
      );
    });
  });

  group('a full test', () {
    test('has eight steps', () {
      expect(actual.totalSteps, kActualTestSteps);
      expect(actual.totalSteps, 8);
    });

    test('has three word lists, three speech steps and two tracings', () {
      expect(actual.wordLists, 3);
      expect(actual.speechSteps, 3);
      expect(actual.precisionSteps, 2);
      expect(actual.count(ScreenKind.learnWords), 3);
      expect(actual.count(ScreenKind.recallWords), 3);
      expect(actual.count(ScreenKind.speech), 3);
      expect(actual.count(ScreenKind.precision), 2);
    });

    test('numbers its steps in order, up to eight', () {
      final numbers = [
        for (final screen in actual.screens)
          if (screen.stepNumber != null) screen.stepNumber!,
      ];
      expect(numbers.first, 1);
      expect(numbers.last, 8);
      for (var i = 1; i < numbers.length; i++) {
        // A step may cover two screens (recalling one list, learning the next), but it
        // never goes backwards or skips.
        expect(numbers[i] - numbers[i - 1], inInclusiveRange(0, 1));
      }
      expect(numbers.toSet(), {1, 2, 3, 4, 5, 6, 7, 8});
    });

    test('shows the last recall as a closing part, not a ninth step', () {
      final last = actual.screens.last;
      expect(last.kind, ScreenKind.recallWords);
      expect(last.isFinalPart, isTrue);
      expect(last.stepNumber, isNull);
      expect(
        actual.screens.where((s) => s.isFinalPart),
        hasLength(1),
        reason: 'only the last screen is the closing part',
      );
    });

    test('does not recall a list straight after learning it', () {
      // Recalled with other steps in between, or it would measure working memory rather
      // than delayed recall.
      for (var list = 0; list < actual.wordLists; list++) {
        final learned = actual.screens.indexWhere(
          (s) => s.kind == ScreenKind.learnWords && s.index == list,
        );
        final recalled = actual.screens.indexWhere(
          (s) => s.kind == ScreenKind.recallWords && s.index == list,
        );
        expect(recalled, greaterThan(learned), reason: 'list $list');
        final between = actual.screens
            .sublist(learned + 1, recalled)
            .where(
              (s) =>
                  s.kind == ScreenKind.speech || s.kind == ScreenKind.precision,
            );
        expect(between, isNotEmpty, reason: 'list $list recalled too soon');
      }
    });

    test('every screen of a kind has its own index', () {
      for (final kind in ScreenKind.values) {
        final indexes = [
          for (final screen in actual.screens)
            if (screen.kind == kind) screen.index,
        ];
        expect(indexes, [for (var i = 0; i < indexes.length; i++) i]);
      }
    });
  });

  group('the two kinds together', () {
    test('a full test repeats the steps a baseline test measures', () {
      // A step in a full test has to be something the baseline also measured, or there is
      // nothing to compare it with.
      final baselineKinds = {for (final s in baseline.screens) s.kind};
      final actualKinds = {for (final s in actual.screens) s.kind};
      expect(actualKinds, baselineKinds);
    });

    test('a screen knows which step it belongs to', () {
      expect(StepKind.of(ScreenKind.learnWords), StepKind.words);
      expect(StepKind.of(ScreenKind.recallWords), StepKind.words);
      expect(StepKind.of(ScreenKind.speech), StepKind.speech);
      expect(StepKind.of(ScreenKind.precision), StepKind.precision);
    });
  });
}
