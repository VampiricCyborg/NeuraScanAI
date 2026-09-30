"""Reference implementation of the NeuraScan AI screening engine.

This package is the off-device counterpart of ``lib/engine/`` in the Flutter
app. It exists because the engine is the part of the project most likely to be
subtly wrong, and Python is a far cheaper place to pin its behaviour down with
tests than a mobile target is. The Dart code mirrors these modules, and the same
cases are asserted on both sides.

Nothing in here touches a device, a database or a network. It takes extracted
features in and produces a status, an index and an explanation out.
"""

from __future__ import annotations

from .baseline import (
    Baseline,
    median,
    median_absolute_deviation,
    robust_scale,
)
from .constants import (
    BASELINE_SESSIONS,
    DEFAULT_PERSISTENCE,
    DEFAULT_THRESHOLD,
    EWMA_LAMBDA,
    FAMILIARISATION_SESSIONS,
    MILD_FRACTION,
)
from .engine import (
    ScreeningEngine,
    Status,
    contribution_percentages,
    status_of,
)
from .features import (
    DOMAIN_WEIGHTS,
    FEATURE_KEYS,
    FEATURE_SPECS,
    SPEC_BY_KEY,
    Direction,
    Domain,
    FeatureSpec,
    Session,
    specs_for,
)
from .quality import QualityReport, TaskMetrics, evaluate_quality
from .scoring import (
    contributions,
    deviation_index,
    domain_scores,
    domain_scores_from,
    top_contributor,
)

__version__ = "1.0.0"

__all__ = [
    "BASELINE_SESSIONS",
    "DEFAULT_PERSISTENCE",
    "DEFAULT_THRESHOLD",
    "DOMAIN_WEIGHTS",
    "EWMA_LAMBDA",
    "FAMILIARISATION_SESSIONS",
    "FEATURE_KEYS",
    "FEATURE_SPECS",
    "MILD_FRACTION",
    "SPEC_BY_KEY",
    "Baseline",
    "Direction",
    "Domain",
    "FeatureSpec",
    "QualityReport",
    "ScreeningEngine",
    "Session",
    "Status",
    "TaskMetrics",
    "contribution_percentages",
    "contributions",
    "deviation_index",
    "domain_scores",
    "domain_scores_from",
    "evaluate_quality",
    "median",
    "median_absolute_deviation",
    "robust_scale",
    "specs_for",
    "status_of",
    "top_contributor",
]
