/// The picture-description step.
///
/// Twenty seconds of free speech about a picture. The prompt is a scene rather than an
/// object because the two features -- articulation rate and how much of the time is spent
/// in pauses -- need connected speech to mean anything; naming a single object would
/// produce one word.
///
/// The screen says the recording is deleted, and it is: the buffer goes to the feature
/// extractor and out of scope, and nothing writes it to disk. Saying so on the screen
/// rather than only in the privacy settings is deliberate, because this is the moment a
/// user is most likely to hesitate.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../app/l10n/generated/app_localizations.dart';
import '../../../app/theme.dart';
import '../../../app/widgets.dart';
import '../../../engine/constants.dart';
import '../../../services/audio_capture.dart';

/// Records the user describing a scene.
class SpeechTask extends StatefulWidget {
  const SpeechTask({
    required this.capture,
    required this.onFinished,
    this.seconds = kSpeechSeconds,
    super.key,
  });

  final AudioCaptureService capture;

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
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _remaining = widget.seconds;
  }

  @override
  void dispose() {
    _ticker?.cancel();
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
    setState(() => _phase = _SpeechPhase.processing);
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
              const Expanded(child: _PicturePrompt()),
              const SizedBox(height: 20),
              if (_phase == _SpeechPhase.recording)
                _RecordingIndicator(
                  remaining: _remaining,
                  total: widget.seconds,
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

/// The scene the user describes.
///
/// Drawn rather than photographed, for two reasons. A photograph would have to be
/// licensed and shipped, and more importantly a drawing can be built from a fixed number
/// of nameable elements, so the amount there is to say is the same for every user and
/// does not change between sessions.
class _PicturePrompt extends StatelessWidget {
  const _PicturePrompt();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(kCornerRadius),
      ),
      child: CustomPaint(
        painter: _ScenePainter(
          sky: context.colors.primaryContainer,
          ground: context.colors.secondaryContainer,
          ink: context.colors.onSurfaceVariant,
          accent: context.colors.primary,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

/// A market scene: stall, awning, fruit, a figure, a dog, a tree, birds.
class _ScenePainter extends CustomPainter {
  const _ScenePainter({
    required this.sky,
    required this.ground,
    required this.ink,
    required this.accent,
  });

  final Color sky;
  final Color ground;
  final Color ink;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final fill = Paint()..style = PaintingStyle.fill;
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..color = ink;

    canvas.drawRect(Rect.fromLTWH(0, 0, w, h * 0.62), fill..color = sky);
    canvas.drawRect(
      Rect.fromLTWH(0, h * 0.62, w, h * 0.38),
      fill..color = ground,
    );

    // Sun.
    canvas.drawCircle(
      Offset(w * 0.82, h * 0.16),
      h * 0.06,
      fill..color = accent,
    );

    // Tree.
    canvas.drawRect(
      Rect.fromLTWH(w * 0.12, h * 0.40, w * 0.022, h * 0.24),
      fill..color = ink,
    );
    canvas.drawCircle(
      Offset(w * 0.131, h * 0.36),
      h * 0.12,
      fill..color = accent,
    );

    // Market stall with a striped awning.
    final stall = Rect.fromLTWH(w * 0.40, h * 0.44, w * 0.34, h * 0.20);
    canvas.drawRect(stall, fill..color = ink.withValues(alpha: 0.18));
    for (var i = 0; i < 5; i++) {
      canvas.drawRect(
        Rect.fromLTWH(
          stall.left + i * stall.width / 5,
          stall.top - h * 0.05,
          stall.width / 10,
          h * 0.05,
        ),
        fill..color = accent,
      );
    }
    canvas.drawLine(
      Offset(stall.left, stall.top),
      Offset(stall.right, stall.top),
      line,
    );

    // Fruit on the counter.
    for (var i = 0; i < 6; i++) {
      canvas.drawCircle(
        Offset(stall.left + w * 0.035 + i * w * 0.05, stall.top + h * 0.055),
        h * 0.022,
        fill..color = i.isEven ? accent : ink.withValues(alpha: 0.55),
      );
    }

    // A figure buying something.
    final personX = w * 0.26;
    final headY = h * 0.50;
    canvas.drawCircle(Offset(personX, headY), h * 0.035, fill..color = ink);
    canvas.drawLine(
      Offset(personX, headY + h * 0.04),
      Offset(personX, headY + h * 0.14),
      line,
    );
    canvas.drawLine(
      Offset(personX, headY + h * 0.06),
      Offset(personX + w * 0.05, headY + h * 0.09),
      line,
    );
    canvas.drawLine(
      Offset(personX, headY + h * 0.14),
      Offset(personX - w * 0.03, headY + h * 0.22),
      line,
    );
    canvas.drawLine(
      Offset(personX, headY + h * 0.14),
      Offset(personX + w * 0.03, headY + h * 0.22),
      line,
    );

    // A dog.
    canvas.drawOval(
      Rect.fromLTWH(w * 0.60, h * 0.78, w * 0.10, h * 0.055),
      fill..color = ink.withValues(alpha: 0.7),
    );
    canvas.drawCircle(
      Offset(w * 0.705, h * 0.785),
      h * 0.026,
      fill..color = ink.withValues(alpha: 0.7),
    );

    // Birds.
    for (final centre in [
      Offset(w * 0.34, h * 0.14),
      Offset(w * 0.46, h * 0.09),
      Offset(w * 0.58, h * 0.16),
    ]) {
      canvas.drawPath(
        Path()
          ..moveTo(centre.dx - w * 0.022, centre.dy)
          ..quadraticBezierTo(
            centre.dx,
            centre.dy - h * 0.022,
            centre.dx,
            centre.dy,
          )
          ..quadraticBezierTo(
            centre.dx,
            centre.dy - h * 0.022,
            centre.dx + w * 0.022,
            centre.dy,
          ),
        line,
      );
    }
  }

  @override
  bool shouldRepaint(_ScenePainter oldDelegate) =>
      oldDelegate.sky != sky ||
      oldDelegate.ground != ground ||
      oldDelegate.ink != ink ||
      oldDelegate.accent != accent;
}

/// Countdown and a level-style animation while recording.
class _RecordingIndicator extends StatelessWidget {
  const _RecordingIndicator({required this.remaining, required this.total});

  final int remaining;
  final int total;

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
        const SizedBox(height: 14),
        Text(
          '$remaining',
          style: context.texts.displaySmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: context.colors.primary,
          ),
        ),
        const SizedBox(height: 14),
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
