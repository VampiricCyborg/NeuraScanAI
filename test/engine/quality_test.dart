/// UT1 and UT2 -- the step-level quality gates.
///
/// Mirrors `engine_lab/tests/test_quality_gates.py`, covering the report's
/// Table 9.2 rows UT1-2: the gates must reject fewer than eight voiced seconds and a spiral
/// traced below 70 %. The gates now apply to a single step -- a failed step is done again
/// rather than costing the user a whole test -- and there is no reaction-time gate because
/// the reaction task is gone.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:neurascan_ai/engine/constants.dart';
import 'package:neurascan_ai/engine/quality.dart';

void main() {
  group('UT1 -- a step that met its requirement passes the gates', () {
    test('nominal metrics are valid', () {
      final report = evaluateQuality(const TaskMetrics());
      expect(report.valid, isTrue);
      expect(report.failures, isEmpty);
    });

    test(
      'metrics exactly at the limits pass, because the gates are inclusive',
      () {
        // TaskMetrics defaults sit exactly on each limit, so the default instance is
        // the boundary case. Asserted here rather than assumed, since a future
        // change to either the defaults or the limits would otherwise make this
        // test quietly stop checking the boundary.
        const boundary = TaskMetrics();
        expect(boundary.voicedSeconds, kMinVoicedSeconds);
        expect(boundary.spiralCoverage, kMinSpiralCoverage);
        expect(evaluateQuality(boundary).valid, isTrue);
      },
    );

    test('generous speech and a full spiral pass', () {
      final report = evaluateQuality(
        const TaskMetrics(voicedSeconds: 18.0, spiralCoverage: 1.0),
      );
      expect(report.valid, isTrue);
    });

    test('a valid report gives a reassuring reason', () {
      expect(
        evaluateQuality(const TaskMetrics()).reason(),
        contains('met the quality checks'),
      );
    });
  });

  group('UT2 -- each gate rejects its own failure mode', () {
    test('near-silence for twenty seconds is rejected (TC5)', () {
      final report = evaluateQuality(const TaskMetrics(voicedSeconds: 3.0));
      expect(report.valid, isFalse);
      expect(report.failures.join(), contains('speech'));
    });

    test('speech just below the floor is rejected', () {
      final report = evaluateQuality(
        const TaskMetrics(voicedSeconds: kMinVoicedSeconds - 0.1),
      );
      expect(report.valid, isFalse);
    });

    test('a half-traced spiral is rejected (TC6)', () {
      final report = evaluateQuality(const TaskMetrics(spiralCoverage: 0.50));
      expect(report.valid, isFalse);
      expect(report.failures.join(), contains('spiral'));
    });

    test('a spiral just below the gate is rejected', () {
      final report = evaluateQuality(
        const TaskMetrics(spiralCoverage: kMinSpiralCoverage - 0.01),
      );
      expect(report.valid, isFalse);
    });

    test('every failure is reported, not just the first', () {
      final report = evaluateQuality(
        const TaskMetrics(voicedSeconds: 1.0, spiralCoverage: 0.1),
      );
      expect(report.valid, isFalse);
      expect(report.failures, hasLength(2));
    });

    test('the reason summarises every failure for the retry prompt', () {
      final report = evaluateQuality(
        const TaskMetrics(voicedSeconds: 0.0, spiralCoverage: 0.2),
      );
      expect(report.reason(), contains('speech'));
      expect(report.reason(), contains('spiral'));
    });
  });

  group('the reaction and tapping gates', () {
    test('three anticipations are rejected (TC4)', () {
      final report = evaluateQuality(
        const TaskMetrics(anticipations: kMaxAnticipations + 1),
      );
      expect(report.valid, isFalse);
      expect(report.failures.join(), contains('before the stimulus'));
    });

    test('two anticipations are tolerated as ordinary impatience', () {
      expect(evaluateQuality(const TaskMetrics()).valid, isTrue);
    });

    test('too few usable reaction trials are rejected', () {
      final report = evaluateQuality(
        const TaskMetrics(validReactionTrials: kMinValidReactionTrials - 1),
      );
      expect(report.valid, isFalse);
      expect(report.failures.join(), contains('reaction trials'));
    });

    test('too few taps are rejected', () {
      final report = evaluateQuality(
        const TaskMetrics(validTaps: kMinValidTaps - 1),
      );
      expect(report.valid, isFalse);
      expect(report.failures.join(), contains('taps'));
    });

    test('the default sits exactly on every limit', () {
      const boundary = TaskMetrics();
      expect(boundary.anticipations, kMaxAnticipations);
      expect(boundary.validReactionTrials, kMinValidReactionTrials);
      expect(boundary.validTaps, kMinValidTaps);
      expect(evaluateQuality(boundary).valid, isTrue);
    });
  });
}
