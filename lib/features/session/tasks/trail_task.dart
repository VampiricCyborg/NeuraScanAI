/// The trail-making step.
///
/// Two parts on the same canvas. Part A: tap five numbered circles in order. Part B: tap eight
/// circles that alternate numbers and letters -- 1, A, 2, B, 3, C, 4, D. Part A is the user's
/// own reference speed, so the extra time per circle in part B is the cost of switching rather
/// than of finding and tapping circles.
///
/// The circles are laid out at random each time, so the path cannot be learned. A wrong tap is
/// counted and shown briefly; it does not stop the clock, as in the paper test.
///
/// Timing comes from a stopwatch started when a part's circles appear. Every tap is kept with
/// its time and whether it was right, then reduced to three numbers when the step ends; the
/// taps themselves are not stored.
library;

import 'dart:async';
import 'dart:math';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';

import '../../../app/l10n/generated/app_localizations.dart';
import '../../../app/theme.dart';
import '../../../app/widgets.dart';
import '../../../engine/constants.dart';
import '../../../engine/extractors/trail_extractor.dart';

/// Radius of a circle, in logical pixels. 28 makes a 56 px target, comfortably above the
/// 48 px minimum.
const double kTrailCircleRadius = 28;

/// The labels of part A: the numbers in order.
List<String> trailLabelsA() => [
  for (var i = 1; i <= kTrailPartACircles; i++) '$i',
];

/// The labels of part B: numbers and letters alternating, 1, A, 2, B and so on.
List<String> trailLabelsB() {
  final labels = <String>[];
  for (var i = 0; labels.length < kTrailPartBCircles; i++) {
    labels.add('${i ~/ 2 + 1}');
    if (labels.length < kTrailPartBCircles) {
      labels.add(String.fromCharCode(65 + i ~/ 2));
    }
    i++;
  }
  return labels;
}

/// Runs both parts of the trail-making step.
class TrailTask extends StatefulWidget {
  const TrailTask({required this.onFinished, this.random, super.key});

  /// Receives what happened in each part.
  final void Function({
    required TrailPartLog partA,
    required TrailPartLog partB,
  })
  onFinished;

  /// Injected in tests so the layout is deterministic.
  final Random? random;

  @override
  State<TrailTask> createState() => _TrailTaskState();
}

enum _Stage { introA, playingA, introB, playingB }

class _TrailTaskState extends State<TrailTask> {
  late final Random _random = widget.random ?? Random();
  final _stopwatch = clock.stopwatch();

  _Stage _stage = _Stage.introA;
  Size _canvasSize = Size.zero;

  List<String> _labels = const [];
  List<Offset> _positions = const [];
  int _next = 0;
  final _taps = <TrailTapEvent>[];
  TrailPartLog? _partA;

  /// The circle to show as wrongly tapped, briefly.
  int? _wrongIndex;
  Timer? _wrongTimer;

  @override
  void dispose() {
    _wrongTimer?.cancel();
    super.dispose();
  }

  bool get _playing => _stage == _Stage.playingA || _stage == _Stage.playingB;

  /// Positions for [count] circles that do not overlap and stay inside the canvas.
  List<Offset> _layout(int count) {
    const margin = kTrailCircleRadius + 8;
    const minGap = kTrailCircleRadius * 2 + 22;
    final width = max(_canvasSize.width - margin * 2, 1.0);
    final height = max(_canvasSize.height - margin * 2, 1.0);

    final placed = <Offset>[];
    var attempts = 0;
    while (placed.length < count && attempts < 4000) {
      attempts++;
      final candidate = Offset(
        margin + _random.nextDouble() * width,
        margin + _random.nextDouble() * height,
      );
      if (placed.every((other) => (other - candidate).distance >= minGap)) {
        placed.add(candidate);
      }
    }
    // A canvas too small for a random fit (a tiny window) falls back to an even row, so the
    // step can always be completed.
    if (placed.length < count) {
      placed
        ..clear()
        ..addAll([
          for (var i = 0; i < count; i++)
            Offset(margin + (width * (i + 0.5)) / count, margin + height / 2),
        ]);
    }
    return placed;
  }

  void _startPart(List<String> labels, _Stage playing) {
    setState(() {
      _labels = labels;
      _positions = _layout(labels.length);
      _next = 0;
      _taps.clear();
      _wrongIndex = null;
      _stage = playing;
    });
    _stopwatch
      ..reset()
      ..start();
  }

  void _tap(int index) {
    if (!_playing) return;
    final elapsed = _stopwatch.elapsedMilliseconds;

    if (index != _next) {
      _taps.add(TrailTapEvent(timestampMs: elapsed, correct: false));
      _wrongTimer?.cancel();
      setState(() => _wrongIndex = index);
      _wrongTimer = Timer(const Duration(milliseconds: 500), () {
        if (mounted) setState(() => _wrongIndex = null);
      });
      return;
    }

    _taps.add(TrailTapEvent(timestampMs: elapsed, correct: true));
    setState(() => _next++);
    if (_next >= _labels.length) _finishPart();
  }

  void _finishPart() {
    _stopwatch.stop();
    final log = TrailPartLog(
      targets: _labels.length,
      taps: List.unmodifiable(_taps),
    );
    if (_stage == _Stage.playingA) {
      setState(() {
        _partA = log;
        _stage = _Stage.introB;
        _positions = const [];
      });
    } else {
      widget.onFinished(partA: _partA!, partB: log);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = AppText.of(context);
    final inB = _stage == _Stage.introB || _stage == _Stage.playingB;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          text.taskTrailTitle,
          style: context.texts.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          inB ? text.taskTrailPartB : text.taskTrailPartA,
          style: context.texts.bodyMedium?.copyWith(
            color: context.colors.onSurfaceVariant,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 8),
        // Fixed height whether or not there is a message, so the canvas does not resize while
        // the user is tapping and move the circles under their finger.
        SizedBox(
          height: 22,
          child: _wrongIndex == null
              ? Text(
                  inB ? text.taskTrailPartLabelB : text.taskTrailPartLabelA,
                  style: context.texts.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: context.colors.primary,
                  ),
                )
              : Text(
                  text.taskTrailMistake,
                  style: context.texts.titleSmall?.copyWith(
                    color: context.colors.error,
                  ),
                ),
        ),
        const SizedBox(height: 8),

        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              _canvasSize = Size(constraints.maxWidth, constraints.maxHeight);
              return Container(
                decoration: BoxDecoration(
                  color: context.colors.surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(kCornerRadius),
                  border: Border.all(color: context.colors.outlineVariant),
                ),
                child: Stack(
                  children: [
                    if (_playing)
                      for (var i = 0; i < _positions.length; i++)
                        Positioned(
                          left: _positions[i].dx - kTrailCircleRadius,
                          top: _positions[i].dy - kTrailCircleRadius,
                          child: _Circle(
                            key: ValueKey('trail-circle-${_labels[i]}'),
                            label: _labels[i],
                            done: i < _next,
                            wrong: i == _wrongIndex,
                            onTap: () => _tap(i),
                          ),
                        ),
                  ],
                ),
              );
            },
          ),
        ),

        const SizedBox(height: 16),
        if (_stage == _Stage.introA)
          PrimaryButton(
            label: text.start,
            icon: Icons.play_arrow_rounded,
            onPressed: () => _startPart(trailLabelsA(), _Stage.playingA),
          )
        else if (_stage == _Stage.introB)
          PrimaryButton(
            label: text.taskTrailNextPart,
            icon: Icons.play_arrow_rounded,
            onPressed: () => _startPart(trailLabelsB(), _Stage.playingB),
          )
        else
          // Keeps the layout the same height while playing.
          const SizedBox(height: 52),
      ],
    );
  }
}

/// One numbered or lettered circle.
///
/// Reports the tap on press rather than on release, so a finger that lands and lifts quickly is
/// not timed late.
class _Circle extends StatelessWidget {
  const _Circle({
    required this.label,
    required this.done,
    required this.wrong,
    required this.onTap,
    super.key,
  });

  final String label;
  final bool done;
  final bool wrong;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final background = wrong
        ? colors.errorContainer
        : done
        ? colors.primary
        : colors.surface;
    final foreground = wrong
        ? colors.onErrorContainer
        : done
        ? colors.onPrimary
        : colors.onSurface;

    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => onTap(),
        child: Container(
          width: kTrailCircleRadius * 2,
          height: kTrailCircleRadius * 2,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: background,
            border: Border.all(
              color: wrong ? colors.error : colors.primary,
              width: 2.5,
            ),
          ),
          child: ExcludeSemantics(
            child: Text(
              label,
              style: context.texts.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: foreground,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
