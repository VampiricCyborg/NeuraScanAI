/// Scoring the finger-tapping step.
///
/// The count must be of correctly alternated taps, so that hammering one button is not
/// rewarded, and the three features must move the way slowing, irregularity and fatigue do.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:neurascan_ai/engine/extractors/tapping_extractor.dart';

/// Perfectly alternating taps every [gapMs], for [seconds] seconds.
List<TapEvent> steady({int gapMs = 200, int seconds = 10}) => [
  for (var t = 0, i = 0; t <= seconds * 1000; t += gapMs, i++)
    TapEvent(timestampMs: t, side: i.isEven ? 0 : 1),
];

void main() {
  group('the rate', () {
    test('five taps a second reads as five', () {
      final result = extractTappingFeatures(steady());
      // 0, 200, ... 10000 is 51 taps in a ten-second window.
      expect(result.tapRate, closeTo(5.1, 1e-9));
    });

    test('slower tapping has a lower rate', () {
      final fast = extractTappingFeatures(steady());
      final slow = extractTappingFeatures(steady(gapMs: 400));
      expect(slow.tapRate, lessThan(fast.tapRate));
    });

    test('taps on the same button twice only count once', () {
      final result = extractTappingFeatures([
        const TapEvent(timestampMs: 100, side: 0),
        const TapEvent(timestampMs: 200, side: 0),
        const TapEvent(timestampMs: 300, side: 0),
        const TapEvent(timestampMs: 400, side: 1),
      ]);
      expect(result.validTaps, 2);
      expect(result.totalTaps, 4);
    });

    test('hammering one button gives a tiny rate', () {
      final result = extractTappingFeatures([
        for (var t = 0; t <= 10000; t += 100) TapEvent(timestampMs: t, side: 0),
      ]);
      expect(result.validTaps, 1);
    });

    test('taps outside the window are ignored', () {
      final result = extractTappingFeatures([
        const TapEvent(timestampMs: -50, side: 0),
        const TapEvent(timestampMs: 100, side: 0),
        const TapEvent(timestampMs: 10500, side: 1),
      ]);
      expect(result.totalTaps, 1);
      expect(result.validTaps, 1);
    });

    test('taps are scored in time order whatever order they arrive in', () {
      final result = extractTappingFeatures([
        const TapEvent(timestampMs: 300, side: 0),
        const TapEvent(timestampMs: 100, side: 0),
        const TapEvent(timestampMs: 200, side: 1),
      ]);
      expect(result.validTaps, 3);
    });

    test('no taps gives zeros, not a failure', () {
      final result = extractTappingFeatures(const []);
      expect(result.tapRate, 0.0);
      expect(result.intervalCv, 0.0);
      expect(result.fatigueDecay, 0.0);
      expect(result.validTaps, 0);
    });
  });

  group('the regularity', () {
    test('a metronome has no variability', () {
      expect(extractTappingFeatures(steady()).intervalCv, closeTo(0.0, 1e-9));
    });

    test('uneven tapping has a higher CV than steady tapping', () {
      var t = 0;
      final uneven = <TapEvent>[];
      for (var i = 0; t <= 10000; i++) {
        uneven.add(TapEvent(timestampMs: t, side: i.isEven ? 0 : 1));
        t += i.isEven ? 120 : 380;
      }
      expect(
        extractTappingFeatures(uneven).intervalCv,
        greaterThan(extractTappingFeatures(steady()).intervalCv + 0.3),
      );
    });

    test('one interval has no spread to measure', () {
      final result = extractTappingFeatures([
        const TapEvent(timestampMs: 0, side: 0),
        const TapEvent(timestampMs: 300, side: 1),
      ]);
      expect(result.intervalCv, 0.0);
    });
  });

  group('the fatigue decay', () {
    test('a steady tapper has none', () {
      expect(extractTappingFeatures(steady()).fatigueDecay, closeTo(0.0, 0.05));
    });

    test('slowing down gives a positive decay', () {
      // Fast for five seconds, then half the pace.
      final taps = <TapEvent>[];
      var t = 0;
      var i = 0;
      while (t <= 10000) {
        taps.add(TapEvent(timestampMs: t, side: i.isEven ? 0 : 1));
        t += t < 5000 ? 150 : 300;
        i++;
      }
      expect(extractTappingFeatures(taps).fatigueDecay, closeTo(0.5, 0.05));
    });

    test('speeding up gives a negative decay', () {
      final taps = <TapEvent>[];
      var t = 0;
      var i = 0;
      while (t <= 10000) {
        taps.add(TapEvent(timestampMs: t, side: i.isEven ? 0 : 1));
        t += t < 5000 ? 300 : 150;
        i++;
      }
      expect(extractTappingFeatures(taps).fatigueDecay, lessThan(0.0));
    });

    test('nothing in the first half does not divide by zero', () {
      final result = extractTappingFeatures([
        const TapEvent(timestampMs: 7000, side: 0),
        const TapEvent(timestampMs: 7300, side: 1),
      ]);
      expect(result.fatigueDecay, 0.0);
    });
  });

  test('a different window is respected', () {
    final result = extractTappingFeatures(steady(seconds: 5), durationMs: 5000);
    expect(result.tapRate, closeTo(result.validTaps / 5.0, 1e-12));
  });
}
