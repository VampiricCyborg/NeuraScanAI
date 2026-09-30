/// Tuning constants for the NeuraScan AI screening engine.
///
/// Every value here is a deliberate design choice documented in the project
/// report; none of them are learned from data. Mirrors
/// `engine_lab/neurascan_engine/constants.py`, and the tests in
/// `test/engine/` pin the behaviour that depends on them.
library;

// --- Baseline construction ---------------------------------------------------

/// Baseline tests discarded before the baseline pool starts collecting.
///
/// The first run is dominated by the practice effect: people do better simply because
/// they have seen the tasks before, and folding that improvement into "normal" would make
/// every later test look like a decline.
///
/// One, not the report's two: the project team's baseline is four tests in all, and a
/// practice run is the first of them, leaving three that count.
const int kFamiliarisationSessions = 1;

/// Valid, unconfounded baseline tests summarised into the frozen baseline.
///
/// Three, after the practice run: four baseline tests in all ([kBaselineTests]), each of
/// three steps (words, speech and a precision tracing).
///
/// The trade-off is worth knowing. A median and a MAD from three observations are very
/// noisy: the MAD of three values is just the smaller of two gaps, which can be tiny by
/// luck. Unprotected, that gave a large share of healthy simulated users a false "notable
/// change" (engine_lab/baseline_sensitivity.py). The safeguard below
/// ([kPriorScaleFloorFraction]) is what makes it usable.
const int kBaselineSessions = 3;

/// Consistency constant that rescales a median absolute deviation so that it
/// estimates the standard deviation of a normal distribution.
const double kMadToSigma = 1.4826;

/// A baseline scale of zero would make every later z-score infinite, which
/// happens easily on bounded features -- a user who recalls 6 of 8 words in every
/// baseline session has a MAD of exactly zero. The scale is therefore floored at a
/// small fraction of the median, with an absolute epsilon as a last resort for
/// features whose median is itself zero.
const double kScaleFloorFraction = 0.02;
const double kScaleFloorAbsolute = 1e-9;

/// The baseline's spread for a feature is never allowed below this fraction of that
/// feature's typical day-to-day spread (`FeatureSpec.typicalDayToDaySd`).
///
/// Added because of what a small baseline does. The MAD of three or four numbers is very
/// unstable -- with three values it is simply the smaller of two gaps, which can be tiny by
/// luck -- so an ordinary day then scores as a large deviation.
///
/// The value was chosen with engine_lab/baseline_sensitivity.py, on healthy and
/// gradually-declining simulated users built from the report's Table A.2, with the app's
/// real structure: a practice run and three counted baseline tests, each measured once, then
/// actual tests that repeat every measurement. At a threshold of 1.0 (false alerts on
/// healthy users / cognitive declines caught / motor declines caught):
///
///   six counted tests, no floor   15 % / 72 % / 66 %   (the report's design)
///   three counted, floor 0        41 % / 48 % / 52 %
///   three counted, floor 0.5      14 % / 63 % / 63 %
///   three counted, floor 0.75      4 % / 63 % / 45 %
///   three counted, floor 1.0       1 % / 43 % / 22 %
///
/// So 0.5 restores the false-alert rate the six-test design had, at the cost of catching
/// somewhat fewer of the simulated declines. Higher floors buy fewer false alerts by missing
/// real declines, motor ones especially. These figures come from a quick re-implementation
/// of the report's simulation, not the report's own cohort, and are only reliable as a
/// comparison between the rows.
///
/// The floor is a fraction of a *spread*, never a value the centre is pulled towards, so a
/// baseline stays personal.
const double kPriorScaleFloorFraction = 0.5;

// --- Deviation fusion --------------------------------------------------------

/// Smoothing factor of the exponentially weighted moving average applied to the
/// per-session deviation index.
///
/// At 0.3 a single session can move the smoothed value by at most a third of the
/// gap, so noise is damped while a sustained shift still comes through within a
/// handful of sessions.
const double kEwmaLambda = 0.3;

/// Smoothed deviation level treated as notable. One unit means the user's
/// weighted, worsening-only deviation equals one of their own robust standard
/// deviations.
const double kDefaultThreshold = 1.0;

/// Consecutive valid sessions the smoothed index must stay above the threshold
/// before a notable deviation is raised.
///
/// Three sessions is about a week at the default reminder cadence, which is long
/// enough to rule out a single bad day without delaying a real trend
/// unreasonably.
const int kDefaultPersistence = 3;

/// Fraction of the threshold at which a result is reported as mild rather than
/// stable. This is an informational band only; it never raises an alert.
const double kMildFraction = 0.6;

// --- Quality gates -----------------------------------------------------------
//
// These apply to a single step. A step that fails is done again, so one quiet room or
// one slipped finger does not cost the user a whole test.

/// Voiced seconds required from the twenty-second picture description. Below
/// this the speaking-rate and pause-ratio estimates rest on too little speech to
/// be comparable with the baseline.
const double kMinVoicedSeconds = 8.0;

/// Share of the guide spiral the trace must cover before the step counts. A
/// partial trace biases the radial-error statistics towards whichever part of
/// the spiral was drawn.
const double kMinSpiralCoverage = 0.70;

/// Taps that may land before the reaction stimulus appears. Up to two are treated as
/// ordinary impatience and the trials are simply discarded; a third suggests the user is
/// tapping rhythmically rather than reacting, which would make the reaction features
/// meaningless.
const int kMaxAnticipations = 2;

/// Reaction trials that must survive discarding to compute a median and a coefficient of
/// variation.
const int kMinValidReactionTrials = 6;

/// Correctly alternated taps required from the ten-second finger-tapping step. Below this
/// the rate and its regularity rest on too few intervals to mean anything, and the step is
/// asked for again.
const int kMinValidTaps = 10;

// --- Test structure ----------------------------------------------------------
//
// There are two kinds of test. A baseline test has three steps -- words, speech and a
// precision tracing -- and four of them set the baseline. A full (actual) test has eight
// different steps: word memory, reaction time, speech description, spiral tracing, typing
// rhythm (measured passively), trail-making, finger tapping and verbal fluency. The word
// memory step returns at the end as a closing part, for the delayed recall.

/// Baseline tests in all: the practice run and the ones that count.
const int kBaselineTests = kFamiliarisationSessions + kBaselineSessions;

/// Steps in a baseline test: words, speech and precision.
const int kBaselineTestSteps = 3;

/// Steps in a full test. Eight different ones, so that each measures something the others
/// do not: a single test then covers thinking, speech, movement and typing.
const int kActualTestSteps = 8;

/// Full tests whose values fix the baseline of each feature that only a full test measures.
///
/// The baseline tests are three steps (words, speech, precision), so the thirteen features
/// that only a full test measures have no baseline when the user finishes them. They get one
/// from their first few full tests instead, frozen in the same way: a median and a floored
/// robust scale. Until a feature has this many values it is reported as a raw number and
/// does not feed the deviation index. Three matches the number of counted baseline tests.
const int kExtensionTests = 3;

/// Full tests discarded before calibration starts collecting, to allow for practice on the
/// five new steps. Zero follows the project's decision to calibrate from the *first* three
/// full tests. Raising it to one would treat the first full test as a practice run for the
/// five new steps, as the first baseline test is for the three old ones, at the cost of a
/// slower start.
const int kExtensionFamiliarisation = 0;

// --- Session design ----------------------------------------------------------

/// Words presented in the memory task. Eight is short enough to encode in
/// forty-five seconds and long enough that the recall fraction has useful
/// resolution.
const int kMemoryWordCount = 8;

/// Reaction trials in the reaction-time step.
const int kReactionTrials = 10;

/// Bounds of the random foreperiod before a reaction stimulus. Randomising it is what stops
/// the user from learning the rhythm and anticipating.
const int kForeperiodMinMs = 1000;
const int kForeperiodMaxMs = 4000;

/// Duration of the spoken picture description.
const int kSpeechSeconds = 20;

/// Finger-tapping duration, in seconds.
const int kTappingSeconds = 10;

/// Verbal-fluency duration, in seconds.
const int kFluencySeconds = 30;

/// Circles in the two parts of the trail-making step: part A is the numbers 1 to 5, part B
/// alternates numbers and letters (1, A, 2, B, 3, C, 4, D). Part A is the user's own
/// reference speed, so the cost of switching is the extra time per tap part B takes.
const int kTrailPartACircles = 5;
const int kTrailPartBCircles = 8;

/// Turns in the guide spiral.
const int kSpiralTurns = 3;

/// Silence longer than this counts as a pause rather than as a gap between
/// syllables.
const int kPauseThresholdMs = 250;

/// Default gap between test reminders.
const int kReminderIntervalDays = 2;
