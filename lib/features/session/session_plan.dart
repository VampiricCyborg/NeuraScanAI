/// The steps of a test, laid out in order.
///
/// There are two kinds of test and both are built from the same three kinds of step -- words,
/// speech and precision -- because a step in an actual test has to be something the baseline
/// also measured, or there would be nothing to compare it with.
///
/// * A **baseline test** has three steps: words, speech, precision. Four of them set the
///   baseline (the first a practice run that does not count).
/// * An **actual test** has eight: three word lists, three speech pictures and two tracings.
///   Each measurement is taken several times and the test's value for it is the median, so
///   one unusual step cannot define the result.
///
/// The recall of a word list is a *screen* but not a *step*: it belongs to the words step that
/// taught the list. A list has to be recalled after other things have happened, or it would
/// measure working memory rather than delayed recall, so the recall comes later than the
/// learning it belongs to. For an actual test the words steps interleave, so recalling one
/// list and learning the next share a step:
///
///     step 1  learn list 1          step 5  speech 2
///     step 2  speech 1              step 6  precision 2
///     step 3  precision 1           step 7  recall list 2, learn list 3
///     step 4  recall list 1,        step 8  speech 3
///             learn list 2          final   recall list 3
library;

import '../../engine/constants.dart';

/// Which kind of test is being taken.
enum TestKind {
  /// Sets the baseline. Three steps.
  baseline,

  /// Compared against the baseline. Eight steps.
  actual,
}

/// The kind of thing a screen asks the user to do.
enum ScreenKind {
  /// Show a word list to memorise.
  learnWords,

  /// Describe a picture aloud.
  speech,

  /// Trace the spiral.
  precision,

  /// Type back a word list learned earlier.
  recallWords,
}

/// The three kinds of step, as the user counts them.
enum StepKind {
  words,
  speech,
  precision;

  /// The step a screen belongs to.
  static StepKind of(ScreenKind screen) => switch (screen) {
    ScreenKind.learnWords || ScreenKind.recallWords => StepKind.words,
    ScreenKind.speech => StepKind.speech,
    ScreenKind.precision => StepKind.precision,
  };
}

/// One screen in a test.
class PlannedScreen {
  const PlannedScreen({
    required this.kind,
    required this.index,
    this.stepNumber,
  });

  final ScreenKind kind;

  /// Which item of its kind this is, counting from zero: the second speech picture has
  /// index 1, the third word list has index 2.
  final int index;

  /// The step this screen belongs to, counting from one, or null for the final recall,
  /// which is shown as a closing part rather than as another step.
  final int? stepNumber;

  StepKind get step => StepKind.of(kind);

  /// True for the closing recall, after the last numbered step.
  bool get isFinalPart => stepNumber == null;
}

/// A whole test, screen by screen.
class TestPlan {
  const TestPlan._({
    required this.kind,
    required this.screens,
    required this.totalSteps,
    required this.wordLists,
    required this.speechSteps,
    required this.precisionSteps,
  });

  final TestKind kind;
  final List<PlannedScreen> screens;

  /// Steps as the user counts them: three or eight.
  final int totalSteps;

  /// Word lists learned and recalled.
  final int wordLists;

  final int speechSteps;
  final int precisionSteps;

  /// The plan for a test of [kind].
  factory TestPlan.of(TestKind kind) => switch (kind) {
    TestKind.baseline => _baseline,
    TestKind.actual => _actual,
  };

  static const TestPlan _baseline = TestPlan._(
    kind: TestKind.baseline,
    totalSteps: kBaselineTestSteps,
    wordLists: 1,
    speechSteps: 1,
    precisionSteps: 1,
    screens: [
      PlannedScreen(kind: ScreenKind.learnWords, index: 0, stepNumber: 1),
      PlannedScreen(kind: ScreenKind.speech, index: 0, stepNumber: 2),
      PlannedScreen(kind: ScreenKind.precision, index: 0, stepNumber: 3),
      PlannedScreen(kind: ScreenKind.recallWords, index: 0),
    ],
  );

  static const TestPlan _actual = TestPlan._(
    kind: TestKind.actual,
    totalSteps: kActualTestSteps,
    wordLists: kActualWordSteps,
    speechSteps: kActualSpeechSteps,
    precisionSteps: kActualPrecisionSteps,
    screens: [
      PlannedScreen(kind: ScreenKind.learnWords, index: 0, stepNumber: 1),
      PlannedScreen(kind: ScreenKind.speech, index: 0, stepNumber: 2),
      PlannedScreen(kind: ScreenKind.precision, index: 0, stepNumber: 3),
      PlannedScreen(kind: ScreenKind.recallWords, index: 0, stepNumber: 4),
      PlannedScreen(kind: ScreenKind.learnWords, index: 1, stepNumber: 4),
      PlannedScreen(kind: ScreenKind.speech, index: 1, stepNumber: 5),
      PlannedScreen(kind: ScreenKind.precision, index: 1, stepNumber: 6),
      PlannedScreen(kind: ScreenKind.recallWords, index: 1, stepNumber: 7),
      PlannedScreen(kind: ScreenKind.learnWords, index: 2, stepNumber: 7),
      PlannedScreen(kind: ScreenKind.speech, index: 2, stepNumber: 8),
      PlannedScreen(kind: ScreenKind.recallWords, index: 2),
    ],
  );

  int get length => screens.length;

  /// How many screens of [kind] the test has.
  int count(ScreenKind kind) => screens.where((s) => s.kind == kind).length;
}
