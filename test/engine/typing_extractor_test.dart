/// Typing-rhythm feature extraction.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:neurascan_ai/engine/extractors/typing_extractor.dart';

void main() {
  /// Builds events from a list of gaps, starting at an arbitrary clock offset.
  List<KeystrokeEvent> fromGaps(List<int> gaps, {int start = 100000}) {
    final events = [KeystrokeEvent(timestampMs: start)];
    var now = start;
    for (final gap in gaps) {
      now += gap;
      events.add(KeystrokeEvent(timestampMs: now));
    }
    return events;
  }

  group('median interval', () {
    test('is the gap itself when every gap is the same', () {
      final result = extractTypingFeatures(fromGaps(List.filled(10, 250)));
      expect(result.medianIntervalMs, 250.0);
      expect(result.usableIntervals, 10);
    });

    test('is unaffected by the absolute clock offset', () {
      final early = extractTypingFeatures(
        fromGaps(List.filled(10, 250), start: 0),
      );
      final late = extractTypingFeatures(
        fromGaps(List.filled(10, 250), start: 9999999),
      );
      expect(late.medianIntervalMs, early.medianIntervalMs);
    });

    test('resists one long pause', () {
      final gaps = [240, 250, 260, 250, 245, 255, 250, 248, 252, 250];
      final withPause = [...gaps, 1800];
      expect(
        extractTypingFeatures(fromGaps(withPause)).medianIntervalMs,
        closeTo(extractTypingFeatures(fromGaps(gaps)).medianIntervalMs, 6.0),
      );
    });

    test('events arriving out of order are sorted before differencing', () {
      // Events can be merged from more than one field within a session.
      final shuffled = [
        const KeystrokeEvent(timestampMs: 500),
        const KeystrokeEvent(timestampMs: 100),
        const KeystrokeEvent(timestampMs: 300),
      ];
      final result = extractTypingFeatures(shuffled);
      expect(result.usableIntervals, 2);
      expect(result.medianIntervalMs, 200.0);
    });
  });

  group('plausibility window', () {
    test('a gap for thought is excluded as not part of the rhythm', () {
      final result = extractTypingFeatures(
        fromGaps([250, 250, 250, kMaxInterKeyIntervalMs + 500, 250]),
      );
      expect(result.totalIntervals, 5);
      expect(result.usableIntervals, 4);
    });

    test('a key repeat or autocomplete burst is excluded', () {
      final result = extractTypingFeatures(
        fromGaps([250, 250, kMinInterKeyIntervalMs - 15, 250]),
      );
      expect(result.usableIntervals, 3);
    });

    test('gaps exactly on the boundaries are kept', () {
      final result = extractTypingFeatures(
        fromGaps([kMinInterKeyIntervalMs, kMaxInterKeyIntervalMs]),
      );
      expect(result.usableIntervals, 2);
    });
  });

  group('coefficient of variation', () {
    test('is zero for a perfectly even rhythm', () {
      final result = extractTypingFeatures(fromGaps(List.filled(12, 260)));
      expect(result.coefficientOfVariation, 0.0);
    });

    test('rises with an irregular rhythm at the same average', () {
      final even = extractTypingFeatures(
        fromGaps([250, 255, 245, 250, 252, 248, 250, 250, 251, 249]),
      );
      final ragged = extractTypingFeatures(
        fromGaps([120, 400, 150, 380, 130, 420, 140, 390, 160, 410]),
      );
      expect(
        ragged.coefficientOfVariation,
        greaterThan(even.coefficientOfVariation),
      );
    });

    test('is dimensionless, so a uniformly slower typist scores the same', () {
      final quick = extractTypingFeatures(fromGaps([100, 150, 200, 250]));
      final slow = extractTypingFeatures(fromGaps([200, 300, 400, 500]));
      expect(
        slow.coefficientOfVariation,
        closeTo(quick.coefficientOfVariation, 1e-12),
      );
    });
  });

  group('insufficient data', () {
    test('fewer than two events yields no intervals', () {
      expect(extractTypingFeatures(const []).totalIntervals, 0);
      expect(
        extractTypingFeatures(const [KeystrokeEvent(timestampMs: 0)])
            .totalIntervals,
        0,
      );
    });

    test('a short burst is flagged as not having enough data', () {
      final result = extractTypingFeatures(fromGaps([250, 250, 250]));
      expect(result.usableIntervals, 3);
      expect(result.hasEnoughData, isFalse);
    });

    test('enough intervals clears the threshold', () {
      final result = extractTypingFeatures(
        fromGaps(List.filled(kMinInterKeyIntervals, 250)),
      );
      expect(result.hasEnoughData, isTrue);
    });

    test('every gap being implausible yields zeroed features', () {
      final result = extractTypingFeatures(fromGaps([5000, 6000, 7000]));
      expect(result.totalIntervals, 3);
      expect(result.usableIntervals, 0);
      expect(result.medianIntervalMs, 0.0);
      expect(result.hasEnoughData, isFalse);
    });
  });
}
