"""Tuning constants for the NeuraScan AI screening engine.

Every value here is a deliberate design choice documented in the project
report; none of them are learned from data.  The Dart engine in
``lib/engine/`` mirrors this module so that the two implementations stay in
step, and the unit tests in ``engine_lab/tests/`` pin the behaviour that
depends on them.
"""

from __future__ import annotations

# --- Baseline construction -------------------------------------------------

#: Sessions discarded before the baseline pool starts collecting.  The first
#: couple of runs are dominated by the practice effect: people get faster and
#: recall more simply because they have seen the tasks before, and folding
#: that improvement into "normal" would make every later session look like a
#: decline.
FAMILIARISATION_SESSIONS = 2

#: Valid, unconfounded sessions summarised into the frozen baseline.  Four, which
#: is the project team's decision after trying the app: six felt like too long
#: before the app had anything to say.  At one session every two to three days,
#: two familiarisation sessions plus four pooled ones is about two weeks.
#:
#: The trade-off is worth knowing.  A median and a MAD from four observations
#: are noisier than from six, so the frozen baseline is a rougher estimate of the
#: user's normal, and the alert thresholds calibrated in the report's simulation
#: (which used six) are not guaranteed to hold the same false-alert rate.  The
#: persistence rule and EWMA still stand between one unlucky baseline and an
#: alert, but the simulation should be re-run with this value before the
#: report's figures are quoted for it.
BASELINE_SESSIONS = 4

#: Consistency constant that rescales a median absolute deviation so that it
#: estimates the standard deviation of a normal distribution.
MAD_TO_SIGMA = 1.4826

#: A baseline scale of zero would make every later z-score infinite, which
#: happens easily on bounded features -- a user who recalls 6 of 8 words in
#: every baseline session has a MAD of exactly zero.  The scale is
#: therefore floored at a small fraction of the median, with an absolute
#: epsilon as a last resort for features whose median is itself zero.
SCALE_FLOOR_FRACTION = 0.02
SCALE_FLOOR_ABSOLUTE = 1e-9

# --- Deviation fusion ------------------------------------------------------

#: Smoothing factor of the exponentially weighted moving average applied to
#: the per-session deviation index.  At 0.3 a single session can move the
#: smoothed value by at most a third of the gap, so noise is damped while a
#: sustained shift still comes through within a handful of sessions.
EWMA_LAMBDA = 0.3

#: Smoothed deviation level treated as notable.  One unit means the user's
#: weighted, worsening-only deviation equals one of their own robust standard
#: deviations.
DEFAULT_THRESHOLD = 1.0

#: Consecutive valid sessions the smoothed index must stay above the
#: threshold before a notable deviation is raised.  Three sessions is about a
#: week at the default reminder cadence, which is long enough to rule out a
#: single bad day without delaying a real trend unreasonably.
DEFAULT_PERSISTENCE = 3

#: Fraction of the threshold at which a result is reported as mild rather
#: than stable.  This is an informational band only; it never raises an alert.
MILD_FRACTION = 0.6

# --- Quality gates ---------------------------------------------------------

#: Taps landing before the stimulus appears.  Up to two are treated as
#: ordinary impatience and the trials are simply discarded; a third suggests
#: the user is tapping rhythmically rather than reacting, which would make
#: the reaction features meaningless.
MAX_ANTICIPATIONS = 2

#: Voiced seconds required from the twenty-second picture description.  Below
#: this the speaking-rate and pause-ratio estimates rest on too little
#: speech to be comparable with the baseline.
MIN_VOICED_SECONDS = 8.0

#: Share of the guide spiral the trace must cover before the task counts.  A
#: partial trace biases the radial-error statistics towards whichever part of
#: the spiral was drawn.
MIN_SPIRAL_COVERAGE = 0.70

#: Reaction trials that must survive discarding to compute a median and a
#: coefficient of variation.
MIN_VALID_REACTION_TRIALS = 6
