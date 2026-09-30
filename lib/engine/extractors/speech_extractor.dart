/// Speech features from the twenty-second picture description.
///
/// Two features come out of the audio: how fast the user speaks, and how much of
/// the time they spend not speaking. Both are transcription-free, and that is the
/// central design constraint rather than a convenience. Speech-to-text would mean
/// either shipping audio to a server or carrying a large on-device model, and it
/// would produce a transcript -- a far more sensitive artefact than two numbers.
/// So the audio is reduced to features on the device and then deleted.
///
/// The speaking-rate method follows de Jong and Wempe: count syllable nuclei as
/// local peaks in the intensity envelope that clear a dip on both sides, and
/// divide by the speaking time. It is approximate, and it is not meant to be
/// otherwise -- what matters is that it is *consistently* approximate, because
/// every session is compared against the same user measured the same way.
library;

import 'dart:math' as math;
import 'dart:typed_data';

/// Analysis frame length. At 16 kHz this is 25 ms, the usual compromise: long
/// enough for a stable energy estimate, short enough to resolve a syllable.
const int kFrameSamples = 400;

/// Frame advance, giving 10 ms steps and so a 100 Hz envelope.
const int kHopSamples = 160;

/// Sample rate the capture layer is required to deliver.
const int kSampleRate = 16000;

/// Silence longer than this counts as a pause rather than as the ordinary gap
/// between syllables. 250 ms is the conventional boundary.
const int kPauseThresholdMs = 250;

/// How far below the speech peak a frame may fall and still count as voiced.
///
/// A fixed absolute threshold cannot work across phones whose microphone gains
/// differ by more than this range, so the threshold is relative to the loudest
/// part of this particular recording.
const double kVoicingFloorDb = 25.0;

/// Absolute level below which a frame cannot be speech, whatever the recording's
/// own peak was.
///
/// The relative threshold alone has a failure mode: given a recording with no
/// speech in it, the peak is itself silence, so every frame clears a threshold
/// set relative to it and the whole twenty seconds reads as voiced. That is the
/// exact case the eight-second quality gate exists to catch, so it must not be
/// hidden. A phone quiet enough to record speech below this level would not
/// produce usable features anyway.
const double kAbsoluteSilenceDb = -65.0;

/// A syllable peak must clear the surrounding dips by this much.
///
/// Without a dip requirement, the amplitude ripple inside a single long vowel
/// would each be counted as a separate syllable.
const double kSyllableDipDb = 2.0;

/// Peaks closer together than this are the same syllable seen twice.
const int kMinSyllableSpacingMs = 80;

/// Speech features and the quality numbers that go with them.
class SpeechResult {
  const SpeechResult({
    required this.speakingRate,
    required this.pauseRatio,
    required this.voicedSeconds,
    required this.syllableCount,
    required this.totalSeconds,
  });

  /// Syllable nuclei per minute of voiced time. This is the `speaking_rate`
  /// feature.
  ///
  /// Per voiced minute rather than per elapsed minute, so that it measures
  /// articulation speed; how much of the time the user was silent is the other
  /// feature's job.
  final double speakingRate;

  /// Silent time in pauses of at least [kPauseThresholdMs], over total time.
  /// This is the `pause_ratio` feature.
  final double pauseRatio;

  /// Seconds of voiced speech detected. A quality signal, not a feature.
  final double voicedSeconds;

  /// Syllable nuclei counted.
  final int syllableCount;

  /// Length of the recording.
  final double totalSeconds;
}

/// Frame-level energy in decibels, one value every [kHopSamples].
///
/// Exposed separately because the spiral task's tremor analysis uses the same
/// framing idea, and because a test can assert on the envelope directly rather
/// than only on the features derived from it.
List<double> intensityEnvelopeDb(Float64List samples) {
  if (samples.length < kFrameSamples) return const [];

  final envelope = <double>[];
  for (var start = 0;
      start + kFrameSamples <= samples.length;
      start += kHopSamples) {
    var sumSquares = 0.0;
    for (var i = start; i < start + kFrameSamples; i++) {
      sumSquares += samples[i] * samples[i];
    }
    final rms = math.sqrt(sumSquares / kFrameSamples);
    // Floored before the log so that a digitally silent frame gives a very low
    // number rather than negative infinity.
    envelope.add(20.0 * math.log(math.max(rms, 1e-10)) / math.ln10);
  }
  return envelope;
}

/// Extracts the speech features from 16 kHz mono [samples] in -1..1.
SpeechResult extractSpeechFeatures(Float64List samples) {
  final totalSeconds = samples.length / kSampleRate;
  final envelope = intensityEnvelopeDb(samples);

  if (envelope.isEmpty) {
    return SpeechResult(
      speakingRate: 0.0,
      pauseRatio: totalSeconds > 0 ? 1.0 : 0.0,
      voicedSeconds: 0.0,
      syllableCount: 0,
      totalSeconds: totalSeconds,
    );
  }

  const frameSeconds = kHopSamples / kSampleRate;

  // The voicing threshold is set relative to this recording's own peak, so that
  // a quiet phone and a loud one produce comparable results. The absolute floor
  // is what stops a recording containing no speech from reading as entirely
  // voiced, since its peak would be silence too.
  final peakDb = envelope.reduce(math.max);
  final voicingThreshold = math.max(
    peakDb - kVoicingFloorDb,
    kAbsoluteSilenceDb,
  );
  final voiced = [for (final db in envelope) db >= voicingThreshold];
  final voicedFrames = voiced.where((isVoiced) => isVoiced).length;
  final voicedSeconds = voicedFrames * frameSeconds;

  // Only silence that lasts is a pause. Brief dips are the gaps between
  // syllables and stop consonants, and counting them would make every speaker
  // look hesitant.
  final minPauseFrames = (kPauseThresholdMs / 1000 / frameSeconds).round();
  var pauseFrames = 0;
  var runLength = 0;
  for (var i = 0; i <= voiced.length; i++) {
    final isSilent = i < voiced.length && !voiced[i];
    if (isSilent) {
      runLength++;
    } else {
      if (runLength >= minPauseFrames) pauseFrames += runLength;
      runLength = 0;
    }
  }

  final syllables = _countSyllableNuclei(
    envelope: envelope,
    voiced: voiced,
    frameSeconds: frameSeconds,
  );

  return SpeechResult(
    speakingRate: voicedSeconds > 0 ? syllables / (voicedSeconds / 60.0) : 0.0,
    pauseRatio: envelope.isEmpty ? 0.0 : pauseFrames / envelope.length,
    voicedSeconds: voicedSeconds,
    syllableCount: syllables,
    totalSeconds: totalSeconds,
  );
}

/// Counts syllable nuclei as dip-separated intensity peaks within voiced frames.
int _countSyllableNuclei({
  required List<double> envelope,
  required List<bool> voiced,
  required double frameSeconds,
}) {
  final minSpacingFrames =
      math.max(1, (kMinSyllableSpacingMs / 1000 / frameSeconds).round());

  // Candidate peaks: a local maximum that the user was actually voicing.
  final peaks = <int>[];
  for (var i = 1; i < envelope.length - 1; i++) {
    if (!voiced[i]) continue;
    if (envelope[i] >= envelope[i - 1] && envelope[i] > envelope[i + 1]) {
      peaks.add(i);
    }
  }
  if (peaks.isEmpty) return 0;

  // Keep a peak only if the valley between it and the last accepted peak is deep
  // enough, and if it is far enough away in time. When a peak is rejected for
  // being too close, the louder of the two is the one that survives, so a
  // syllable is attributed to its own nucleus rather than to a shoulder.
  final accepted = <int>[peaks.first];
  for (var p = 1; p < peaks.length; p++) {
    final candidate = peaks[p];
    final previous = accepted.last;

    var valley = envelope[previous];
    for (var i = previous; i <= candidate; i++) {
      valley = math.min(valley, envelope[i]);
    }

    final dipFromPrevious = envelope[previous] - valley;
    final dipFromCandidate = envelope[candidate] - valley;
    final farEnough = candidate - previous >= minSpacingFrames;
    final deepEnough =
        dipFromPrevious >= kSyllableDipDb && dipFromCandidate >= kSyllableDipDb;

    if (farEnough && deepEnough) {
      accepted.add(candidate);
    } else if (envelope[candidate] > envelope[previous]) {
      accepted[accepted.length - 1] = candidate;
    }
  }

  return accepted.length;
}
