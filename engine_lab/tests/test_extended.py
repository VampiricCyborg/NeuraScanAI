"""The eighteen features, and calibrating the thirteen a baseline test cannot measure.

A baseline test has three steps, so it supplies only the five core features.  The
other thirteen come from steps only a full test has.  They get their baseline from
the user's first few full tests, and until then they are reported as raw values and
left out of the deviation index.  These tests pin that behaviour, and the scoring
rules that let a test be scored on whichever features have a baseline.
"""

from __future__ import annotations

import pytest

from neurascan_engine import (
    CORE_FEATURE_KEYS,
    DOMAIN_WEIGHTS,
    EXTENDED_FEATURE_KEYS,
    EXTENSION_TESTS,
    FEATURE_KEYS,
    FEATURE_SPECS,
    SPEC_BY_KEY,
    Baseline,
    Direction,
    Domain,
    ScreeningEngine,
    Session,
    Status,
    contributions,
    deviation_index,
    domain_scores_from,
    feature_contributions,
    normalised_weights,
    status_of,
)

from .conftest import (
    NOMINAL,
    WITHIN_SD,
    feed_baseline,
    make_full_session,
    make_session,
    varied_baseline_sessions,
    varied_full_sessions,
)


class TestTheFeatureTable:
    """The eight tests and the features each one measures."""

    #: Which features each of the eight tests yields.
    TESTS = {
        "word memory": ("immediate_recall", "delayed_recall"),
        "reaction time": ("reaction_median", "reaction_cv"),
        "speech description": ("speaking_rate", "pause_ratio"),
        "spiral tracing": ("spiral_rmse", "tremor_index"),
        "typing rhythm": ("inter_key_interval", "inter_key_cv"),
        "trail-making": ("completion_time", "error_count", "switch_cost"),
        "finger tapping": ("tap_rate", "tap_interval_cv", "fatigue_decay"),
        "verbal fluency": ("valid_word_count", "fluency_half_ratio"),
    }

    def test_there_are_eighteen_features(self) -> None:
        assert len(FEATURE_KEYS) == 18
        assert len(set(FEATURE_KEYS)) == 18

    def test_every_test_is_covered_and_nothing_else(self) -> None:
        listed = [key for keys in self.TESTS.values() for key in keys]
        assert sorted(listed) == sorted(FEATURE_KEYS)

    def test_features_are_in_test_order(self) -> None:
        listed = [key for keys in self.TESTS.values() for key in keys]
        assert list(FEATURE_KEYS) == listed

    def test_the_core_features_are_the_three_baseline_steps(self) -> None:
        assert set(CORE_FEATURE_KEYS) == {
            "delayed_recall",
            "speaking_rate",
            "pause_ratio",
            "spiral_rmse",
            "tremor_index",
        }

    def test_core_and_extended_partition_the_features(self) -> None:
        assert set(CORE_FEATURE_KEYS) | set(EXTENDED_FEATURE_KEYS) == set(FEATURE_KEYS)
        assert not set(CORE_FEATURE_KEYS) & set(EXTENDED_FEATURE_KEYS)
        assert len(EXTENDED_FEATURE_KEYS) == 13

    def test_every_domain_has_features(self) -> None:
        for domain in Domain:
            assert any(spec.domain is domain for spec in FEATURE_SPECS), domain

    @pytest.mark.parametrize(
        ("key", "direction"),
        [
            ("immediate_recall", Direction.LOWER_IS_WORSE),
            ("delayed_recall", Direction.LOWER_IS_WORSE),
            ("reaction_median", Direction.HIGHER_IS_WORSE),
            ("reaction_cv", Direction.HIGHER_IS_WORSE),
            ("speaking_rate", Direction.LOWER_IS_WORSE),
            ("pause_ratio", Direction.HIGHER_IS_WORSE),
            ("spiral_rmse", Direction.HIGHER_IS_WORSE),
            ("tremor_index", Direction.HIGHER_IS_WORSE),
            ("inter_key_interval", Direction.HIGHER_IS_WORSE),
            ("inter_key_cv", Direction.HIGHER_IS_WORSE),
            ("completion_time", Direction.HIGHER_IS_WORSE),
            ("error_count", Direction.HIGHER_IS_WORSE),
            ("switch_cost", Direction.HIGHER_IS_WORSE),
            ("tap_rate", Direction.LOWER_IS_WORSE),
            ("tap_interval_cv", Direction.HIGHER_IS_WORSE),
            ("fatigue_decay", Direction.HIGHER_IS_WORSE),
            ("valid_word_count", Direction.LOWER_IS_WORSE),
            ("fluency_half_ratio", Direction.LOWER_IS_WORSE),
        ],
    )
    def test_direction_of_each_feature(self, key: str, direction: Direction) -> None:
        assert SPEC_BY_KEY[key].direction is direction

    def test_typing_is_the_interaction_area(self) -> None:
        for key in ("inter_key_interval", "inter_key_cv"):
            assert SPEC_BY_KEY[key].domain is Domain.INTERACTION

    def test_the_nominal_and_spread_tables_match_the_features(self) -> None:
        assert set(NOMINAL) == set(FEATURE_KEYS)
        assert set(WITHIN_SD) == set(FEATURE_KEYS)

    def test_spreads_in_the_test_fixtures_are_the_ones_the_engine_uses(self) -> None:
        for spec in FEATURE_SPECS:
            assert WITHIN_SD[spec.key] == spec.typical_day_to_day_sd, spec.key

    def test_the_provisional_spreads_are_flagged(self) -> None:
        """Only the figures from the report's Table A.2 are unflagged."""
        unflagged = {s.key for s in FEATURE_SPECS if not s.provisional}
        assert unflagged == {
            "delayed_recall",
            "reaction_median",
            "reaction_cv",
            "speaking_rate",
            "pause_ratio",
            "spiral_rmse",
            "tremor_index",
            "inter_key_interval",
            "inter_key_cv",
        }

    def test_domain_weights_sum_to_one(self) -> None:
        assert sum(DOMAIN_WEIGHTS.values()) == pytest.approx(1.0)


class TestAPartialBaseline:
    """A baseline that has the core features and is waiting for the rest."""

    def test_fit_from_baseline_tests_covers_only_the_core(self) -> None:
        baseline = Baseline.fit(varied_baseline_sessions())
        assert set(baseline.median) == set(CORE_FEATURE_KEYS)
        assert not baseline.is_complete

    def test_fit_ignores_extended_features_a_session_happens_to_carry(self) -> None:
        baseline = Baseline.fit([make_full_session() for _ in range(3)])
        assert set(baseline.median) == set(CORE_FEATURE_KEYS)

    def test_pending_keys_are_the_extended_ones_in_order(self) -> None:
        baseline = Baseline.fit(varied_baseline_sessions())
        assert baseline.pending_keys() == EXTENDED_FEATURE_KEYS

    def test_extending_with_enough_full_tests_completes_it(self) -> None:
        baseline = Baseline.fit(varied_baseline_sessions())
        extended = baseline.extended(varied_full_sessions(3), required=3)
        assert extended.is_complete
        assert extended.pending_keys() == ()
        assert extended.median["reaction_median"] == pytest.approx(320.0)

    def test_extending_leaves_the_core_untouched(self) -> None:
        baseline = Baseline.fit(varied_baseline_sessions())
        extended = baseline.extended(varied_full_sessions(3), required=3)
        for key in CORE_FEATURE_KEYS:
            assert extended.median[key] == baseline.median[key]
            assert extended.scale[key] == baseline.scale[key]
        assert extended.session_count == baseline.session_count

    def test_too_few_values_leave_a_feature_pending(self) -> None:
        baseline = Baseline.fit(varied_baseline_sessions())
        extended = baseline.extended(varied_full_sessions(2), required=3)
        assert not extended.is_complete
        assert set(extended.pending_keys()) == set(EXTENDED_FEATURE_KEYS)

    def test_a_feature_is_fixed_from_the_first_values_only(self) -> None:
        """Later tests must not move a baseline once it is set."""
        baseline = Baseline.fit(varied_baseline_sessions())
        first = varied_full_sessions(3)
        later = [make_full_session(reaction_median=900.0) for _ in range(5)]
        extended = baseline.extended(first + later, required=3)
        assert extended.median["reaction_median"] == pytest.approx(320.0)

    def test_a_test_that_lacks_a_feature_does_not_count_for_it(self) -> None:
        """Typing missing from one test delays only the typing baseline."""
        baseline = Baseline.fit(varied_baseline_sessions())
        full = varied_full_sessions(3)
        del full[1].features["inter_key_interval"]
        extended = baseline.extended(full, required=3)
        assert "inter_key_interval" not in extended.median
        assert "reaction_median" in extended.median

    def test_extended_baselines_get_the_same_spread_floor(self) -> None:
        baseline = Baseline.fit(varied_baseline_sessions())
        extended = baseline.extended(
            [make_full_session() for _ in range(3)], required=3
        )
        for key in EXTENDED_FEATURE_KEYS:
            floor = 0.5 * SPEC_BY_KEY[key].typical_day_to_day_sd
            assert extended.scale[key] >= floor - 1e-12, key

    def test_a_partial_baseline_round_trips_through_json(self) -> None:
        baseline = Baseline.fit(varied_baseline_sessions())
        restored = Baseline.from_json(baseline.to_json())
        assert restored.pending_keys() == baseline.pending_keys()


class TestScoringOnWhateverHasABaseline:
    """A test is scored on the features that have a value and a baseline."""

    def test_a_feature_without_a_baseline_is_left_out(self) -> None:
        baseline = Baseline.fit(varied_baseline_sessions())
        scores = domain_scores_from(make_full_session().features, baseline)
        assert Domain.INTERACTION not in scores
        assert set(scores) == {Domain.COGNITIVE, Domain.SPEECH, Domain.MOTOR}

    def test_a_domain_with_no_data_is_absent_not_zero(self) -> None:
        """So a caller can tell no data from no change."""
        baseline = Baseline.fit(varied_baseline_sessions())
        scores = domain_scores_from(make_session().features, baseline)
        assert Domain.INTERACTION not in scores

    def test_weights_are_renormalised_over_the_domains_present(self) -> None:
        weights = normalised_weights(
            frozenset({Domain.COGNITIVE, Domain.SPEECH, Domain.MOTOR})
        )
        assert sum(weights.values()) == pytest.approx(1.0)
        assert weights[Domain.COGNITIVE] == pytest.approx(0.35 / 0.85)
        # Relative sizes are kept.
        assert weights[Domain.SPEECH] / weights[Domain.MOTOR] == pytest.approx(1.0)

    def test_all_four_domains_give_the_configured_weights(self) -> None:
        assert normalised_weights(frozenset(Domain)) == pytest.approx(DOMAIN_WEIGHTS)

    def test_no_domains_give_no_weights(self) -> None:
        assert normalised_weights(frozenset()) == {}

    def test_a_missing_domain_does_not_pull_the_index_towards_zero(self) -> None:
        """One declining domain reads the same whether or not typing was measured.

        Here the user has a complete baseline but typed too little in this test, so
        the interaction area has no data.  The index must equal the weighted sum over
        the three areas that do, with their weights re-normalised -- not that sum with
        the fourth area counted as zero.
        """
        complete = Baseline.fit(varied_baseline_sessions()).extended(
            varied_full_sessions(3), required=3
        )
        session = make_full_session(jitter={"spiral_rmse": 4.0, "tremor_index": 4.0})
        del session.features["inter_key_interval"]
        del session.features["inter_key_cv"]

        scores = domain_scores_from(session.features, complete)
        assert Domain.INTERACTION not in scores

        weights = normalised_weights(frozenset(scores))
        expected = sum(
            weights[domain] * max(0.0, score) for domain, score in scores.items()
        )
        assert deviation_index(scores) == pytest.approx(expected)
        # Counting the missing area as zero would have scaled it by 0.85.
        unnormalised = sum(
            DOMAIN_WEIGHTS[domain] * max(0.0, score) for domain, score in scores.items()
        )
        assert deviation_index(scores) > unnormalised

    def test_the_same_decline_reads_the_same_before_and_after_calibration(self) -> None:
        """A test of core features only scores identically under either baseline."""
        partial = Baseline.fit(varied_baseline_sessions())
        complete = partial.extended(varied_full_sessions(3), required=3)
        session = make_session(jitter={"delayed_recall": -4.0, "spiral_rmse": 4.0})
        assert deviation_index(
            domain_scores_from(session.features, partial)
        ) == pytest.approx(
            deviation_index(domain_scores_from(session.features, complete))
        )

    def test_contributions_always_name_every_domain(self) -> None:
        baseline = Baseline.fit(varied_baseline_sessions())
        shares = contributions(
            domain_scores_from(
                make_session(jitter={"delayed_recall": -4.0}).features, baseline
            )
        )
        assert set(shares) == set(Domain)
        assert shares[Domain.INTERACTION] == 0.0
        assert sum(shares.values()) == pytest.approx(1.0)

    def test_a_steady_test_falls_back_to_the_normalised_weights(self) -> None:
        baseline = Baseline.fit(varied_baseline_sessions())
        shares = contributions(
            domain_scores_from(
                make_session(jitter={"delayed_recall": 3.0}).features, baseline
            )
        )
        assert sum(shares.values()) == pytest.approx(1.0)
        assert shares[Domain.INTERACTION] == 0.0


class TestFeatureContributions:
    """Each feature's exact share of the index, for the top-contributors list."""

    @pytest.fixture
    def complete(self) -> Baseline:
        return Baseline.fit(varied_baseline_sessions()).extended(
            varied_full_sessions(3), required=3
        )

    def test_they_add_up_to_the_index(self, complete: Baseline) -> None:
        session = make_full_session(
            jitter={
                "delayed_recall": -3.0,
                "reaction_median": 2.0,
                "tap_rate": -2.0,
                "inter_key_cv": 3.0,
            }
        )
        scores = domain_scores_from(session.features, complete)
        parts = feature_contributions(session.features, complete.median, complete.scale)
        assert sum(parts.values()) == pytest.approx(deviation_index(scores))

    def test_the_declining_feature_leads(self, complete: Baseline) -> None:
        session = make_full_session(jitter={"tap_rate": -5.0})
        parts = feature_contributions(session.features, complete.median, complete.scale)
        assert max(parts, key=lambda k: parts[k]) == "tap_rate"

    def test_a_feature_offsetting_a_decline_is_negative(
        self, complete: Baseline
    ) -> None:
        session = make_full_session(
            jitter={"delayed_recall": -5.0, "immediate_recall": 2.0}
        )
        parts = feature_contributions(session.features, complete.median, complete.scale)
        assert parts["delayed_recall"] > 0.0
        assert parts["immediate_recall"] < 0.0

    def test_a_domain_that_is_not_worsening_contributes_nothing(
        self, complete: Baseline
    ) -> None:
        session = make_full_session(jitter={"tap_rate": 4.0, "delayed_recall": -4.0})
        parts = feature_contributions(session.features, complete.median, complete.scale)
        assert "tap_rate" not in parts
        assert "spiral_rmse" not in parts

    def test_only_features_with_a_baseline_appear(self) -> None:
        baseline = Baseline.fit(varied_baseline_sessions())
        session = make_full_session(
            jitter={"reaction_median": 5.0, "delayed_recall": -3.0}
        )
        parts = feature_contributions(session.features, baseline.median, baseline.scale)
        assert "reaction_median" not in parts
        assert "delayed_recall" in parts


class TestTheEngineCalibrates:
    """The engine fixes the extended baselines from the first full tests."""

    def ready(self) -> ScreeningEngine:
        engine = ScreeningEngine()
        feed_baseline(engine)
        assert engine.baseline_ready
        return engine

    def test_a_fresh_baseline_is_partial(self) -> None:
        engine = self.ready()
        assert engine.baseline is not None
        assert not engine.baseline.is_complete
        assert engine.calibration_collected == 0

    def test_the_first_full_tests_are_scored_on_the_core_only(self) -> None:
        engine = self.ready()
        result = engine.update(make_full_session(session_id="f1"))
        assert status_of(result) in (Status.STABLE, Status.MILD_DEVIATION)
        assert Domain.INTERACTION not in result["domains"]
        assert engine.calibration_collected == 1
        assert engine.baseline is not None
        assert not engine.baseline.is_complete

    def test_the_third_full_test_completes_the_baseline(self) -> None:
        engine = self.ready()
        results = [engine.update(s) for s in varied_full_sessions(EXTENSION_TESTS)]
        assert engine.baseline is not None
        assert engine.baseline.is_complete
        # Scored with the new features: the last test now has all four areas.
        assert set(results[-1]["domains"]) == set(Domain)
        assert Domain.INTERACTION not in results[0]["domains"]

    def test_later_full_tests_cannot_move_the_calibrated_baseline(self) -> None:
        engine = self.ready()
        for session in varied_full_sessions(EXTENSION_TESTS):
            engine.update(session)
        assert engine.baseline is not None
        before = dict(engine.baseline.median)
        for _ in range(4):
            engine.update(make_full_session(reaction_median=900.0))
        assert engine.baseline.median == before

    def test_a_tired_full_test_does_not_count_towards_calibration(self) -> None:
        engine = self.ready()
        engine.update(make_full_session(confounded=True, reaction_median=900.0))
        assert engine.calibration_collected == 0

    def test_an_invalid_full_test_does_not_count(self) -> None:
        engine = self.ready()
        engine.update(make_full_session(valid=False))
        assert engine.calibration_collected == 0

    def test_a_baseline_style_test_does_not_count(self) -> None:
        engine = self.ready()
        engine.update(make_session())
        assert engine.calibration_collected == 0

    def test_calibration_does_not_start_before_the_baseline_is_frozen(self) -> None:
        engine = ScreeningEngine()
        engine.update(make_full_session())
        assert engine.calibration_collected == 0

    def test_a_feature_missing_from_a_test_delays_only_that_feature(self) -> None:
        engine = self.ready()
        sessions = varied_full_sessions(3)
        del sessions[0].features["inter_key_interval"]
        for session in sessions:
            engine.update(session)
        assert engine.baseline is not None
        assert "inter_key_interval" not in engine.baseline.median
        assert "reaction_median" in engine.baseline.median
        # The fourth test supplies the third typing value.
        engine.update(make_full_session(inter_key_interval=265.0, session_id="f4"))
        assert "inter_key_interval" in engine.baseline.median

    def test_replaying_stored_tests_rebuilds_the_same_calibration(self) -> None:
        """The pool is not serialised: it is replayed from the stored tests."""
        live = self.ready()
        stored = varied_full_sessions(EXTENSION_TESTS)
        for session in stored:
            live.update(session)

        restored = ScreeningEngine()
        restored.baseline = Baseline.fit(varied_baseline_sessions())
        restored.calibrate_from(stored)

        assert live.baseline is not None and restored.baseline is not None
        assert restored.baseline.median == pytest.approx(live.baseline.median)
        assert restored.baseline.scale == pytest.approx(live.baseline.scale)

    def test_replay_does_not_touch_the_smoothing_state(self) -> None:
        engine = ScreeningEngine()
        engine.baseline = Baseline.fit(varied_baseline_sessions())
        engine.calibrate_from(varied_full_sessions(3))
        assert engine.ewma == 0.0
        assert engine.run == 0

    def test_a_complete_baseline_ignores_further_calibration(self) -> None:
        engine = self.ready()
        for session in varied_full_sessions(3):
            engine.update(session)
        collected = engine.calibration_collected
        engine.update(make_full_session())
        assert engine.calibration_collected == collected

    def test_the_serialised_state_reports_calibration(self) -> None:
        engine = self.ready()
        engine.update(make_full_session())
        assert engine.to_json()["calibrationCollected"] == 1


def test_session_reports_only_missing_core_features() -> None:
    incomplete = Session(features={"delayed_recall": 0.7})
    assert set(incomplete.missing_features()) == set(CORE_FEATURE_KEYS) - {
        "delayed_recall"
    }
    assert make_full_session().missing_features() == ()
