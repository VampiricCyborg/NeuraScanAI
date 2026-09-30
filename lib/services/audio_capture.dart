/// Microphone capture for the speech task, behind an interface.
///
/// The interface exists because of how the audio is treated. A recording is held only
/// long enough to extract two numbers from it and is then dropped, and it is never
/// written to disk. Making capture a service with a narrow contract -- hand back a
/// buffer, then forget it -- keeps that lifetime in one place instead of spread across
/// a task screen.
///
/// The implementation used in this build is [SimulatedAudioCapture]: it synthesises a
/// plausible speech-like waveform instead of opening the microphone. That is a real
/// limitation and worth stating plainly. The feature extraction it feeds is the
/// genuine article -- the same energy envelope, voice-activity detection and syllable
/// counting that would run on a real recording -- but the *input* is manufactured, so
/// nothing here demonstrates that the speech features track real speech. Doing that
/// needs a pilot study with real recordings, which is listed as future work.
///
/// Swapping in a real implementation means writing one class against this interface
/// and changing one provider. Nothing above this line knows which is in use.
library;

import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:clock/clock.dart';

import '../engine/extractors/speech_extractor.dart';

/// Why capture could not start.
enum AudioCaptureFailure {
  permissionDenied,
  noMicrophone,
  alreadyRecording,
  unknown;

  String get message => switch (this) {
    AudioCaptureFailure.permissionDenied =>
      'NeuraScan needs permission to use the microphone for this task.',
    AudioCaptureFailure.noMicrophone =>
      'No microphone was found on this device.',
    AudioCaptureFailure.alreadyRecording =>
      'A recording is already in progress.',
    AudioCaptureFailure.unknown =>
      'The microphone could not be started. Please try again.',
  };
}

/// Thrown when capture cannot start.
class AudioCaptureException implements Exception {
  const AudioCaptureException(this.failure);

  final AudioCaptureFailure failure;

  String get message => failure.message;

  @override
  String toString() => 'AudioCaptureException(${failure.name})';
}

/// Captures mono PCM at [kSampleRate] for the speech task.
abstract interface class AudioCaptureService {
  /// Whether the microphone may be used, requesting permission if needed.
  Future<bool> ensurePermission();

  /// Starts capturing.
  Future<void> start();

  /// Stops capturing and returns the samples, normalised to -1..1.
  ///
  /// The returned buffer is the only copy. Once the caller has extracted features
  /// from it and let it go, the recording is gone.
  Future<Float64List> stopAndTake();

  /// Abandons a recording in progress without returning it.
  ///
  /// Used when the user leaves the task part-way. Separate from [stopAndTake] so that
  /// discarding is an explicit action rather than a buffer nobody happened to read.
  Future<void> discard();

  /// True while capturing.
  bool get isRecording;
}

/// Synthesises speech-like audio instead of opening the microphone.
///
/// The waveform is a train of voiced bursts separated by short dips, with occasional
/// longer pauses -- enough structure for the envelope, the voice-activity detection and
/// the syllable counter to produce sensible, varying numbers. It is not speech, and the
/// class name says so.
class SimulatedAudioCapture implements AudioCaptureService {
  SimulatedAudioCapture({
    int? seed,
    this.syllablesPerMinute = 240,
    this.pauseFraction = 0.22,
    Duration? simulatedLatency,
  }) : _random = Random(seed),
       _latency = simulatedLatency ?? const Duration(milliseconds: 120);

  final Random _random;
  final Duration _latency;

  /// Roughly how fast the simulated speaker articulates.
  final int syllablesPerMinute;

  /// Roughly how much of the time the simulated speaker is silent.
  final double pauseFraction;

  DateTime? _startedAt;

  @override
  bool get isRecording => _startedAt != null;

  @override
  Future<bool> ensurePermission() async => true;

  @override
  Future<void> start() async {
    if (isRecording) {
      throw const AudioCaptureException(AudioCaptureFailure.alreadyRecording);
    }
    // A short delay so that callers which assume starting is asynchronous are
    // exercised the same way they would be against a real microphone.
    await Future<void>.delayed(_latency);
    _startedAt = clock.now();
  }

  @override
  Future<Float64List> stopAndTake() async {
    final startedAt = _startedAt;
    if (startedAt == null) return Float64List(0);
    _startedAt = null;

    final elapsed = clock.now().difference(startedAt);
    return _synthesise(elapsed);
  }

  @override
  Future<void> discard() async {
    _startedAt = null;
  }

  /// Builds a waveform lasting [duration].
  Float64List _synthesise(Duration duration) {
    final total = (duration.inMilliseconds / 1000 * kSampleRate).round();
    if (total <= 0) return Float64List(0);

    final samples = Float64List(total);
    final syllableSeconds = 60 / syllablesPerMinute;

    var cursor = 0;
    var phase = 0.0;
    while (cursor < total) {
      // Every so often, a pause long enough to count as one.
      if (_random.nextDouble() < pauseFraction / 3) {
        final pause = (kSampleRate * (0.3 + _random.nextDouble() * 0.5))
            .round();
        cursor = min(total, cursor + pause);
        continue;
      }

      // One syllable: a voiced burst then a short dip, so the syllable counter has a
      // dip to find between peaks.
      final burst = (kSampleRate * syllableSeconds * 0.62).round();
      final dip = (kSampleRate * syllableSeconds * 0.38).round();
      // A different fundamental per syllable, so the signal is not a single pure tone
      // that the envelope would read as one long vowel.
      final fundamental = 95 + _random.nextDouble() * 85;
      final amplitude = 0.18 + _random.nextDouble() * 0.16;

      for (var i = 0; i < burst && cursor < total; i++, cursor++) {
        phase += 2 * pi * fundamental / kSampleRate;
        // A shaped burst rather than a rectangular one: an abrupt edge would register
        // as a broadband click.
        final envelope = sin(pi * i / burst);
        samples[cursor] =
            amplitude *
            envelope *
            (sin(phase) + 0.35 * sin(2 * phase) + 0.15 * sin(3 * phase));
      }
      for (var i = 0; i < dip && cursor < total; i++, cursor++) {
        samples[cursor] = 0.012 * (_random.nextDouble() * 2 - 1);
      }
    }

    return samples;
  }
}

/// Returns silence, for testing the too-quiet path and the quality gate.
class SilentAudioCapture implements AudioCaptureService {
  SilentAudioCapture({this.seconds = 20});

  final int seconds;
  bool _recording = false;

  @override
  bool get isRecording => _recording;

  @override
  Future<bool> ensurePermission() async => true;

  @override
  Future<void> start() async => _recording = true;

  @override
  Future<Float64List> stopAndTake() async {
    _recording = false;
    return Float64List(seconds * kSampleRate);
  }

  @override
  Future<void> discard() async => _recording = false;
}

/// Refuses permission, for testing the denied path.
class DeniedAudioCapture implements AudioCaptureService {
  @override
  bool get isRecording => false;

  @override
  Future<bool> ensurePermission() async => false;

  @override
  Future<void> start() async =>
      throw const AudioCaptureException(AudioCaptureFailure.permissionDenied);

  @override
  Future<Float64List> stopAndTake() async => Float64List(0);

  @override
  Future<void> discard() async {}
}
