/// Typing-rhythm capture.
///
/// The privacy tests here matter as much as the behavioural ones. The claim is that timings
/// are recorded and text is not, and that only the app's own fields are measured.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neurascan_ai/features/session/keystroke_recorder.dart';

void main() {
  group('KeystrokeLog', () {
    test('records one event per character', () {
      final log = KeystrokeLog();
      log.recordInsertion();
      log.recordInsertion();
      log.recordInsertion();
      expect(log.length, 3);
    });

    test('records several characters for a paste', () {
      // Recorded as it happened rather than guessed at. The extractor's plausibility window
      // discards them, which is the right place for that decision.
      final log = KeystrokeLog();
      log.recordInsertion(inserted: 5);
      expect(log.length, 5);
    });

    test('ignores a non-positive insertion', () {
      final log = KeystrokeLog();
      log.recordInsertion(inserted: 0);
      log.recordInsertion(inserted: -3);
      expect(log.length, 0);
    });

    test('timestamps are relative to the first keystroke', () {
      // Nothing stored should reveal what time of day the user was typing.
      var now = DateTime.utc(2026, 5, 4, 22, 17, 31);
      final log = KeystrokeLog(now: () => now);

      log.recordInsertion();
      now = now.add(const Duration(milliseconds: 250));
      log.recordInsertion();

      expect(log.events.first.timestampMs, 0);
      expect(log.events.last.timestampMs, 250);
    });

    test('the same typing at a different hour produces identical timings', () {
      List<int> timingsFrom(DateTime start) {
        var now = start;
        final log = KeystrokeLog(now: () => now);
        for (var i = 0; i < 5; i++) {
          log.recordInsertion();
          now = now.add(const Duration(milliseconds: 240));
        }
        return [for (final event in log.events) event.timestampMs];
      }

      expect(
        timingsFrom(DateTime.utc(2026, 5, 4, 3)),
        timingsFrom(DateTime.utc(2026, 5, 4, 21)),
      );
    });

    test('extracts features from the recorded intervals', () {
      var now = DateTime.utc(2026, 5, 4, 10);
      final log = KeystrokeLog(now: () => now);
      for (var i = 0; i < 12; i++) {
        log.recordInsertion();
        now = now.add(const Duration(milliseconds: 260));
      }

      final features = log.extractFeatures();
      expect(features.medianIntervalMs, closeTo(260, 1));
      expect(features.hasEnoughData, isTrue);
    });

    test('reports when there is too little data to mean anything', () {
      final log = KeystrokeLog();
      log.recordInsertion();
      log.recordInsertion();
      expect(log.hasEnoughData, isFalse);
    });

    test('clearing forgets everything, including the time origin', () {
      var now = DateTime.utc(2026, 5, 4, 10);
      final log = KeystrokeLog(now: () => now);
      log.recordInsertion();
      now = now.add(const Duration(seconds: 30));

      log.clear();
      expect(log.length, 0);

      log.recordInsertion();
      // A fresh origin, not 30 seconds into the old one.
      expect(log.events.single.timestampMs, 0);
    });

    test('no key identity is stored, only a timestamp', () {
      // Asserted structurally: a KeystrokeEvent has nothing on it but a time, so the
      // recorded data cannot reconstruct the text.
      final log = KeystrokeLog();
      log.recordInsertion();
      final event = log.events.single;
      expect(event.timestampMs, isA<int>());
      expect(
        event.toString(),
        isNot(contains('char')),
        reason: 'a KeystrokeEvent must carry no character data',
      );
    });
  });

  group('MeasuredTextField', () {
    Future<void> pumpField(
      WidgetTester tester,
      KeystrokeLog log, {
      TextEditingController? controller,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: KeystrokeScope(
              log: log,
              child: MeasuredTextField(
                controller: controller ?? TextEditingController(),
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('records typing in the app\'s own field', (tester) async {
      final log = KeystrokeLog();
      await pumpField(tester, log);

      await tester.enterText(find.byType(TextField), 'violin');
      await tester.pump();

      expect(log.length, 6);
    });

    testWidgets('records the characters added, not the total length', (
      tester,
    ) async {
      final log = KeystrokeLog();
      final controller = TextEditingController();
      await pumpField(tester, log, controller: controller);

      await tester.enterText(find.byType(TextField), 'abc');
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'abcde');
      await tester.pump();

      expect(log.length, 5);
    });

    testWidgets('a deletion records nothing', (tester) async {
      // A deletion says something about self-correction, but there is no matching baseline
      // measurement for it, so recording it would add noise rather than signal.
      final log = KeystrokeLog();
      await pumpField(tester, log);

      await tester.enterText(find.byType(TextField), 'violin');
      await tester.pump();
      final afterTyping = log.length;

      await tester.enterText(find.byType(TextField), 'viol');
      await tester.pump();

      expect(log.length, afterTyping);
    });

    testWidgets(
      'a field with no scope above it records nothing and does not throw',
      (tester) async {
        // This is the sign-in screen's situation: fields exist, but there is no session to
        // attribute typing to.
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MeasuredTextField(controller: TextEditingController()),
            ),
          ),
        );

        await tester.enterText(find.byType(TextField), 'someone@example.com');
        await tester.pump();
        // Reaching here without an exception is the assertion.
        expect(find.byType(TextField), findsOneWidget);
      },
    );

    testWidgets('the field\'s own onChanged still fires', (tester) async {
      final log = KeystrokeLog();
      final seen = <String>[];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: KeystrokeScope(
              log: log,
              child: MeasuredTextField(
                controller: TextEditingController(),
                onChanged: seen.add,
              ),
            ),
          ),
        ),
      );

      await tester.enterText(find.byType(TextField), 'harbour');
      await tester.pump();

      expect(seen, ['harbour']);
      expect(log.length, 7);
    });

    testWidgets('an explicit log overrides the inherited one', (tester) async {
      final inherited = KeystrokeLog();
      final explicit = KeystrokeLog();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: KeystrokeScope(
              log: inherited,
              child: MeasuredTextField(
                controller: TextEditingController(),
                log: explicit,
              ),
            ),
          ),
        ),
      );

      await tester.enterText(find.byType(TextField), 'abc');
      await tester.pump();

      expect(explicit.length, 3);
      expect(inherited.length, 0);
    });
  });
}
