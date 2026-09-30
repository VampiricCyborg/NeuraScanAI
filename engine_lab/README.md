# NeuraScan AI — Engine Lab

The off-device reference implementation of the screening engine, and the test
suite that pins its behaviour down.

## Why this exists

The screening engine is the part of NeuraScan most likely to be subtly wrong,
and the hardest part to debug on a phone. So it was written and tested here
first, in Python, where a full baseline-to-alert sequence runs in microseconds
and a failure points at a line number instead of a stack trace from a device.

The Dart engine under `../lib/engine/` mirrors these modules, and the same cases
are asserted on both sides. If the two implementations ever disagree, a test
fails rather than two users being told different things about the same data.

Nothing in this package touches a device, a database or a network. Extracted
features go in; a status, an index and an explanation come out.

## Layout

| File | Contents |
| --- | --- |
| `neurascan_engine/constants.py` | Every tuning value, with the reasoning for each |
| `neurascan_engine/features.py` | The nine features, four domains, and which direction is worse |
| `neurascan_engine/baseline.py` | Median/MAD baseline fitting and the scale floor |
| `neurascan_engine/scoring.py` | Domain z-scores, the deviation index, exact contributions |
| `neurascan_engine/quality.py` | Task-level quality gates |
| `neurascan_engine/engine.py` | The stateful engine: baseline → fusion → EWMA → persistence |

## Running the tests

```bash
cd engine_lab
python -m pip install -e ".[dev]"
python -m pytest
```

Or without installing the package, since `pythonpath` is set in
`pyproject.toml`:

```bash
cd engine_lab
python -m pytest
```

## What the tests cover

The suite is organised around the twelve numbered unit tests in Table 9.2 of the
project report. Each class below corresponds to one row of that table.

| Report ID | Test class | Behaviour asserted |
| --- | --- | --- |
| UT1 | `TestUT1AcceptableSessions` | A properly performed session passes every gate |
| UT2 | `TestUT2RejectedSessions` | More than 2 anticipations, under 8 s voiced speech, or under 70 % spiral coverage all invalidate the session |
| UT3 | `TestUT3FamiliarisationExcluded` | The first two sessions never reach the baseline; confounded ones do not either |
| UT4 | `TestUT4MedianResistsOutliers` | One extreme session cannot move the baseline centre |
| UT5 | `TestUT5ScaleFloor` | A perfectly flat baseline still yields finite z-scores |
| UT6 | `TestUT6OrientationRaisesTheRightScore` | Worse performance raises the score, in every domain and for every feature |
| UT7 | `TestUT7ImprovementsNeverRaiseTheIndex` | Getting better cannot look like decline, and cannot mask a real decline elsewhere |
| UT8 | `TestUT8ContributionsSumToOne` | Contributions total exactly 1, including when nothing is deviating |
| UT9 | `TestUT9ConfoundedSessionsAreExcluded` | A reported bad day leaves the EWMA, the run length and the history untouched |
| UT10 | `TestUT10OneBadSessionDoesNotAlert` | A single spike, even a severe one, never raises a notable deviation |
| UT11 | `TestUT11SustainedDeviationAlerts` | A deviation that persists for the configured window does alert, and explains itself |
| UT12 | `TestUT12InvalidSessionsAreIgnored` | A gated-out session changes no engine state, but still counts as familiarisation |

## Design decisions worth knowing before changing anything

**The index is one-sided.** `max(0, z)` is applied per domain before weighting,
so improvements are visible in the per-domain trends but cannot pull the overall
index down. A user who has got faster at tapping while forgetting more still
shows a cognitive deviation.

**The explanation is exact.** Because the fusion is a weighted sum, each
domain's share of the total *is* its contribution. There is no attribution
method and therefore no approximation error — `test_share_equals_weighted_score_over_the_index`
asserts the identity directly rather than a tolerance.

**Order of checks in `update()` is load-bearing.** Invalidity beats everything;
baseline building comes before scoring; a confound is checked before the EWMA is
touched, so a bad day cannot nudge the smoothed trend even slightly.

**Invalid sessions still count as familiarisation.** `_seen` increments before
the validity check. This is deliberate: familiarisation is about how many times
the user has met the tasks, and an attempt that failed a gate still taught them
the task.

**`MILD_DEVIATION` covers two situations.** A smoothed value between the mild
fraction and the threshold, *and* a value already over the threshold whose run
has not yet reached the persistence length. Both mean "worth watching" rather
than "this has persisted", so both are reported the same way.

**The `use_context` and `use_ewma` flags are for ablation.** They let the same
code path run with parts of the design switched off, which is how the report's
method comparison avoids giving NeuraScan an accidental advantage over the
baselines it is compared against.

## Not a diagnostic device

No status name in this package mentions a disease, and none should be added.
The app is a screening and awareness tool; the vocabulary it can use is bounded
by that.
