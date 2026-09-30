"""How do the baseline size and the spread safeguard affect false and missed alerts?

The report's evaluation used a six-session baseline of single measurements.  The
app now sets its baseline from three tests (after a practice run), each measured
once, and then scores *actual tests* that repeat every measurement several times.
A median and MAD from only three points are a rough estimate of a person's
normal, so this measures the cost of that rather than assuming it, and is what
``PRIOR_SCALE_FLOOR_FRACTION`` was tuned with.

Synthetic users are drawn from the report's Table A.2: a personal trait level
(between-person SD), day-to-day noise (within-person SD), a practice effect that
decays over the first tests, and tired days the check-in reports 80 % of the
time.  Half of the within-person variance is shared by everything measured on the
same day and half is independent between steps, so repeating a step within a test
reduces the second half but not the first -- averaging eight steps does not make
a bad night disappear.

* healthy users never decline, so any NOTABLE_DEVIATION is a false alert;
* "cognitive decline" drifts delayed recall for the worse from test 25, reaching
  three within-person SDs by test 60, as in the report;
* "motor decline" does the same to the two tracing measurements.

Run:  python baseline_sensitivity.py [users] [tests]
"""

from __future__ import annotations

import math
import random
import statistics
import sys

import neurascan_engine.baseline as baseline_module
import neurascan_engine.engine as engine_module
from neurascan_engine import (
    FEATURE_SPECS,
    Direction,
    ScreeningEngine,
    Session,
    Status,
)

# Table A.2 (mean, between-person SD, within-person SD) for the five measurements.
TABLE_A2 = {
    "delayed_recall": (0.75, 0.12, 0.06),
    "speaking_rate": (140.0, 20.0, 8.0),
    "pause_ratio": (0.22, 0.06, 0.025),
    "spiral_rmse": (6.0, 1.5, 0.6),
    "tremor_index": (0.10, 0.03, 0.012),
}

#: How many times an actual test repeats each measurement.  Three word lists, three
#: speech pictures (each giving rate and pauses) and two tracings: eight steps.
STEPS_PER_FEATURE = {
    "delayed_recall": 3,
    "speaking_rate": 3,
    "pause_ratio": 3,
    "spiral_rmse": 2,
    "tremor_index": 2,
}

BASELINE_TESTS = 4  # one practice run and three that count
PRACTICE_SD = 1.0  # within-SDs, decaying
PRACTICE_TAU = 1.5  # tests
TIRED_RATE = 0.15
TIRED_EFFECT = 1.5  # within-SDs, in the worse direction
TIRED_REPORTED = 0.80

DECLINE_ONSET = 25
DECLINE_END = 60
DECLINE_SDS = 3.0
COGNITIVE = ("delayed_recall",)
MOTOR = ("spiral_rmse", "tremor_index")

#: Share of within-person variance shared by everything measured on one day.
DAY_SHARE = 0.5


def worse_sign(key: str) -> int:
    spec = next(s for s in FEATURE_SPECS if s.key == key)
    return 1 if spec.direction is Direction.HIGHER_IS_WORSE else -1


def simulate_user(
    rng: random.Random, tests: int, declining: tuple[str, ...] = ()
) -> list[Session]:
    """A user's tests in order: baseline tests first, then actual tests."""
    traits = {k: rng.gauss(m, b) for k, (m, b, _) in TABLE_A2.items()}
    out: list[Session] = []
    for i in range(tests):
        tired = rng.random() < TIRED_RATE
        actual = i >= BASELINE_TESTS
        features: dict[str, float] = {}
        for key, (_, _, within) in TABLE_A2.items():
            day = rng.gauss(0, within * math.sqrt(DAY_SHARE))
            step_sd = within * math.sqrt(1.0 - DAY_SHARE)
            worse = worse_sign(key)

            shift = worse * within * PRACTICE_SD * math.exp(-i / PRACTICE_TAU)
            if tired:
                shift += worse * within * TIRED_EFFECT
            if key in declining and i >= DECLINE_ONSET:
                progress = min(1.0, (i - DECLINE_ONSET) / (DECLINE_END - DECLINE_ONSET))
                shift += worse * within * DECLINE_SDS * progress

            steps = STEPS_PER_FEATURE[key] if actual else 1
            readings = [
                traits[key] + day + shift + rng.gauss(0, step_sd) for _ in range(steps)
            ]
            features[key] = statistics.median(readings)
        out.append(
            Session(
                features=features, confounded=tired and rng.random() < TIRED_REPORTED
            )
        )
    return out


def first_alert(stream: list[Session], threshold: float) -> int | None:
    engine = ScreeningEngine(threshold=threshold)
    for i, session in enumerate(stream):
        if engine.update(session)["status"] is Status.NOTABLE_DEVIATION:
            return i
    return None


def rates(
    pooled: int, floor: float, users: int, tests: int, threshold: float, seed: int
) -> tuple[float, float, float]:
    """(false-alert rate, cognitive-decline detection, motor-decline detection)."""
    engine_module.BASELINE_SESSIONS = pooled
    baseline_module.PRIOR_SCALE_FLOOR_FRACTION = floor

    def group(declining: tuple[str, ...], offset: int) -> list[int | None]:
        rng = random.Random(seed + offset)
        return [
            first_alert(simulate_user(rng, tests, declining), threshold)
            for _ in range(users)
        ]

    healthy = group((), 0)
    cognitive = group(COGNITIVE, 1)
    motor = group(MOTOR, 2)
    false_alerts = sum(a is not None for a in healthy) / users
    detect_c = sum(a is not None and a >= DECLINE_ONSET for a in cognitive) / users
    detect_m = sum(a is not None and a >= DECLINE_ONSET for a in motor) / users
    return false_alerts, detect_c, detect_m


def main() -> None:
    users = int(sys.argv[1]) if len(sys.argv) > 1 else 300
    tests = int(sys.argv[2]) if len(sys.argv) > 2 else 60

    print(
        f"{users} users per group, {tests} tests each.  FA = false alerts on healthy "
        "users;\nCOG / MOT = cognitive / motor declines caught.\n"
    )
    thresholds = (0.75, 1.0)
    header = f"{'pooled':>6} {'floor':>6} |" + "".join(
        f" {'FA':>6} {'COG':>6} {'MOT':>6} |" for _ in thresholds
    )
    print(f"{'':>13} |" + "".join(f"{'threshold ' + str(t):^21} |" for t in thresholds))
    print(header)
    print("-" * len(header))
    for pooled, floor in [(6, 0.0), (3, 0.0), (3, 0.25), (3, 0.5), (3, 0.75), (3, 1.0)]:
        cells = ""
        for threshold in thresholds:
            fa, cog, mot = rates(pooled, floor, users, tests, threshold, seed=7)
            cells += f" {fa * 100:>5.1f}% {cog * 100:>5.1f}% {mot * 100:>5.1f}% |"
        print(f"{pooled:>6} {floor:>6.2f} |{cells}")


if __name__ == "__main__":
    main()
