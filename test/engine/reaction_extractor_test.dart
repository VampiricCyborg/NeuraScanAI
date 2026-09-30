/// Reaction-time feature extraction.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:neurascan_ai/engine/extractors/reaction_extractor.dart';

void main() {
  List<ReactionTrial> responded(List<int> times) => [
    for (final ms in times) ReactionTrial.responded(ms),
  ];

  group('trial usability', () {
    test('a plausible response is usable', () {
      expect(const ReactionTrial.responded(320).isUsable, isTrue);
    });

    test('an anticipation is never usable', () {
      expect(const ReactionTrial.anticipation().isUsable, isFalse);
    });

    test('a timeout is never usable', () {
      expect(const ReactionTrial.timedOut().isUsable, isFalse);
    });

    test('an implausibly fast response is discarded as a lucky guess', () {
      expect(
        const ReactionTrial.responded(kMinPlausibleReactionMs - 1).isUsable,
        isFalse,
      );
      expect(
        const ReactionTrial.responded(kMinPlausibleReactionMs).isUsable,
        isTrue,
      );
    });

    test('an implausibly slow response is discarded as a lapse', () {
      expect(
        const ReactionTrial.responded(kMaxPlausibleReactionMs + 1).isUsable,
        isFalse,
      );
      expect(
        const ReactionTrial.responded(kMaxPlausibleReactionMs).isUsable,
        isTrue,
      );
    });
  });

  group('median', () {
    test('is the middle value of an odd number of trials', () {
      final result = extractReactionFeatures(responded([300, 320, 340]));
      expect(result.medianMs, 320.0);
    });

    test('averages the middle pair of an even number of trials', () {
      final result = extractReactionFeatures(responded([300, 320, 340, 360]));
      expect(result.medianMs, 330.0);
    });

    test('does not depend on the order trials arrived in', () {
      final ascending = extractReactionFeatures(
        responded([280, 300, 320, 340]),
      );
      final shuffled = extractReactionFeatures(responded([340, 280, 320, 300]));
      expect(shuffled.medianMs, ascending.medianMs);
    });

    test('resists one slow trial, which a mean would not', () {
      final times = [300, 310, 320, 330, 1900];
      final result = extractReactionFeatures(responded(times));
      final mean = times.reduce((a, b) => a + b) / times.length;
      expect(result.medianMs, 320.0);
      expect(mean, greaterThan(600));
    });
  });

  group('coefficient of variation', () {
    test('is zero for perfectly consistent trials', () {
      final result = extractReactionFeatures(responded([320, 320, 320, 320]));
      expect(result.coefficientOfVariation, 0.0);
    });

    test('rises with spread at the same average', () {
      final tight = extractReactionFeatures(responded([310, 315, 325, 330]));
      final loose = extractReactionFeatures(responded([200, 260, 380, 440]));
      expect(
        loose.coefficientOfVariation,
        greaterThan(tight.coefficientOfVariation),
      );
    });

    test('is dimensionless, so scaling every trial leaves it unchanged', () {
      final slow = extractReactionFeatures(responded([300, 400, 500, 600]));
      final slower = extractReactionFeatures(responded([600, 800, 1000, 1200]));
      expect(
        slower.coefficientOfVariation,
        closeTo(slow.coefficientOfVariation, 1e-12),
      );
    });

    test(
      'is zero when only one trial survives, having no spread to estimate',
      () {
        final result = extractReactionFeatures([
          const ReactionTrial.responded(320),
          const ReactionTrial.anticipation(),
          const ReactionTrial.timedOut(),
        ]);
        expect(result.usableTrials, 1);
        expect(result.coefficientOfVariation, 0.0);
      },
    );

    test('uses the sample standard deviation', () {
      // Values 100, 200, 300: mean 200, sample SD 100, so the CV is 0.5. With the
      // population SD it would be about 0.408, so this pins which one is used.
      final result = extractReactionFeatures(responded([200, 300, 400]));
      expect(result.medianMs, 300.0);
      expect(result.coefficientOfVariation, closeTo(100 / 300, 1e-12));
    });
  });

  group('anticipations and counts', () {
    test('anticipations are counted, not scored', () {
      final result = extractReactionFeatures([
        const ReactionTrial.anticipation(),
        const ReactionTrial.anticipation(),
        ...responded([300, 320, 340]),
      ]);
      expect(result.anticipations, 2);
      expect(result.usableTrials, 3);
      expect(result.totalTrials, 5);
      expect(result.medianMs, 320.0);
    });

    test(
      'timeouts reduce the usable count without counting as anticipations',
      () {
        final result = extractReactionFeatures([
          const ReactionTrial.timedOut(),
          ...responded([300, 320]),
        ]);
        expect(result.anticipations, 0);
        expect(result.usableTrials, 2);
        expect(result.totalTrials, 3);
      },
    );

    test(
      'a session with nothing usable returns zeros rather than throwing',
      () {
        // The quality gate is what turns this into an invalid session; the extractor
        // must not crash on the way there.
        final result = extractReactionFeatures(
          List.filled(10, const ReactionTrial.anticipation()),
        );
        expect(result.usableTrials, 0);
        expect(result.medianMs, 0.0);
        expect(result.coefficientOfVariation, 0.0);
        expect(result.anticipations, 10);
      },
    );

    test('an empty trial list returns zeros', () {
      final result = extractReactionFeatures(const []);
      expect(result.totalTrials, 0);
      expect(result.medianMs, 0.0);
    });
  });
}
