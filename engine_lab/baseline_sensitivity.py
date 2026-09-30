"""How does the size of the baseline affect false alerts on healthy users?

The report's evaluation used a six-session baseline.  The app has since moved to
fewer, and a median and MAD from only a handful of points are a rougher estimate
of a person's normal, so this measures the cost rather than assuming it.

Healthy synthetic users are drawn from the report's Table A.2: a personal trait
level (between-person SD), day-to-day noise (within-person SD), a practice effect
decaying over the first sessions, tired days that the check-in reports 80 % of
the time, and a few invalid sessions.  Nobody in this simulation declines, so any
NOTABLE_DEVIATION is a false alert.

Run:  python baseline_sensitivity.py [users] [sessions]
"""

from __future__ import annotations

import math
import random
import sys

import neurascan_engine.baseline as baseline_module
import neurascan_engine.engine as engine_module
from neurascan_engine import (
    DOMAIN_WEIGHTS,
    FEATURE_SPECS,
    Direction,
    ScreeningEngine,
    Session,
    Status,
)

# Table A.2: (mean, between-person SD, within-person SD).
TABLE_A2 = {
    "delayed_recall": (0.75, 0.12, 0.06),
    "reaction_median": (320.0, 45.0, 18.0),
    "reaction_cv": (0.15, 0.04, 0.02),
    "speaking_rate": (140.0, 20.0, 8.0),
    "pause_ratio": (0.22, 0.06, 0.025),
    "spiral_rmse": (6.0, 1.5, 0.6),
    "tremor_index": (0.10, 0.03, 0.012),
    "inter_key_interval": (260.0, 50.0, 15.0),
    "inter_key_cv": (0.35, 0.08, 0.035),
}

PRACTICE_SD = 1.0  # within-SDs, decaying
PRACTICE_TAU = 1.5  # sessions
TIRED_RATE = 0.15
TIRED_EFFECT = 1.5  # within-SDs, in the worse direction
TIRED_REPORTED = 0.80
INVALID_RATE = 0.03


def worse_sign(key: str) -> int:
    spec = next(s for s in FEATURE_SPECS if s.key == key)
    return 1 if spec.direction is Direction.HIGHER_IS_WORSE else -1


def healthy_user(rng: random.Random, sessions: int) -> list[Session]:
    traits = {k: rng.gauss(m, b) for k, (m, b, _) in TABLE_A2.items()}
    out: list[Session] = []
    for i in range(sessions):
        tired = rng.random() < TIRED_RATE
        features = {}
        for key, (_, _, within) in TABLE_A2.items():
            value = traits[key] + rng.gauss(0, within)
            worse = worse_sign(key)
            value += worse * within * PRACTICE_SD * math.exp(-i / PRACTICE_TAU)
            if tired:
                value += worse * within * TIRED_EFFECT
            features[key] = value
        out.append(
            Session(
                features=features,
                valid=rng.random() >= INVALID_RATE,
                confounded=tired and rng.random() < TIRED_REPORTED,
            )
        )
    return out


DECLINE_ONSET = 25
DECLINE_END = 60
DECLINE_SDS = 3.0  # within-person SDs by the last session, as in the report
COGNITIVE_FEATURES = ("delayed_recall", "reaction_median", "reaction_cv")


def declining_user(rng: random.Random, sessions: int) -> list[Session]:
    """A healthy user whose cognitive features drift worse from session 25."""
    out = healthy_user(rng, sessions)
    for i, session in enumerate(out):
        if i < DECLINE_ONSET:
            continue
        progress = min(1.0, (i - DECLINE_ONSET) / (DECLINE_END - DECLINE_ONSET))
        for key in COGNITIVE_FEATURES:
            within = TABLE_A2[key][2]
            session.features[key] += worse_sign(key) * within * DECLINE_SDS * progress
    return out


def alert_rates(
    baseline_size: int,
    floor: float,
    users: int,
    sessions: int,
    threshold: float,
    seed: int,
) -> tuple[float, float]:
    """(false-alert rate on healthy users, detection rate on declining users)."""
    engine_module.BASELINE_SESSIONS = baseline_size
    baseline_module.PRIOR_SCALE_FLOOR_FRACTION = floor

    def alerted_at(stream: list[Session]) -> int | None:
        engine = ScreeningEngine(threshold=threshold)
        for i, session in enumerate(stream):
            if engine.update(session)["status"] is Status.NOTABLE_DEVIATION:
                return i
        return None

    rng = random.Random(seed)
    false_alerts = sum(
        alerted_at(healthy_user(rng, sessions)) is not None for _ in range(users)
    )
    rng = random.Random(seed + 1)
    detected = 0
    for _ in range(users):
        first = alerted_at(declining_user(rng, sessions))
        detected += first is not None and first >= DECLINE_ONSET
    return false_alerts / users, detected / users


def main() -> None:
    users = int(sys.argv[1]) if len(sys.argv) > 1 else 300
    sessions = int(sys.argv[2]) if len(sys.argv) > 2 else 60
    assert abs(sum(DOMAIN_WEIGHTS.values()) - 1.0) < 1e-9

    print(
        f"{users} users per group, {sessions} sessions each.  FA = false alerts on "
        "healthy users; DET = cognitive declines caught.\n"
    )
    header = (
        f"{'baseline':>8} {'floor':>6} | {'FA@1.0':>7} {'DET@1.0':>8} | "
        f"{'FA@1.5':>7} {'DET@1.5':>8}"
    )
    print(header)
    print("-" * len(header))
    rows = [(6, 0.0), (4, 0.0), (3, 0.0), (3, 0.5), (3, 0.75), (3, 1.0), (3, 1.25)]
    for size, floor in rows:
        cells = []
        for threshold in (1.0, 1.5):
            fa, det = alert_rates(size, floor, users, sessions, threshold, seed=7)
            cells += [f"{fa * 100:>6.1f}%", f"{det * 100:>7.1f}%"]
        print(
            f"{size:>8} {floor:>6.2f} | {cells[0]} {cells[1]} | {cells[2]} {cells[3]}"
        )


if __name__ == "__main__":
    main()
