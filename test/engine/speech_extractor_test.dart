/// Speech feature extraction.
///
/// The tests build synthetic audio rather than using recordings. That is a
/// deliberate limitation as well as a convenience: it lets a test state exactly
/// what it expects ("six amplitude bursts should read as six syllables"), but it
/// cannot show that the syllable counter tracks real speech. Only a pilot study
/// with real recordings could establish that, which is noted as future work.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:neurascan_ai/engine/extractors/speech_extractor.dart';

void main() {
  /// Silence of [seconds].
  Float64List silence(double seconds) =>
      Float64List((seconds * kSampleRate).round());

  /// A tone of [seconds] at [amplitude], standing in for a voiced stretch.
  Float64List tone(double seconds, {double amplitude = 0.3, double hz = 180}) {
    final samples = Float64List((seconds * kSampleRate).round());
    for (var i = 0; i < samples.length; i++) {
      samples[i] = amplitude * math.sin(2 * math.pi * hz * i / kSampleRate);
    }
    return samples;
  }

  Float64List concat(List<Float64List> parts) {
    final total = parts.fold<int>(0, (sum, part) => sum + part.length);
    final out = Float64List(total);
    var offset = 0;
    for (final part in parts) {
      out.setRange(offset, offset + part.length, part);
      offset += part.length;
    }
    return out;
  }

  /// [count] amplitude bursts separated by short dips, as syllables look.
  Float64List syllableBursts(
    int count, {
    double burst = 0.18,
    double dip = 0.07,
  }) {
    final parts = <Float64List>[];
    for (var i = 0; i < count; i++) {
      parts.add(tone(burst));
      if (i < count - 1) parts.add(tone(dip, amplitude: 0.02));
    }
    return concat(parts);
  }

  group('intensity envelope', () {
    test('is empty for audio shorter than one frame', () {
      expect(intensityEnvelopeDb(Float64List(kFrameSamples - 1)), isEmpty);
    });

    test('has one value per hop', () {
      final samples = tone(1.0);
      final expected =
          ((samples.length - kFrameSamples) / kHopSamples).floor() + 1;
      expect(intensityEnvelopeDb(samples), hasLength(expected));
    });

    test('a louder signal gives a higher level', () {
      final quiet = intensityEnvelopeDb(tone(0.5, amplitude: 0.05));
      final loud = intensityEnvelopeDb(tone(0.5, amplitude: 0.5));
      expect(loud.first, greaterThan(quiet.first));
    });

    test(
      'digital silence gives a very low level rather than negative infinity',
      () {
        final envelope = intensityEnvelopeDb(silence(0.5));
        expect(envelope, isNotEmpty);
        expect(envelope.first.isFinite, isTrue);
        expect(envelope.first, lessThan(-100));
      },
    );
  });

  group('voiced seconds', () {
    test('continuous speech is almost entirely voiced', () {
      final result = extractSpeechFeatures(tone(10.0));
      expect(result.voicedSeconds, closeTo(10.0, 0.2));
    });

    test('silence registers no voiced time', () {
      // With no speech at all the relative threshold has nothing to anchor to,
      // so the whole recording must read as unvoiced rather than as fully voiced.
      final result = extractSpeechFeatures(silence(20.0));
      expect(result.voicedSeconds, lessThan(1.0));
    });

    test('half speech and half silence is about half voiced', () {
      final result = extractSpeechFeatures(concat([tone(5.0), silence(5.0)]));
      expect(result.voicedSeconds, closeTo(5.0, 0.4));
    });

    test('voiced time never exceeds the recording length', () {
      final result = extractSpeechFeatures(tone(3.0));
      expect(result.voicedSeconds, lessThanOrEqualTo(result.totalSeconds));
    });

    test('the same speech at a different microphone gain reads the same', () {
      // The threshold is relative to this recording's peak precisely so that two
      // phones with different gains produce comparable numbers.
      final quiet = extractSpeechFeatures(
        concat([tone(4.0, amplitude: 0.03), silence(4.0)]),
      );
      final loud = extractSpeechFeatures(
        concat([tone(4.0, amplitude: 0.6), silence(4.0)]),
      );
      expect(loud.voicedSeconds, closeTo(quiet.voicedSeconds, 0.3));
    });
  });

  group('pause ratio', () {
    test('continuous speech has almost no pause', () {
      expect(extractSpeechFeatures(tone(10.0)).pauseRatio, lessThan(0.1));
    });

    test('a long silence raises the ratio', () {
      final result = extractSpeechFeatures(
        concat([tone(3.0), silence(3.0), tone(3.0)]),
      );
      expect(result.pauseRatio, closeTo(1 / 3, 0.1));
    });

    test('brief gaps between syllables are not counted as pauses', () {
      // Gaps shorter than the threshold are the ordinary spaces between syllables
      // and stop consonants; counting them would make every speaker look
      // hesitant.
      const brief = kPauseThresholdMs / 2 / 1000;
      final result = extractSpeechFeatures(
        concat([
          tone(2.0),
          silence(brief),
          tone(2.0),
          silence(brief),
          tone(2.0),
        ]),
      );
      expect(result.pauseRatio, lessThan(0.1));
    });

    test('a silence just over the threshold does count', () {
      const justOver = (kPauseThresholdMs + 120) / 1000;
      final result = extractSpeechFeatures(
        concat([tone(2.0), silence(justOver), tone(2.0)]),
      );
      expect(result.pauseRatio, greaterThan(0.0));
    });

    test('the ratio stays within zero and one', () {
      for (final samples in [
        tone(5.0),
        silence(5.0),
        concat([tone(2.0), silence(8.0)]),
      ]) {
        final ratio = extractSpeechFeatures(samples).pauseRatio;
        expect(ratio, inInclusiveRange(0.0, 1.0));
      }
    });
  });

  group('speaking rate', () {
    test('counts separated amplitude bursts as syllables', () {
      final result = extractSpeechFeatures(syllableBursts(10));
      expect(result.syllableCount, inInclusiveRange(8, 12));
    });

    test('more bursts in the same time means a higher rate', () {
      final slow = extractSpeechFeatures(
        syllableBursts(8, burst: 0.3, dip: 0.12),
      );
      final fast = extractSpeechFeatures(
        syllableBursts(20, burst: 0.1, dip: 0.05),
      );
      expect(fast.speakingRate, greaterThan(slow.speakingRate));
    });

    test('a steady tone is not counted as many syllables', () {
      // Without the dip requirement, the ripple inside one long vowel would each
      // be counted separately.
      final result = extractSpeechFeatures(tone(4.0));
      expect(result.syllableCount, lessThan(5));
    });

    test('silence yields no syllables and a zero rate', () {
      final result = extractSpeechFeatures(silence(20.0));
      expect(result.syllableCount, 0);
      expect(result.speakingRate, 0.0);
    });

    test(
      'the rate is per voiced minute, so added silence does not lower it',
      () {
        final tight = extractSpeechFeatures(syllableBursts(12));
        final padded = extractSpeechFeatures(
          concat([syllableBursts(12), silence(8.0)]),
        );
        expect(
          padded.speakingRate,
          closeTo(tight.speakingRate, tight.speakingRate * 0.35),
        );
      },
    );

    test('audio too short to frame yields zeroed features', () {
      final result = extractSpeechFeatures(Float64List(10));
      expect(result.syllableCount, 0);
      expect(result.speakingRate, 0.0);
      expect(result.voicedSeconds, 0.0);
    });

    test('an empty buffer does not divide by zero', () {
      final result = extractSpeechFeatures(Float64List(0));
      expect(result.totalSeconds, 0.0);
      expect(result.pauseRatio, 0.0);
    });
  });
}
