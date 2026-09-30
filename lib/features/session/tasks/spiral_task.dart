/// The spiral-tracing step.
///
/// The user follows a three-turn guide spiral outwards with one finger. Two measurements
/// come out of it: how far the trace strays from the guide, and how much of that straying
/// oscillates in the 4-12 Hz band where pathological tremor lives.
///
/// Every touch sample is kept with its timestamp, because the tremor measurement is a
/// frequency estimate and needs the timing, not just the path. The samples exist in memory
/// for the length of the task and are reduced to two numbers when it ends; the trace is
/// never stored.
library;

import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart';

import '../../../app/l10n/generated/app_localizations.dart';
import '../../../app/theme.dart';
import '../../../app/widgets.dart';
import '../../../engine/constants.dart';
import '../../../engine/extractors/spiral_extractor.dart';

/// Presents the guide spiral and records the trace.
class SpiralTask extends StatefulWidget {
  const SpiralTask({required this.onFinished, super.key});

  /// Receives the trace and the guide it was drawn against.
  final void Function({
    required List<TracePoint> trace,
    required GuideSpiral guide,
  })
  onFinished;

  @override
  State<SpiralTask> createState() => _SpiralTaskState();
}

class _SpiralTaskState extends State<SpiralTask> {
  final _trace = <TracePoint>[];
  final _stopwatch = Stopwatch();

  Size _canvasSize = Size.zero;
  double _coverage = 0;

  GuideSpiral _guideFor(Size size) => GuideSpiral(
    centre: (x: size.width / 2, y: size.height / 2),
    // Inset so the outermost turn is not against the edge of the canvas, where a
    // finger would run out of room and the trace would flatten for reasons that have
    // nothing to do with motor control.
    maxRadius: (size.shortestSide / 2) * 0.86,
  );

  void _addPoint(Offset local) {
    if (!_stopwatch.isRunning) _stopwatch.start();

    _trace.add(
      TracePoint(
        x: local.dx,
        y: local.dy,
        timestampMs: _stopwatch.elapsedMilliseconds,
      ),
    );

    // Coverage is recomputed as the user draws so the finish button can unlock at the
    // gate rather than letting them finish and then telling them it did not count.
    if (_trace.length % 8 == 0 && _canvasSize != Size.zero) {
      final result = extractSpiralFeatures(
        trace: _trace,
        guide: _guideFor(_canvasSize),
      );
      setState(() => _coverage = result.coverage);
    }
  }

  void _clear() {
    setState(() {
      _trace.clear();
      _coverage = 0;
      _stopwatch
        ..stop()
        ..reset();
    });
  }

  void _finish() {
    widget.onFinished(
      trace: List.unmodifiable(_trace),
      guide: _guideFor(_canvasSize),
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = AppText.of(context);
    final enoughTraced = _coverage >= kMinSpiralCoverage;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          text.taskSpiralTitle,
          style: context.texts.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          text.taskSpiralBody,
          style: context.texts.bodyMedium?.copyWith(
            color: context.colors.onSurfaceVariant,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 16),

        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final size = Size(constraints.maxWidth, constraints.maxHeight);
              _canvasSize = size;

              return GestureDetector(
                // Report the drag from where the finger landed. By default a drag only
                // starts once the finger has moved past the touch slop (about 18 px), so
                // the first recorded point was already well out from the centre and the
                // start of the spiral -- the tightest, most telling part -- was lost.
                dragStartBehavior: DragStartBehavior.down,
                // Both handlers record, so a tap-and-drag and a slow drag produce the
                // same series. onPanUpdate alone would miss the first sample.
                onPanStart: (details) => _addPoint(details.localPosition),
                onPanUpdate: (details) => _addPoint(details.localPosition),
                onPanEnd: (_) => setState(() {}),
                child: Container(
                  decoration: BoxDecoration(
                    color: context.colors.surfaceContainerLowest,
                    borderRadius: BorderRadius.circular(kCornerRadius),
                    border: Border.all(color: context.colors.outlineVariant),
                  ),
                  child: CustomPaint(
                    painter: _SpiralPainter(
                      guide: _guideFor(size),
                      trace: _trace,
                      guideColor: context.colors.outline,
                      traceColor: context.colors.primary,
                    ),
                    child: const SizedBox.expand(),
                  ),
                ),
              );
            },
          ),
        ),

        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    text.taskSpiralCoverage((_coverage * 100).round()),
                    style: context.texts.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: enoughTraced
                          ? context.colors.primary
                          : context.colors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      value: (_coverage / kMinSpiralCoverage).clamp(0.0, 1.0),
                      minHeight: 6,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 14),
            TextButton.icon(
              onPressed: _trace.isEmpty ? null : _clear,
              icon: const Icon(Icons.refresh, size: 18),
              label: Text(text.taskSpiralClear),
            ),
          ],
        ),

        const SizedBox(height: 8),
        // Always laid out, and only hidden. This line used to be added to the column once
        // drawing began, which shrank the canvas by about 40 px while the user's finger was
        // on it. The guide spiral is centred in the canvas, so it slid roughly 20 px under
        // the finger mid-stroke -- enough to make an accurate trace look inaccurate and to
        // corrupt the accuracy measurement itself.
        Opacity(
          opacity: !enoughTraced && _trace.isNotEmpty ? 1.0 : 0.0,
          child: Text(
            text.taskSpiralIncomplete,
            style: context.texts.bodySmall?.copyWith(
              color: context.colors.onSurfaceVariant,
            ),
          ),
        ),

        const SizedBox(height: 12),
        PrimaryButton(
          label: text.finish,
          icon: Icons.check,
          // Locked until the gate would pass, which is test case TC6.
          onPressed: enoughTraced ? _finish : null,
        ),
      ],
    );
  }
}

/// Draws the guide spiral and the user's trace over it.
class _SpiralPainter extends CustomPainter {
  const _SpiralPainter({
    required this.guide,
    required this.trace,
    required this.guideColor,
    required this.traceColor,
  });

  final GuideSpiral guide;
  final List<TracePoint> trace;
  final Color guideColor;
  final Color traceColor;

  @override
  void paint(Canvas canvas, Size size) {
    // The guide, dashed so that the user's own line stays distinguishable from it.
    final guidePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..color = guideColor.withValues(alpha: 0.5);

    const steps = 720;
    final totalAngle = guide.turns * 2 * 3.141592653589793;
    var drawing = true;
    var current = Path();

    for (var i = 0; i <= steps; i++) {
      final theta = totalAngle * i / steps;
      final point = guide.pointAt(theta);
      final offset = Offset(point.x, point.y);

      // Roughly twelve dashes per turn.
      final inDash = (i ~/ 10).isEven;
      if (inDash != drawing) {
        if (drawing) canvas.drawPath(current, guidePaint);
        current = Path()..moveTo(offset.dx, offset.dy);
        drawing = inDash;
      } else if (i == 0) {
        current.moveTo(offset.dx, offset.dy);
      } else if (drawing) {
        current.lineTo(offset.dx, offset.dy);
      }
    }
    if (drawing) canvas.drawPath(current, guidePaint);

    // The centre dot, so it is obvious where to start.
    canvas.drawCircle(
      Offset(guide.centre.x, guide.centre.y),
      5,
      Paint()..color = guideColor,
    );

    if (trace.length < 2) return;

    final tracePath = Path()..moveTo(trace.first.x, trace.first.y);
    for (final point in trace.skip(1)) {
      tracePath.lineTo(point.x, point.y);
    }
    canvas.drawPath(
      tracePath,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = traceColor,
    );
  }

  @override
  bool shouldRepaint(_SpiralPainter oldDelegate) =>
      oldDelegate.trace.length != trace.length ||
      oldDelegate.guideColor != guideColor ||
      oldDelegate.traceColor != traceColor;
}
