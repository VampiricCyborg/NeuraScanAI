"""UT6, UT7 and UT8 -- scoring, orientation and the exactness of explanations.

Covers Table 9.2 rows UT6-7 (lower recall raises the cognitive score, and
improvements never raise the index) and UT8 (domain contributions sum to 1).
"""

from __future__ import annotations

import pytest

from neurascan_engine import (
    DOMAIN_WEIGHTS,
    FEATURE_SPECS,
    Baseline,
    Direction,
    Domain,
    contributions,
    deviation_index,
    domain_scores_from,
    top_contributor,
)

from .conftest import make_session, varied_baseline_sessions


@pytest.fixture
def baseline() -> Baseline:
    """A baseline with genuine spread on every feature."""
    return Baseline.fit(varied_baseline_sessions())


class TestUT6OrientationRaisesTheRightScore:
    """UT6 -- worse performance produces a positive domain score."""

    def test_lower_recall_raises_the_cognitive_score(self, baseline: Baseline) -> None:
        worse = make_session(jitter={"delayed_recall": -3.0})
        scores = domain_scores_from(worse.features, baseline)
        assert scores[Domain.COGNITIVE] > 0.0

    def test_higher_recall_lowers_the_cognitive_score(self, baseline: Baseline) -> None:
        better = make_session(jitter={"delayed_recall": +3.0})
        scores = domain_scores_from(better.features, baseline)
        assert scores[Domain.COGNITIVE] < 0.0

    def test_slower_reaction_raises_the_cognitive_score(
        self, baseline: Baseline
    ) -> None:
        worse = make_session(jitter={"reaction_median": +3.0})
        assert domain_scores_from(worse.features, baseline)[Domain.COGNITIVE] > 0.0

    def test_slower_speech_raises_the_speech_score(self, baseline: Baseline) -> None:
        """Speaking rate is lower-is-worse, pause ratio is higher-is-worse."""
        worse = make_session(
            jitter={"speaking_rate": -3.0, "pause_ratio": +3.0},
        )
        assert domain_scores_from(worse.features, baseline)[Domain.SPEECH] > 0.0

    def test_shakier_tracing_raises_the_motor_score(self, baseline: Baseline) -> None:
        worse = make_session(jitter={"spiral_rmse": +3.0, "tremor_index": +3.0})
        assert domain_scores_from(worse.features, baseline)[Domain.MOTOR] > 0.0

    def test_slower_typing_raises_the_interaction_score(
        self, baseline: Baseline
    ) -> None:
        worse = make_session(
            jitter={"inter_key_interval": +3.0, "inter_key_cv": +3.0},
        )
        assert domain_scores_from(worse.features, baseline)[Domain.INTERACTION] > 0.0

    def test_a_typical_session_scores_near_zero(self, baseline: Baseline) -> None:
        scores = domain_scores_from(make_session().features, baseline)
        for domain, score in scores.items():
            assert abs(score) < 1.0, f"{domain} drifted without any change"

    def test_every_feature_is_oriented_so_positive_means_worse(self) -> None:
        """The orientation table itself, asserted feature by feature."""
        for spec in FEATURE_SPECS:
            if spec.direction is Direction.LOWER_IS_WORSE:
                assert spec.orient(-2.0) > 0.0
                assert spec.orient(+2.0) < 0.0
            else:
                assert spec.orient(+2.0) > 0.0
                assert spec.orient(-2.0) < 0.0


class TestUT7ImprovementsNeverRaiseTheIndex:
    """UT7 -- the index is one-sided; getting better cannot look like decline."""

    def test_an_all_round_improvement_gives_a_zero_index(
        self, baseline: Baseline
    ) -> None:
        better = make_session(
            jitter={
                "delayed_recall": +2.0,
                "reaction_median": -2.0,
                "reaction_cv": -2.0,
                "speaking_rate": +2.0,
                "pause_ratio": -2.0,
                "spiral_rmse": -2.0,
                "tremor_index": -2.0,
                "inter_key_interval": -2.0,
                "inter_key_cv": -2.0,
            }
        )
        scores = domain_scores_from(better.features, baseline)
        assert all(score < 0.0 for score in scores.values())
        assert deviation_index(scores) == 0.0

    def test_improving_one_domain_cannot_mask_another_declining(
        self, baseline: Baseline
    ) -> None:
        """The core of the clamp: a fast tapper who is forgetting still shows up."""
        declining_only = make_session(jitter={"delayed_recall": -4.0})
        mixed = make_session(
            jitter={
                "delayed_recall": -4.0,
                "spiral_rmse": -6.0,
                "tremor_index": -6.0,
            }
        )
        index_declining = deviation_index(
            domain_scores_from(declining_only.features, baseline)
        )
        index_mixed = deviation_index(domain_scores_from(mixed.features, baseline))
        assert index_mixed == pytest.approx(index_declining)

    def test_index_is_never_negative(self, baseline: Baseline) -> None:
        for sds in (-5.0, -2.0, 0.0, 2.0, 5.0):
            session = make_session(jitter={key: sds for key in ("delayed_recall",)})
            assert (
                deviation_index(domain_scores_from(session.features, baseline)) >= 0.0
            )

    def test_index_grows_with_the_size_of_the_decline(self, baseline: Baseline) -> None:
        indices = [
            deviation_index(
                domain_scores_from(
                    make_session(jitter={"delayed_recall": -sds}).features, baseline
                )
            )
            for sds in (1.0, 2.0, 3.0, 4.0)
        ]
        assert indices == sorted(indices)
        assert indices[0] < indices[-1]

    def test_index_respects_the_configured_weights(self, baseline: Baseline) -> None:
        """A pure single-domain deviation is that domain's weight times its score."""
        session = make_session(jitter={"spiral_rmse": +4.0, "tremor_index": +4.0})
        scores = domain_scores_from(session.features, baseline)
        expected = DOMAIN_WEIGHTS[Domain.MOTOR] * scores[Domain.MOTOR]
        assert deviation_index(scores) == pytest.approx(expected)


class TestUT8ContributionsSumToOne:
    """UT8 -- the explanation is exact, so the shares must total exactly 1."""

    def test_contributions_sum_to_one_for_a_single_domain_decline(
        self, baseline: Baseline
    ) -> None:
        session = make_session(jitter={"delayed_recall": -4.0})
        shares = contributions(domain_scores_from(session.features, baseline))
        assert sum(shares.values()) == pytest.approx(1.0)

    def test_contributions_sum_to_one_for_a_mixed_decline(
        self, baseline: Baseline
    ) -> None:
        session = make_session(
            jitter={
                "delayed_recall": -3.0,
                "speaking_rate": -2.0,
                "inter_key_interval": +2.0,
            }
        )
        shares = contributions(domain_scores_from(session.features, baseline))
        assert sum(shares.values()) == pytest.approx(1.0)

    def test_contributions_sum_to_one_with_no_deviation_at_all(self) -> None:
        """The stable case falls back to the weights, which also total 1."""
        shares = contributions({domain: 0.0 for domain in Domain})
        assert sum(shares.values()) == pytest.approx(1.0)
        assert shares == DOMAIN_WEIGHTS

    def test_contributions_sum_to_one_when_everything_improved(self) -> None:
        shares = contributions({domain: -3.0 for domain in Domain})
        assert sum(shares.values()) == pytest.approx(1.0)

    def test_an_improving_domain_contributes_nothing(self, baseline: Baseline) -> None:
        session = make_session(
            jitter={"delayed_recall": -4.0, "spiral_rmse": -5.0, "tremor_index": -5.0}
        )
        shares = contributions(domain_scores_from(session.features, baseline))
        assert shares[Domain.MOTOR] == 0.0
        assert shares[Domain.COGNITIVE] > 0.0

    def test_share_equals_weighted_score_over_the_index(
        self, baseline: Baseline
    ) -> None:
        """Exactness, stated as an identity rather than a tolerance."""
        session = make_session(
            jitter={"delayed_recall": -3.0, "pause_ratio": +3.0, "tremor_index": +3.0}
        )
        scores = domain_scores_from(session.features, baseline)
        index = deviation_index(scores)
        shares = contributions(scores)
        for domain, share in shares.items():
            expected = DOMAIN_WEIGHTS[domain] * max(0.0, scores[domain]) / index
            assert share == pytest.approx(expected)

    def test_top_contributor_names_the_declining_domain(
        self, baseline: Baseline
    ) -> None:
        session = make_session(jitter={"spiral_rmse": +6.0, "tremor_index": +6.0})
        scores = domain_scores_from(session.features, baseline)
        assert top_contributor(scores) is Domain.MOTOR
