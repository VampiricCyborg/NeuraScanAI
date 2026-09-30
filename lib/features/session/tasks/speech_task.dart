/// The picture-description step.
///
/// Twenty seconds of free speech about a picture. There are ten pictures (see scenes.dart),
/// rotated by session so the user is not describing the same one every time. The prompt is a
/// scene rather than an object because the two features -- articulation rate and how much of
/// the time is spent in pauses -- need connected speech to mean anything; naming a single
/// object would produce one word.
///
/// The screen says the recording is deleted, and it is: the buffer goes to the feature
/// extractor and out of scope, and nothing writes it to disk. Saying so on the screen rather
/// than only in the privacy settings is deliberate, because this is the moment a user is most
/// likely to hesitate.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../app/l10n/generated/app_localizations.dart';
import '../../../app/theme.dart';
import '../../../app/widgets.dart';
import '../../../engine/constants.dart';
import '../../../services/audio_capture.dart';
import 'scenes.dart';

/// Records the user describing a scene.
class SpeechTask extends StatefulWidget {
  const SpeechTask({
    required this.capture,
    required this.onFinished,
    this.sceneIndex = 0,
    this.seconds = kSpeechSeconds,
    super.key,
  });

  final AudioCaptureService capture;

  /// Which of the [kSceneCount] pictures to describe this session.
  final int sceneIndex;

  /// Receives the samples. The only reference to the recording.
  final ValueChanged<Float64List> onFinished;

  final int seconds;

  @override
  State<SpeechTask> createState() => _SpeechTaskState();
}

enum _SpeechPhase { ready, permissionDenied, recording, processing }

class _SpeechTaskState extends State<SpeechTask> {
  _SpeechPhase _phase = _SpeechPhase.ready;
  int _remaining = 0;
  double _level = 0;
  Timer? _ticker;
  StreamSubscription<double>? _levels;

  @override
  void initState() {
    super.initState();
    _remaining = widget.seconds;
  }

  @override
  void dispose() {
    _ticker?.cancel();
    unawaited(_levels?.cancel());
    // If the user leaves mid-recording, the buffer is abandoned rather than left for
    // whatever reads it next.
    unawaited(widget.capture.discard());
    super.dispose();
  }

  Future<void> _start() async {
    final granted = await widget.capture.ensurePermission();
    if (!mounted) return;
    if (!granted) {
      setState(() => _phase = _SpeechPhase.permissionDenied);
      return;
    }

    try {
      await widget.capture.start();
    } on AudioCaptureException {
      if (mounted) setState(() => _phase = _SpeechPhase.permissionDenied);
      return;
    }
    if (!mounted) return;

    setState(() {
      _phase = _SpeechPhase.recording;
      _remaining = widget.seconds;
      _level = 0;
    });

    _levels = widget.capture.levels.listen((level) {
      if (mounted) setState(() => _level = level);
    });

    _ticker = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() => _remaining--);
      if (_remaining <= 0) {
        timer.cancel();
        unawaited(_stop());
      }
    });
  }

  Future<void> _stop() async {
    // The screen moves on first, and the meter subscription is released without being
    // waited for. Awaiting its cancellation before updating the UI left the task stuck on
    // "Listening" under test, and there is nothing to wait for: the samples come from
    // stopAndTake, not from this subscription.
    _ticker?.cancel();
    unawaited(_levels?.cancel());
    _levels = null;
    if (mounted) setState(() => _phase = _SpeechPhase.processing);
    final samples = await widget.capture.stopAndTake();
    if (!mounted) return;
    widget.onFinished(samples);
  }

  @override
  Widget build(BuildContext context) {
    final text = AppText.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          text.taskSpeechTitle,
          style: context.texts.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          text.taskSpeechBody(widget.seconds),
          style: context.texts.bodyMedium?.copyWith(
            color: context.colors.onSurfaceVariant,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 20),

        Expanded(
          child: Column(
            children: [
              Expanded(child: SceneView(index: widget.sceneIndex)),
              const SizedBox(height: 20),
              if (_phase == _SpeechPhase.recording)
                _RecordingIndicator(
                  remaining: _remaining,
                  total: widget.seconds,
                  level: _level,
                )
              else if (_phase == _SpeechPhase.processing)
                const CircularProgressIndicator()
              else if (_phase == _SpeechPhase.permissionDenied)
                Text(
                  text.taskSpeechMicrophoneNeeded,
                  textAlign: TextAlign.center,
                  style: context.texts.bodyMedium?.copyWith(
                    color: context.colors.error,
                    height: 1.4,
                  ),
                ),
            ],
          ),
        ),

        const SizedBox(height: 16),
        Text(
          text.taskSpeechDeleted,
          textAlign: TextAlign.center,
          style: context.texts.bodySmall?.copyWith(
            color: context.colors.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        if (_phase == _SpeechPhase.ready)
          PrimaryButton(
            label: text.start,
            icon: Icons.mic_none,
            onPressed: _start,
          )
        else if (_phase == _SpeechPhase.permissionDenied)
          PrimaryButton(
            label: text.retry,
            icon: Icons.refresh,
            onPressed: _start,
          )
        else if (_phase == _SpeechPhase.recording)
          OutlinedButton.icon(
            onPressed: _stop,
            icon: const Icon(Icons.stop),
            label: Text(text.finish),
          )
        else
          const PrimaryButton(label: '', onPressed: null, busy: true),
      ],
    );
  }
}

/// Countdown, and a live input level so the user can see they are being heard.
///
/// The level bar matters more with a real microphone than it did with the simulator: a phone
/// whose microphone is blocked by a case or a finger records silence without any error, and
/// the user would only find out from a rejected session twenty seconds later.
class _RecordingIndicator extends StatelessWidget {
  const _RecordingIndicator({
    required this.remaining,
    required this.total,
    required this.level,
  });

  final int remaining;
  final int total;

  /// Current input level in 0..1.
  final double level;

  @override
  Widget build(BuildContext context) {
    final text = AppText.of(context);

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.mic, color: context.colors.error),
            const SizedBox(width: 8),
            Text(
              text.taskSpeechRecording,
              style: context.texts.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          '$remaining',
          style: context.texts.displaySmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: context.colors.primary,
          ),
        ),
        const SizedBox(height: 12),
        // Input level.
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: level.clamp(0.0, 1.0),
            minHeight: 8,
            color: context.colors.tertiary,
          ),
        ),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: total == 0 ? 0 : (total - remaining) / total,
          ),
        ),
      ],
    );
  }
}
