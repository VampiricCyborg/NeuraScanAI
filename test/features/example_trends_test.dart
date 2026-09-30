/// The simulated trends and the baseline card.
///
/// The thing to protect above all is that simulated data can never be mistaken for the user's
/// own, so most of these are about the labelling.
library;

import 'package:flutter/material.dart' hide Baseline;
import 'package:flutter_test/flutter_test.dart';
import 'package:neurascan_ai/app/l10n/generated/app_localizations.dart';
import 'package:neurascan_ai/app/theme.dart';
import 'package:neurascan_ai/engine/baseline.dart';
import 'package:neurascan_ai/engine/constants.dart';
import 'package:neurascan_ai/engine/features.dart';
import 'package:neurascan_ai/features/trends/baseline_format.dart';
import 'package:neurascan_ai/features/trends/example_trends.dart';

import '../engine/engine_test_support.dart';

void main() {
  late Baseline baseline;

  setUp(() => baseline = Baseline.fit(variedBaselineSessions()));

  Future<void> pump(WidgetTester tester, {Locale? locale}) async {
    tester.view
      ..physicalSize = const Size(420, 5200)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.light),
        locale: locale,
        localizationsDelegates: AppText.localizationsDelegates,
        supportedLocales: AppText.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ExampleTrendsSection(baseline: baseline),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('nothing simulated can pass for real data', () {
    testWidgets('every simulated chart is labelled as an example', (
      tester,
    ) async {
      await pump(tester);
      // One badge under the heading and one on each of the two charts.
      expect(find.text('Example, not your data'), findsNWidgets(3));
    });

    testWidgets('the intro says the charts are simulated', (tester) async {
      await pump(tester);
      expect(
        find.textContaining('simulated from your own baseline'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Nothing on them is a result'),
        findsOneWidget,
      );
    });

    testWidgets('the charts carry an example label for screen readers', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pump(tester);
      expect(
        find.bySemanticsLabel(
          RegExp('Example, not your data: A steady pattern'),
        ),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(
          RegExp('Example, not your data: A gradual change'),
        ),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('it never claims to be a result or a diagnosis', (
      tester,
    ) async {
      await pump(tester);
      expect(find.textContaining('diagnos'), findsNothing);
      expect(find.textContaining('Your result'), findsNothing);
    });
  });

  group('the two example charts', () {
    testWidgets('a steady pattern and a gradual change', (tester) async {
      await pump(tester);
      expect(find.text('A steady pattern'), findsOneWidget);
      expect(find.text('A gradual change'), findsOneWidget);
    });

    testWidgets('the change caption says when it would be reported', (
      tester,
    ) async {
      await pump(tester);
      // The persistence wording also appears in the how-it-works steps, so anchor on the
      // part only the caption has.
      expect(
        find.textContaining(
          'for $kDefaultPersistence tests in a row, so a notable change is reported at test',
        ),
        findsOneWidget,
      );
    });

    testWidgets('the steady caption says nothing is reported', (tester) async {
      await pump(tester);
      expect(find.textContaining('so nothing is reported'), findsOneWidget);
    });

    testWidgets('there is a legend for all three lines', (tester) async {
      await pump(tester);
      expect(find.text('Your smoothed score'), findsOneWidget);
      expect(find.text('Notable-change line'), findsOneWidget);
      expect(find.text('Your baseline'), findsWidgets);
    });

    testWidgets('both draw a chart', (tester) async {
      await pump(tester);
      expect(find.byType(SimulatedTrendChart), findsNWidgets(2));
    });
  });

  group('your baseline', () {
    testWidgets('lists all nine measurements', (tester) async {
      await pump(tester);
      for (final label in [
        'Words remembered',
        'Reaction speed',
        'Reaction steadiness',
        'Speaking pace',
        'Time spent pausing',
        'Tracing accuracy',
        'Hand steadiness',
        'Typing pace',
        'Typing rhythm',
      ]) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
    });

    testWidgets('shows the actual frozen baseline value for each', (
      tester,
    ) async {
      await pump(tester);
      for (final spec in kFeatureSpecs) {
        final shown = formatFeatureValue(spec.key, baseline.median[spec.key]!);
        expect(find.text(shown), findsWidgets, reason: spec.key);
      }
    });

    testWidgets('and how much each usually varies', (tester) async {
      await pump(tester);
      expect(find.textContaining('usually within'), findsNWidgets(9));
    });

    testWidgets('different users see different baselines', (tester) async {
      baseline = Baseline.fit([
        for (var i = 0; i < kBaselineSessions; i++)
          makeSession(
            sessionId: '$i',
            overrides: {'reaction_median': 512.0 + i},
          ),
      ]);
      await pump(tester);
      expect(find.text('513 ms'), findsOneWidget);
    });
  });

  group('how the numbers are worked out', () {
    testWidgets('five steps, numbered', (tester) async {
      await pump(tester);
      expect(find.text('How the numbers are worked out'), findsOneWidget);
      for (var i = 1; i <= 5; i++) {
        expect(find.text('$i'), findsWidgets, reason: 'step $i');
      }
    });

    testWidgets('and says only changes for the worse count', (tester) async {
      await pump(tester);
      expect(
        find.textContaining('Only changes for the worse count'),
        findsOneWidget,
      );
    });

    testWidgets('and states the persistence rule with its real number', (
      tester,
    ) async {
      await pump(tester);
      expect(
        find.textContaining('for $kDefaultPersistence tests in a row'),
        findsWidgets,
      );
    });
  });

  group('in Tamil', () {
    testWidgets('the example label and intro are translated', (tester) async {
      await pump(tester, locale: const Locale('ta'));
      expect(find.text('எடுத்துக்காட்டு, உங்கள் தரவு அல்ல'), findsNWidgets(3));
      expect(find.text('Example, not your data'), findsNothing);
    });
  });

  group('value formatting', () {
    test('recall and pauses read as percentages', () {
      expect(formatFeatureValue('delayed_recall', 0.75), '75%');
      expect(formatFeatureValue('pause_ratio', 0.22), '22%');
    });

    test('times read in milliseconds', () {
      expect(formatFeatureValue('reaction_median', 312.4), '312 ms');
      expect(formatFeatureValue('inter_key_interval', 260.0), '260 ms');
    });

    test('speech reads as a rate', () {
      expect(formatFeatureValue('speaking_rate', 140.2), '140/min');
    });

    test('tracing error reads in dp to one place', () {
      expect(formatFeatureValue('spiral_rmse', 6.04), '6.0 dp');
    });

    test('ratios read to two places', () {
      expect(formatFeatureValue('reaction_cv', 0.153), '0.15');
      expect(formatFeatureValue('tremor_index', 0.104), '0.10');
    });

    test('a spread is a value with a plus-or-minus', () {
      expect(formatFeatureSpread('reaction_median', 18.0), '±18 ms');
    });

    test('an unknown feature still formats rather than failing', () {
      expect(formatFeatureValue('something_new', 1.234), '1.23');
    });
  });
}
