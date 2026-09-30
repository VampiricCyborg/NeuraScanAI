/// The spiral screen's behaviour under a finger.
///
/// The extractor is tested on synthetic traces in test/engine. These tests are about the
/// screen: what it records, and that it does not move underneath the user.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neurascan_ai/app/l10n/generated/app_localizations.dart';
import 'package:neurascan_ai/app/theme.dart';
import 'package:neurascan_ai/engine/extractors/spiral_extractor.dart';
import 'package:neurascan_ai/features/session/tasks/spiral_task.dart';

void main() {
  List<TracePoint>? finishedTrace;
  GuideSpiral? finishedGuide;

  Future<void> pump(WidgetTester tester) async {
    finishedTrace = null;
    finishedGuide = null;
    tester.view
      ..physicalSize = const Size(420, 1000)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.light),
        localizationsDelegates: AppText.localizationsDelegates,
        supportedLocales: AppText.supportedLocales,
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(20),
            child: SpiralTask(
              onFinished: ({required trace, required guide}) {
                finishedTrace = trace;
                finishedGuide = guide;
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder canvas() => find.descendant(
    of: find.byType(SpiralTask),
    matching: find.byType(GestureDetector),
  );

  /// Drags along the guide as the app draws it, for [fraction] of the way out.
  Future<void> dragAlongGuide(
    WidgetTester tester, {
    double fraction = 1.0,
  }) async {
    final box = tester.renderObject<RenderBox>(canvas().first);
    final origin = tester.getTopLeft(canvas().first);
    final centre = origin + Offset(box.size.width / 2, box.size.height / 2);
    final maxRadius = (box.size.shortestSide / 2) * 0.86;

    final gesture = await tester.startGesture(centre);
    const steps = 200;
    for (var i = 1; i <= (steps * fraction).round(); i++) {
      final theta = 3 * 2 * math.pi * i / steps;
      final radius = maxRadius * i / steps;
      await gesture.moveTo(
        centre + Offset(radius * math.cos(theta), radius * math.sin(theta)),
      );
      await tester.pump(const Duration(milliseconds: 10));
    }
    await gesture.up();
    await tester.pumpAndSettle();
  }

  testWidgets('the canvas does not change size once drawing starts', (
    tester,
  ) async {
    // A "please trace more" line used to be added below the canvas as soon as the first
    // point was drawn. That shrank the canvas by about 40 px with the finger on it, and since
    // the guide is centred in the canvas it slid roughly 20 px under the finger mid-stroke.
    await pump(tester);
    final before = tester.getSize(canvas().first);

    final gesture = await tester.startGesture(tester.getCenter(canvas().first));
    await gesture.moveBy(const Offset(20, 20));
    await tester.pump();
    final during = tester.getSize(canvas().first);
    await gesture.up();
    await tester.pumpAndSettle();
    final after = tester.getSize(canvas().first);

    expect(during, before);
    expect(after, before);
  });

  testWidgets('the guide stays centred while drawing', (tester) async {
    await pump(tester);
    final centreBefore = tester.getCenter(canvas().first);

    final gesture = await tester.startGesture(centreBefore);
    await gesture.moveBy(const Offset(40, 0));
    await tester.pump();
    final centreDuring = tester.getCenter(canvas().first);
    await gesture.up();

    expect(centreDuring, centreBefore);
  });

  testWidgets('an accurate trace reaches the gate', (tester) async {
    await pump(tester);
    await dragAlongGuide(tester);

    final finish = tester.widget<FilledButton>(
      find.ancestor(
        of: find.text('Finish'),
        matching: find.byType(FilledButton),
      ),
    );
    expect(finish.onPressed, isNotNull);
  });

  testWidgets('a partial trace does not', (tester) async {
    await pump(tester);
    await dragAlongGuide(tester, fraction: 0.35);

    final finish = tester.widget<FilledButton>(
      find.ancestor(
        of: find.text('Finish'),
        matching: find.byType(FilledButton),
      ),
    );
    expect(finish.onPressed, isNull);
  });

  testWidgets('a wide circle does not reach the gate', (tester) async {
    // The complaint that started this: tracing well off the line still reached 70 %.
    await pump(tester);
    final box = tester.renderObject<RenderBox>(canvas().first);
    final origin = tester.getTopLeft(canvas().first);
    final centre = origin + Offset(box.size.width / 2, box.size.height / 2);
    final radius = (box.size.shortestSide / 2) * 0.86 * 0.55;

    final gesture = await tester.startGesture(centre + Offset(radius, 0));
    for (var i = 1; i <= 240; i++) {
      final theta = 3 * 2 * math.pi * i / 240;
      await gesture.moveTo(
        centre + Offset(radius * math.cos(theta), radius * math.sin(theta)),
      );
      await tester.pump(const Duration(milliseconds: 10));
    }
    await gesture.up();
    await tester.pumpAndSettle();

    final finish = tester.widget<FilledButton>(
      find.ancestor(
        of: find.text('Finish'),
        matching: find.byType(FilledButton),
      ),
    );
    expect(finish.onPressed, isNull);
  });

  testWidgets('finishing hands over the trace and the guide it was drawn on', (
    tester,
  ) async {
    await pump(tester);
    await dragAlongGuide(tester);
    await tester.tap(find.text('Finish'));
    await tester.pumpAndSettle();

    expect(finishedTrace, isNotNull);
    expect(finishedTrace!.length, greaterThan(100));
    expect(finishedGuide, isNotNull);
    // The guide the screen reports is the one the trace can be scored against.
    final result = extractSpiralFeatures(
      trace: finishedTrace!,
      guide: finishedGuide!,
    );
    expect(result.coverage, greaterThan(kMinCoverageForTest));
  });

  testWidgets('starting again clears the trace and the progress', (
    tester,
  ) async {
    await pump(tester);
    await dragAlongGuide(tester, fraction: 0.5);
    expect(find.textContaining('% traced'), findsOneWidget);

    await tester.tap(find.text('Start again'));
    await tester.pumpAndSettle();

    expect(find.text('0% traced'), findsOneWidget);
  });
}

/// The engine's coverage gate, restated so the test fails if the two drift apart.
const double kMinCoverageForTest = 0.70;
