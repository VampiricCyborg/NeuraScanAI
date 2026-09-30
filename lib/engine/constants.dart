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

// --- Test structure ----------------------------------------------------------
//
// A test is a run of steps, and every step is one of three kinds: words, speech or
// precision. A step in an actual test has to be something the baseline also measured, or
// there would be nothing to compare it with, so an actual test is more of the same three.

/// Baseline tests in all: the practice run and the ones that count.
const int kBaselineTests = kFamiliarisationSessions + kBaselineSessions;

/// Steps in a baseline test: words, speech and precision.
const int kBaselineTestSteps = 3;

/// Word lists learned and recalled in an actual test.
const int kActualWordSteps = 3;

/// Speech pictures described in an actual test.
const int kActualSpeechSteps = 3;

/// Precision tracings in an actual test.
const int kActualPrecisionSteps = 2;

/// Steps in an actual test. Eight, so that each measurement is taken several times and a
/// single unusual step cannot define the result: the test's value for a measurement is the
/// median of its repeats.
const int kActualTestSteps =
    kActualWordSteps + kActualSpeechSteps + kActualPrecisionSteps;

// --- Session design ----------------------------------------------------------

/// Words presented in the memory task. Eight is short enough to encode in
/// forty-five seconds and long enough that the recall fraction has useful
/// resolution.
const int kMemoryWordCount = 8;

/// Duration of the spoken picture description.
const int kSpeechSeconds = 20;

/// Turns in the guide spiral.
const int kSpiralTurns = 3;

/// Silence longer than this counts as a pause rather than as a gap between
/// syllables.
const int kPauseThresholdMs = 250;

/// Default gap between test reminders.
const int kReminderIntervalDays = 2;
