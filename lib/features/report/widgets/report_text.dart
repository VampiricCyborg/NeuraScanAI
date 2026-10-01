/// Words for the results module: the sentence that says what a measurement did, and the labels
/// of the things a user logged.
///
/// The interpretation is a plain sentence in the user's terms ("Words remembered later was 1
/// word lower than your baseline"), built from numbers the analysis already holds. It describes
/// a change from the user's own usual pattern and nothing more: no condition is named, and
/// nothing is called normal or abnormal.
library;

import '../../../app/l10n/generated/app_localizations.dart';
import '../../../app/widgets.dart';
import '../../../engine/comparison.dart';
import '../../../engine/constants.dart';
import '../../trends/baseline_format.dart';
import '../calculators/analysis.dart';
import '../models.dart';

/// The user-facing name of a logged context note.
String contextNoteLabel(AppText text, ContextNote note) => switch (note) {
  ContextNote.sleepFair => text.resCtxSleepFair,
  ContextNote.sleepPoor => text.resCtxSleepPoor,
  ContextNote.fatigueSome => text.resCtxFatigueSome,
  ContextNote.fatigueVery => text.resCtxFatigueVery,
  ContextNote.illnessOrMedication => text.resCtxIllness,
};

/// The name of a test, as it appears in a step heading.
String testLabel(AppText text, TestId id) => switch (id) {
  TestId.wordMemory => text.sessionStepWords,
  TestId.reaction => text.sessionStepReaction,
  TestId.speech => text.sessionStepSpeech,
  TestId.spiral => text.sessionStepPrecision,
  TestId.typing => text.sessionStepTyping,
  TestId.trail => text.sessionStepTrail,
  TestId.tapping => text.sessionStepTapping,
  TestId.fluency => text.sessionStepFluency,
};

/// "Improved", "Stable" or "Worse", for a comparison with earlier tests.
String directionWord(AppText text, Change change) => switch (change) {
  Change.better => text.resImproved,
  Change.similar => text.resStable,
  Change.worse => text.resWorse,
};

/// "Better", "About the same" or "Worse", for a comparison with the baseline.
String changeWord(AppText text, Change change) => switch (change) {
  Change.better => text.comparisonBetter,
  Change.similar => text.comparisonSimilar,
  Change.worse => text.comparisonWorse,
};

/// The word for a trend.
String trendWord(AppText text, TrendDirection direction) => switch (direction) {
  TrendDirection.improving => text.resTrendImproving,
  TrendDirection.stable => text.resTrendStable,
  TrendDirection.declining => text.resTrendDeclining,
};

/// How far a measurement was from its baseline, worded in the measurement's own terms.
///
/// The word-recall scores are fractions, which read as nothing to a person, so the gap is given
/// in words ("1 word"). Everything else is formatted like the value itself.
String amountOfChange(AppText text, String key, double delta) {
  final size = delta.abs();
  if (key == 'immediate_recall' || key == 'delayed_recall') {
    return text.resAmountWords((size * kMemoryWordCount).round());
  }
  return formatFeatureValue(key, size);
}

/// The one-line interpretation of [summary]: what it did against the user's own baseline.
String interpretMetric(AppText text, MetricSummary summary) {
  final key = summary.spec.key;
  final name = featureLabel(text, key);

  switch (summary.state) {
    case MetricState.notMeasured:
      return text.resInterpNotMeasured(name);
    case MetricState.notCounted:
      return text.resInterpNotCounted(
        name,
        formatFeatureValue(key, summary.value!),
      );
    case MetricState.calibrating:
      return text.resInterpCalibrating(
        name,
        formatFeatureValue(key, summary.value!),
        summary.calibrationCollected,
        kExtensionTests,
      );
    case MetricState.measured:
      final change = summary.vsBaseline;
      final delta = summary.deltaFromBaseline!;
      // Within the usual spread is "about the same", whichever way it leans, and a change
      // that rounds to nothing in the words it is told in reads the same.
      final amount = amountOfChange(text, key, delta);
      final nothing =
          (key == 'immediate_recall' || key == 'delayed_recall') &&
          (delta.abs() * kMemoryWordCount).round() == 0;
      if (change == Change.similar || nothing) {
        return text.resInterpSame(name);
      }
      return delta > 0
          ? text.resInterpHigher(name, amount)
          : text.resInterpLower(name, amount);
  }
}
