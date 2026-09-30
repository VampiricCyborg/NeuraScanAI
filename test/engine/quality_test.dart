/// UT1 and UT2 -- the task-level quality gates.
///
/// Mirrors `engine_lab/tests/test_quality_gates.py`, covering the report's
/// Table 9.2 rows UT1-2: the gates must reject more than two anticipations, fewer
/// than eight voiced seconds, and a spiral traced below 70 %.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:neurascan_ai/engine/constants.dart';
import 'package:neurascan_ai/engine/quality.dart';

void main() {
  group('UT1 -- a session that met every task requirement passes the gates', () {
    test('nominal metrics are valid', () {
      final report = evaluateQuality(const TaskMetrics());
      expect(report.valid, isTrue);
      expect(report.failures, isEmpty);
    });

    test('two anticipations are tolerated as ordinary impatience', () {
      final report = evaluateQuality(
        const TaskMetrics(anticipations: kMaxAnticipations),
      );
      expect(report.valid, isTrue);
    });

    test(
      'metrics exactly at the limits pass, because the gates are inclusive',
      () {
        // TaskMetrics defaults sit exactly on each limit, so the default instance is
        // the boundary case. Asserted here rather than assumed, since a future
        // change to either the defaults or the limits would otherwise make this
        // test quietly stop checking the boundary.
        const boundary = TaskMetrics();
        expect(boundary.anticipations, lessThanOrEqualTo(kMaxAnticipations));
        expect(boundary.validReactionTrials, kMinValidReactionTrials);
        expect(boundary.voicedSeconds, kMinVoicedSeconds);
        expect(boundary.spiralCoverage, kMinSpiralCoverage);
        expect(evaluateQuality(boundary).valid, isTrue);
      },
    );

    test('a valid report gives a reassuring reason', () {
      expect(
        evaluateQuality(const TaskMetrics()).reason(),
        contains('met the quality checks'),
      );
    });
  });

  group('UT2 -- each gate rejects its own failure mode', () {
    test('three anticipations invalidate the session (TC4)', () {
      final report = evaluateQuality(const TaskMetrics(anticipations: 3));
      expect(report.valid, isFalse);
      expect(report.failures.join(), contains('before the stimulus'));
    });

    test('near-silence for twenty seconds invalidates the session (TC5)', () {
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

    test('a half-traced spiral invalidates the session (TC6)', () {
      final report = evaluateQuality(const TaskMetrics(spiralCoverage: 0.50));
      expect(report.valid, isFalse);
      expect(report.failures.join(), contains('spiral'));
    });

    test('too few usable reaction trials invalidate the session', () {
      final report = evaluateQuality(const TaskMetrics(validReactionTrials: 4));
      expect(report.valid, isFalse);
      expect(report.failures.join(), contains('reaction trials'));
    });

    test('every failure is reported, not just the first', () {
      final report = evaluateQuality(
        const TaskMetrics(
          anticipations: 5,
          voicedSeconds: 1.0,
          spiralCoverage: 0.1,
        ),
      );
      expect(report.valid, isFalse);
      expect(report.failures, hasLength(3));
    });

    test('the reason summarises every failure for the retry prompt', () {
      final report = evaluateQuality(
        const TaskMetrics(voicedSeconds: 0.0, spiralCoverage: 0.2),
      );
      expect(report.reason(), contains('speech'));
      expect(report.reason(), contains('spiral'));
    });
  });
}
