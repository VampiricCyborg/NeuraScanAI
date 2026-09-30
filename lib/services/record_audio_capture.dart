/// Real microphone capture for the speech task.
///
/// Audio is requested as raw 16 kHz mono PCM and read as a *stream*, not recorded to a
/// file. That is the whole privacy design of the speech task in one choice: the samples
/// exist only as a buffer in memory, they go to the feature extractor, and the buffer is
/// dropped. There is no recording on disk to delete, so there is nothing that could be left
/// behind if the app is killed mid-task.
///
/// 16 kHz mono is what the extractor is written for (see speech_extractor.dart), and it is
/// plenty for energy-envelope work; speech intelligibility lives below 8 kHz, which is the
/// Nyquist limit at this rate.
// The three processing flags in the RecordConfig below equal the plugin's defaults today.
// They are spelled out anyway, because "these are off" is a measurement requirement and a
// change of default in the plugin must not silently change what the app measures.
// ignore_for_file: avoid_redundant_argument_values
library;

import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:record/record.dart';

import '../engine/extractors/speech_extractor.dart';
import 'audio_capture.dart';

/// The most audio held in memory, in seconds.
///
/// The task asks for twenty seconds. The cap exists so that a stop that never arrives -- a
/// bug, or the app left open on the screen -- cannot grow the buffer without limit.
const int kMaxCaptureSeconds = 45;

/// Input level, in dBFS, at or below which the level meter reads empty.
const double _meterFloorDb = -60.0;

/// Input level, in dBFS, at or above which the level meter reads full.
const double _meterCeilingDb = -12.0;

/// Captures the microphone through the `record` plugin.
class RecordAudioCapture implements AudioCaptureService {
  RecordAudioCapture({AudioRecorder? recorder})
    : _recorder = recorder ?? AudioRecorder();

  final AudioRecorder _recorder;

  final _levels = StreamController<double>.broadcast();
  final _bytes = BytesBuilder(copy: false);

  StreamSubscription<Uint8List>? _subscription;

  /// A trailing odd byte from the previous chunk. PCM16 samples are two bytes, and the
  /// plugin delivers chunks of arbitrary length, so a sample can straddle two of them.
  int? _carry;

  bool _recording = false;

  @override
  bool get isRecording => _recording;

  @override
  Stream<double> get levels => _levels.stream;

  @override
  Future<bool> ensurePermission() async {
    try {
      // Asks the user if they have not yet been asked, and returns the current state
      // otherwise.
      return await _recorder.hasPermission();
    } on Object {
      return false;
    }
  }

  @override
  Future<void> start() async {
    if (_recording) {
      throw const AudioCaptureException(AudioCaptureFailure.alreadyRecording);
    }
    if (!await ensurePermission()) {
      throw const AudioCaptureException(AudioCaptureFailure.permissionDenied);
    }

    _bytes.clear();
    _carry = null;

    try {
      final stream = await _recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: kSampleRate,
          numChannels: 1,
          // Echo cancellation and noise suppression are switched off. They are meant
          // for calls, and here they would quietly change the very things being
          // measured: noise suppression treats soft speech and pauses as noise and
          // removes them, which would bias both features and differ from phone to phone.
          echoCancel: false,
          noiseSuppress: false,
          autoGain: false,
        ),
      );
      _recording = true;
      _subscription = stream.listen(_onChunk, onError: (Object _) {});
    } on Object {
      _recording = false;
      throw const AudioCaptureException(AudioCaptureFailure.unknown);
    }
  }

  void _onChunk(Uint8List chunk) {
    if (!_recording || chunk.isEmpty) return;

    // Reassemble whole samples, carrying an odd trailing byte into the next chunk.
    var data = chunk;
    if (_carry != null) {
      data = Uint8List(chunk.length + 1)
        ..[0] = _carry!
        ..setRange(1, chunk.length + 1, chunk);
      _carry = null;
    }
    if (data.length.isOdd) {
      _carry = data.last;
      data = Uint8List.sublistView(data, 0, data.length - 1);
    }
    if (data.isEmpty) return;

    if (_bytes.length + data.length <= kMaxCaptureSeconds * kSampleRate * 2) {
      _bytes.add(data);
    }
    _levels.add(_levelOf(data));
  }

  /// The chunk's loudness on a 0..1 scale for the meter.
  double _levelOf(Uint8List pcm) {
    final view = ByteData.sublistView(pcm);
    final count = pcm.length ~/ 2;
    var sumSquares = 0.0;
    for (var i = 0; i < count; i++) {
      final sample = view.getInt16(i * 2, Endian.little) / 32768.0;
      sumSquares += sample * sample;
    }
    final rms = math.sqrt(sumSquares / count);
    final db = 20.0 * math.log(math.max(rms, 1e-9)) / math.ln10;
    return ((db - _meterFloorDb) / (_meterCeilingDb - _meterFloorDb)).clamp(
      0.0,
      1.0,
    );
  }

  @override
  Future<Float64List> stopAndTake() async {
    if (!_recording) return Float64List(0);
    _recording = false;

    await _subscription?.cancel();
    _subscription = null;
    try {
      await _recorder.stop();
    } on Object {
      // Stopping a recorder that has already stopped throws on some platforms. The
      // samples already collected are what matter.
    }

    final pcm = _bytes.takeBytes();
    _carry = null;

    final view = ByteData.sublistView(pcm);
    final count = pcm.length ~/ 2;
    final samples = Float64List(count);
    for (var i = 0; i < count; i++) {
      samples[i] = view.getInt16(i * 2, Endian.little) / 32768.0;
    }
    return samples;
  }

  @override
  Future<void> discard() async {
    if (!_recording) {
      _bytes.clear();
      return;
    }
    _recording = false;
    await _subscription?.cancel();
    _subscription = null;
    try {
      await _recorder.stop();
    } on Object {
      // Already stopped.
    }
    _bytes.clear();
    _carry = null;
  }

  /// Releases the plugin. Call when the capture service itself is finished with.
  Future<void> dispose() async {
    await discard();
    await _levels.close();
    await _recorder.dispose();
  }
}
