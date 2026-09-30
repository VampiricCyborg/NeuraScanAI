/// The steps of a test, laid out in order.
///
/// There are two kinds of test.
///
/// * A **baseline test** has three steps: words, speech, precision. Four of them set the
///   baseline (the first a practice run that does not count). The words step shows a list and
///   asks for it back at the end, as a closing part.
/// * An **actual test** has eight different steps, each measuring something the others do not:
///
///       1  Word memory        see eight words, type them back straight away
///       2  Reaction time      tap when the circle turns green, ten times
///       3  Speech description describe a picture aloud for twenty seconds
///       4  Spiral tracing     trace a guide spiral with a finger
///       5  Typing rhythm      nothing to do: timed while the user types in steps 1, 8 and the end
///       6  Trail-making       tap circles in order, then alternating numbers and letters
///       7  Finger tapping     tap two buttons in turn for ten seconds
///       8  Verbal fluency     type as many animals as possible in thirty seconds
///       final  Word memory again, typed, after everything else: the delayed recall
///
/// The recall of a list is a *screen* but not a separate *step*: it belongs to the word-memory
/// step that taught the list. A list has to be recalled after other things have happened, or it
/// would measure working memory rather than delayed recall, so the delayed recall comes at the
/// very end, as a closing part, about as long after the learning as the rest of the test takes.
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

  /// Type the list back straight away.
  immediateRecall,

  /// Tap when the circle turns green.
  reaction,

  /// Describe a picture aloud.
  speech,

  /// Trace the spiral.
  precision,

  /// The passive typing-rhythm step: explains itself and moves on.
  typingNote,

  /// Tap circles in order.
  trail,

  /// Tap two buttons in turn.
  tapping,

  /// Type animals.
  fluency,

  /// Type the list back at the end of the test.
  recallWords,
}

/// The kinds of step, as the user counts them.
enum StepKind {
  words,
  reaction,
  speech,
  precision,
  typing,
  trail,
  tapping,
  fluency;

  /// The step a screen belongs to.
  static StepKind of(ScreenKind screen) => switch (screen) {
    ScreenKind.learnWords ||
    ScreenKind.immediateRecall ||
    ScreenKind.recallWords => StepKind.words,
    ScreenKind.reaction => StepKind.reaction,
    ScreenKind.speech => StepKind.speech,
    ScreenKind.precision => StepKind.precision,
    ScreenKind.typingNote => StepKind.typing,
    ScreenKind.trail => StepKind.trail,
    ScreenKind.tapping => StepKind.tapping,
    ScreenKind.fluency => StepKind.fluency,
  };
}

/// One screen in a test.
class PlannedScreen {
  const PlannedScreen({required this.kind, this.stepNumber});

  final ScreenKind kind;

  /// The step this screen belongs to, counting from one, or null for the closing recall,
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
  });

  final TestKind kind;
  final List<PlannedScreen> screens;

  /// Steps as the user counts them: three or eight.
  final int totalSteps;

  /// The plan for a test of [kind].
  factory TestPlan.of(TestKind kind) => switch (kind) {
    TestKind.baseline => _baseline,
    TestKind.actual => _actual,
  };

  static const TestPlan _baseline = TestPlan._(
    kind: TestKind.baseline,
    totalSteps: kBaselineTestSteps,
    screens: [
      PlannedScreen(kind: ScreenKind.learnWords, stepNumber: 1),
      PlannedScreen(kind: ScreenKind.speech, stepNumber: 2),
      PlannedScreen(kind: ScreenKind.precision, stepNumber: 3),
      PlannedScreen(kind: ScreenKind.recallWords),
    ],
  );

  static const TestPlan _actual = TestPlan._(
    kind: TestKind.actual,
    totalSteps: kActualTestSteps,
    screens: [
      PlannedScreen(kind: ScreenKind.learnWords, stepNumber: 1),
      PlannedScreen(kind: ScreenKind.immediateRecall, stepNumber: 1),
      PlannedScreen(kind: ScreenKind.reaction, stepNumber: 2),
      PlannedScreen(kind: ScreenKind.speech, stepNumber: 3),
      PlannedScreen(kind: ScreenKind.precision, stepNumber: 4),
      PlannedScreen(kind: ScreenKind.typingNote, stepNumber: 5),
      PlannedScreen(kind: ScreenKind.trail, stepNumber: 6),
      PlannedScreen(kind: ScreenKind.tapping, stepNumber: 7),
      PlannedScreen(kind: ScreenKind.fluency, stepNumber: 8),
      PlannedScreen(kind: ScreenKind.recallWords),
    ],
  );

  int get length => screens.length;

  /// How many screens of [kind] the test has.
  int count(ScreenKind kind) => screens.where((s) => s.kind == kind).length;
}
