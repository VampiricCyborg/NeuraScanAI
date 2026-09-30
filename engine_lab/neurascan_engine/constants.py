"""Tuning constants for the NeuraScan AI screening engine.

Every value here is a deliberate design choice documented in the project
report; none of them are learned from data.  The Dart engine in
``lib/engine/`` mirrors this module so that the two implementations stay in
step, and the unit tests in ``engine_lab/tests/`` pin the behaviour that
depends on them.
"""

from __future__ import annotations

# --- Baseline construction -------------------------------------------------

#: Baseline tests discarded before the baseline pool starts collecting.  The
#: first run is dominated by the practice effect: people do better simply
#: because they have seen the tasks before, and folding that improvement into
#: "normal" would make every later test look like a decline.
#:
#: One, not the report's two: the project team's baseline is four tests in all,
#: and a practice run is the first of them, leaving three that count.
FAMILIARISATION_SESSIONS = 1

#: Valid, unconfounded baseline tests summarised into the frozen baseline.
#: Three, after the practice run: four baseline tests in all, each of three steps
#: (words, speech and a precision tracing).
#:
#: The trade-off is worth knowing.  A median and a MAD from three observations
#: are very noisy: the MAD of three values is just the smaller of two gaps, which
#: can be tiny by luck.  Unprotected, that gave a large share of healthy
#: simulated users a false "notable change" (``baseline_sensitivity.py``).  The
#: safeguard below (``PRIOR_SCALE_FLOOR_FRACTION``) is what makes it usable.
BASELINE_SESSIONS = 3

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

#: The baseline's spread for a feature is never allowed below this fraction of
#: that feature's typical day-to-day spread (``FeatureSpec.typical_day_to_day_sd``).
#:
#: Added because of what a small baseline does.  The MAD of three or four
#: numbers is very unstable -- with three values it is simply the smaller of two
#: gaps, which can be tiny by luck -- so an ordinary day then scores as a large
#: deviation.
#:
#: The value was chosen with ``baseline_sensitivity.py``, on healthy and
#: gradually-declining simulated users built from the report's Table A.2, with the
#: app's real structure: a practice run and three counted baseline tests, each
#: measured once, then actual tests that repeat every measurement.  At a
#: threshold of 1.0 (false alerts on healthy users / cognitive declines caught /
#: motor declines caught):
#:
#:   six counted tests, no floor   15 % / 72 % / 66 %   (the report's design)
#:   three counted, floor 0        41 % / 48 % / 52 %
#:   three counted, floor 0.5      14 % / 63 % / 63 %
#:   three counted, floor 0.75      4 % / 63 % / 45 %
#:   three counted, floor 1.0       1 % / 43 % / 22 %
#:
#: So 0.5 restores the false-alert rate the six-test design had, at the cost of
#: catching somewhat fewer of the simulated declines.  Higher floors buy fewer
#: false alerts by missing real declines, motor ones especially.  These figures
#: come from a quick re-implementation of the report's simulation, not the
#: report's own cohort, and are only reliable as a comparison between the rows.
#:
#: The floor is a fraction of a *spread*, never a value the centre is pulled
#: towards, so a baseline stays personal.
PRIOR_SCALE_FLOOR_FRACTION = 0.5

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
#
# These apply to a single step.  A step that fails is done again, so one quiet
# room or one slipped finger does not cost the user a whole test.

#: Voiced seconds required from the twenty-second picture description.  Below
#: this the speaking-rate and pause-ratio estimates rest on too little
#: speech to be comparable with the baseline.
MIN_VOICED_SECONDS = 8.0

#: Share of the guide spiral the trace must cover before the step counts.  A
#: partial trace biases the radial-error statistics towards whichever part of
#: the spiral was drawn.
MIN_SPIRAL_COVERAGE = 0.70
