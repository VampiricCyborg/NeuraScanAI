/// The results screens as a person meets them: a card for each test, in each state it can be in,
/// the trend panels with too little data, and everything at the largest text size.
///
/// The cards and charts are pumped on their own from a real engine's history. The three views
/// are pumped against the app's real providers and an in-memory database, so what they show is
/// what the app would show.
library;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neurascan_ai/app/l10n/generated/app_localizations.dart';
import 'package:neurascan_ai/app/theme.dart';
import 'package:neurascan_ai/data/models.dart';
import 'package:neurascan_ai/engine/features.dart';
import 'package:neurascan_ai/features/report/calculators/analysis.dart';
import 'package:neurascan_ai/features/report/calculators/trend_stats.dart';
import 'package:neurascan_ai/features/report/models.dart';
import 'package:neurascan_ai/features/report/reference_ranges.dart';
import 'package:neurascan_ai/features/report/screens/results_views.dart';
import 'package:neurascan_ai/features/report/widgets/charts.dart';
import 'package:neurascan_ai/features/report/widgets/status_card.dart';
import 'package:neurascan_ai/features/report/widgets/test_card.dart';

import '../../app/seed_history.dart';
import '../../app/test_harness.dart';
import 'report_fixtures.dart';

/// [child] in a themed, localised app at [textScale], on a phone-sized surface.
Widget host(
  Widget child, {
  double textScale = 1.0,
  Brightness brightness = Brightness.light,
  Locale locale = const Locale('en'),
  bool scrolls = true,
}) => MaterialApp(
  theme: buildTheme(brightness),
  locale: locale,
  localizationsDelegates: AppText.localizationsDelegates,
  supportedLocales: AppText.supportedLocales,
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context)
        .copyWith(textScaler: TextScaler.linear(textScale)),
    child: child!,
  ),
  home: Scaffold(
    body: scrolls
        ? SingleChildScrollView(padding: const EdgeInsets.all(16), child: child)
        : child,
  ),
);

void phone(WidgetTester tester) {
  tester.view
    ..physicalSize = const Size(360, 2400)
    ..devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

/// The eight cards of [session] in [f]'s history.
List<TestSummary> summariesOf(
  Fixture f,
  SessionRecord session, {
  ReferenceRanges ranges = ReferenceRanges.none,
}) => summariseTests(
  series: buildAllSeries(
    sessions: f.sessions,
    baseline: f.baseline,
    ranges: ranges,
  ),
  session: session,
);

TestSummary cardFor(List<TestSummary> all, TestId id) =>
    all.firstWhere((s) => s.id == id);

Future<void> openCard(WidgetTester tester, String title) async {
  await tester.tap(find.text(title));
  await tester.pumpAndSettle();
}

void main() {
  group('a test card', () {
    final f = buildFixture(fullTests: 8, setAside: {3});

    testWidgets(
      'a valid test shows its values with units and its comparisons',
      (tester) async {
        phone(tester);
        final summary = cardFor(
          summariesOf(f, f.fullTests.last),
          TestId.reaction,
        );
        await tester.pumpWidget(host(TestCard(summary: summary)));
        await openCard(tester, 'Reaction time');

        // Counted, and the value is in milliseconds.
        expect(find.text('Counted'), findsOneWidget);
        expect(find.textContaining(' ms'), findsWidgets);
        // The personal baseline is the first comparison, with a z-score.
        expect(find.text('Against your baseline'), findsWidgets);
        expect(find.textContaining('z-score'), findsWidgets);
        // Then the earlier tests, then the population range.
        expect(find.text('Against your earlier tests'), findsWidgets);
        expect(find.textContaining('Best so far'), findsWidgets);
        expect(find.text('Population range (context only)'), findsWidgets);
        // A plain-language sentence for each measurement.
        expect(find.textContaining('your baseline'), findsWidgets);
      },
    );

    testWidgets(
      'the population range is "not yet validated", with no verdict',
      (tester) async {
        phone(tester);
        final summary = cardFor(
          summariesOf(f, f.fullTests.last),
          TestId.reaction,
        );
        await tester.pumpWidget(host(TestCard(summary: summary)));
        await openCard(tester, 'Reaction time');

        expect(find.text('Reference range not yet validated'), findsWidgets);
        for (final verdict in ['normal', 'abnormal', 'healthy', 'unhealthy']) {
          expect(find.textContaining(verdict), findsNothing, reason: verdict);
        }
      },
    );

    testWidgets('a half-filled range is still not shown as a number', (
      tester,
    ) async {
      phone(tester);
      // Numbers but no source, and marked a placeholder: it must not pass for evidence.
      final ranges = ReferenceRanges.parse(
        '{"ranges":[{"metric":"reaction_median","age_band":"all","low":200,'
        '"high":400,"unit":"ms","source_citation":null,'
        '"evidence_level":"placeholder"}]}',
      );
      final summary = cardFor(
        summariesOf(f, f.fullTests.last, ranges: ranges),
        TestId.reaction,
      );
      await tester.pumpWidget(host(TestCard(summary: summary)));
      await openCard(tester, 'Reaction time');

      expect(find.text('Reference range not yet validated'), findsWidgets);
      expect(find.textContaining('200 ms to 400 ms'), findsNothing);
    });

    testWidgets(
      'a cited, published range is shown as a range, still no verdict',
      (tester) async {
        phone(tester);
        final ranges = ReferenceRanges.parse(
          '{"ranges":[{"metric":"reaction_median","age_band":"all","low":200,'
          '"high":400,"unit":"ms","source_citation":"A test citation",'
          '"evidence_level":"published"}]}',
        );
        final summary = cardFor(
          summariesOf(f, f.fullTests.last, ranges: ranges),
          TestId.reaction,
        );
        await tester.pumpWidget(host(TestCard(summary: summary)));
        await openCard(tester, 'Reaction time');

        expect(find.textContaining('200 ms to 400 ms'), findsOneWidget);
        expect(find.textContaining('A test citation'), findsOneWidget);
        expect(find.textContaining('normal'), findsNothing);
      },
    );

    testWidgets(
      'a test the check-in set aside is marked not counted, with the reason',
      (tester) async {
        phone(tester);
        final summary = cardFor(
          summariesOf(f, f.fullTests[3]),
          TestId.reaction,
        );
        await tester.pumpWidget(host(TestCard(summary: summary)));

        expect(find.text('Not counted'), findsOneWidget);
        await openCard(tester, 'Reaction time');
        // Why, in the user's terms.
        expect(find.textContaining('Poor sleep'), findsWidgets);
        // Its raw value is shown, but there is no comparison.
        expect(find.textContaining(' ms'), findsWidgets);
        expect(find.text('Against your baseline'), findsNothing);
      },
    );

    testWidgets(
      'a measurement still calibrating is a raw value, marked calibrating',
      (tester) async {
        phone(tester);
        final first = buildFixture(fullTests: 1);
        final summary = cardFor(
          summariesOf(first, first.fullTests.single),
          TestId.reaction,
        );
        await tester.pumpWidget(host(TestCard(summary: summary)));
        await openCard(tester, 'Reaction time');

        expect(find.text('Calibrating'), findsWidgets);
        expect(find.textContaining('z-score'), findsNothing);
      },
    );

    testWidgets('a test nobody took is marked not measured', (tester) async {
      phone(tester);
      final quiet = buildFixture(
        fullTests: 6,
        omit: {'inter_key_interval', 'inter_key_cv'},
      );
      final summary = cardFor(
        summariesOf(quiet, quiet.fullTests.last),
        TestId.typing,
      );
      await tester.pumpWidget(host(TestCard(summary: summary)));

      expect(find.text('Not measured'), findsWidgets);
      await openCard(tester, 'Typing rhythm');
      expect(
        find.text('Too little typing to time the rhythm.'),
        findsOneWidget,
      );
    });

    testWidgets('names the areas a test feeds, in words as well as colour', (
      tester,
    ) async {
      phone(tester);
      final summary = cardFor(summariesOf(f, f.fullTests.last), TestId.tapping);
      await tester.pumpWidget(host(TestCard(summary: summary)));

      expect(find.text('Movement'), findsOneWidget);
    });
  });

  group('large text and themes', () {
    final f = buildFixture(fullTests: 8, setAside: {3});

    testWidgets('a card and its charts fit at 200% text in English', (
      tester,
    ) async {
      phone(tester);
      final all = summariesOf(f, f.fullTests.last);
      await tester.pumpWidget(
        host(
          Column(
            children: [
              for (final s in all)
                TestCard(summary: s, initiallyExpanded: true),
            ],
          ),
          textScale: 2.0,
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('and in Tamil', (tester) async {
      phone(tester);
      final all = summariesOf(f, f.fullTests.last);
      await tester.pumpWidget(
        host(
          Column(
            children: [
              for (final s in all)
                TestCard(summary: s, initiallyExpanded: true),
            ],
          ),
          textScale: 2.0,
          locale: const Locale('ta'),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      // Tamil, not the English fallback.
      expect(find.text('Reaction time'), findsNothing);
    });

    testWidgets('the status card fits at 200% text', (tester) async {
      phone(tester);
      await tester.pumpWidget(
        host(
          SessionStatusCard(
            session: f.fullTests.last,
            topFeatures: topContributors(
              session: f.fullTests.last,
              baseline: f.baseline,
            ),
            calibratingCount: 3,
            early: true,
          ),
          textScale: 2.0,
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('a metric chart fits at 200% text, in light and dark', (
      tester,
    ) async {
      phone(tester);
      final series = buildMetricSeries(
        spec: kSpecByKey['reaction_median']!,
        sessions: f.sessions,
        baseline: f.baseline,
      );
      for (final brightness in Brightness.values) {
        await tester.pumpWidget(
          host(
            MetricChart(
              series: series,
              range: TrendRange.all,
              now: DateTime(2027),
            ),
            textScale: 2.0,
            brightness: brightness,
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: brightness.name);
      }
    });
  });

  group('the charts', () {
    final f = buildFixture(setAside: {3});
    final now = DateTime(2027);

    MetricSeries seriesOf(String key) => buildMetricSeries(
      spec: kSpecByKey[key]!,
      sessions: f.sessions,
      baseline: f.baseline,
    );

    testWidgets('a test set aside is a hollow marker, not joined to the line', (
      tester,
    ) async {
      phone(tester);
      await tester.pumpWidget(
        host(
          MetricChart(
            series: seriesOf('reaction_median'),
            range: TrendRange.all,
            now: now,
          ),
        ),
      );

      final chart = tester.widget<LineChart>(find.byType(LineChart));
      final bars = chart.data.lineBarsData;
      final counted = bars.firstWhere(
        (b) => b.barWidth > 0 && b.spots.length > 1,
      );
      final hollow = bars
          .where((b) => b.barWidth == 0 && b.spots.isNotEmpty)
          .toList();

      // One set-aside test, one hollow marker; nine counted ones on the line.
      expect(counted.spots.length, 9);
      expect(hollow, hasLength(1));
      expect(hollow.single.spots, hasLength(1));
      final painter = hollow.single.dotData.getDotPainter(
        hollow.single.spots.single,
        0,
        hollow.single,
        0,
      ) as FlDotCirclePainter;
      // Hollow: no fill, an outline.
      expect(painter.color, Colors.transparent);
      expect(painter.strokeWidth, greaterThan(0));
      // The counted ones are filled.
      final filled = counted.dotData.getDotPainter(
        counted.spots.first,
        0,
        counted,
        0,
      ) as FlDotCirclePainter;
      expect(filled.color, isNot(Colors.transparent));
    });

    testWidgets('has a spoken description for a screen reader', (tester) async {
      phone(tester);
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        host(
          MetricChart(
            series: seriesOf('reaction_median'),
            range: TrendRange.all,
            now: now,
          ),
        ),
      );

      expect(
        find.bySemanticsLabel(RegExp(r'Reaction.*trend', caseSensitive: false)),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('says there is not enough data, in words, with few tests', (
      tester,
    ) async {
      phone(tester);
      final handle = tester.ensureSemantics();
      final few = buildFixture(fullTests: 3);
      final series = buildMetricSeries(
        spec: kSpecByKey['reaction_median']!,
        sessions: few.sessions,
        baseline: few.baseline,
      );
      await tester.pumpWidget(
        host(MetricChart(series: series, range: TrendRange.all, now: now)),
      );

      expect(
        find.bySemanticsLabel(RegExp(r'not enough data', caseSensitive: false)),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('the range selector offers 7 tests, 30 days, 90 days and all', (
      tester,
    ) async {
      phone(tester);
      var chosen = TrendRange.all;
      await tester.pumpWidget(
        host(
          StatefulBuilder(
            builder: (context, setState) => RangeSelector(
              value: chosen,
              onChanged: (r) => setState(() => chosen = r),
            ),
          ),
        ),
      );

      for (final label in ['Last 7 tests', '30 days', '90 days', 'All']) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      await tester.tap(find.text('30 days'));
      await tester.pump();
      expect(chosen, TrendRange.days30);
    });

    testWidgets('the share bars and index chart draw with a legend', (
      tester,
    ) async {
      phone(tester);
      final points = buildIndexSeries(f.sessions);
      await tester.pumpWidget(
        host(
          Column(
            children: [
              IndexChart(points: points, range: TrendRange.all, now: now),
              ShareBars(points: points, range: TrendRange.all, now: now),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Mild level'), findsWidgets);
      expect(find.text('Notable level'), findsWidgets);
    });
  });

  group('the trend statistics panel', () {
    testWidgets(
      'says "Not enough data yet (n of 6)" and no direction before six tests',
      (tester) async {
        phone(tester);
        await tester.pumpWidget(
          host(
            TrendStatsPanel(
              stats: computeTrendStats(oriented: [0.1, 0.2, 0.3, 0.4]),
            ),
          ),
        );

        expect(find.text('Not enough data yet (4 of 6)'), findsOneWidget);
        expect(find.textContaining('Improving'), findsNothing);
        expect(find.textContaining('Declining'), findsNothing);
      },
    );

    testWidgets('gives a direction from six valid tests', (tester) async {
      phone(tester);
      await tester.pumpWidget(
        host(
          TrendStatsPanel(
            stats: computeTrendStats(oriented: [0.0, 0.3, 0.6, 0.9, 1.2, 1.5]),
          ),
        ),
      );

      expect(find.textContaining('Not enough data'), findsNothing);
      expect(find.textContaining('Declining'), findsOneWidget);
    });
  });

  group('the three views', () {
    Future<TestApp> signedIn(WidgetTester tester) async {
      final app = await pumpApp(tester, signedIn: consentPendingAccount);
      await completeOnboarding(app);
      await tester.pumpAndSettle();
      return app;
    }

    Future<void> show(WidgetTester tester, TestApp app, Widget view) async {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: app.container,
          child: host(view, scrolls: false),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('the latest test is empty before any full test', (
      tester,
    ) async {
      final app = await signedIn(tester);
      await show(tester, app, const LatestTestView());

      expect(find.text('Word memory'), findsNothing);
    });

    testWidgets(
      'the latest test shows the status and a card for all eight tests',
      (tester) async {
        final app = await signedIn(tester);
        await seed(app, history(actual: 3));
        await show(tester, app, const LatestTestView());

        expect(find.text('Within your usual range'), findsOneWidget);
        // The eight cards, scrolled to as they are built lazily.
        for (final title in [
          'Word memory',
          'Reaction time',
          'Speech description',
          'Spiral tracing',
          'Typing rhythm',
          'Trail-making',
          'Finger tapping',
          'Verbal fluency',
        ]) {
          await tester.scrollUntilVisible(find.text(title), 300);
          expect(find.text(title), findsOneWidget, reason: title);
        }
      },
    );

    testWidgets('the trends say how far from six tests the data is', (
      tester,
    ) async {
      final app = await signedIn(tester);
      await seed(app, history(actual: 3));
      await show(tester, app, const TrendsView());

      expect(find.textContaining('Not enough data yet (3 of 6)'), findsWidgets);
    });

    testWidgets('the trends are empty before a full test', (tester) async {
      final app = await signedIn(tester);
      await show(tester, app, const TrendsView());

      expect(
        find.text('Nothing to chart yet. Take a full test first.'),
        findsOneWidget,
      );
    });

    testWidgets('the log lists a test that was set aside, marked not counted', (
      tester,
    ) async {
      final app = await signedIn(tester);
      await seed(app, history(actual: 4, setAside: {1}));
      await show(tester, app, const LogView());

      expect(find.text('Not counted'), findsWidgets);
      expect(find.textContaining('Poor sleep'), findsWidgets);
    });

    testWidgets('and the practice test, with its reason', (tester) async {
      final app = await signedIn(tester);
      await seed(app, history(actual: 2));
      await show(tester, app, const LogView());

      await tester.scrollUntilVisible(
        find.textContaining('Practice only'),
        300,
      );
      expect(find.textContaining('Practice only'), findsOneWidget);
    });
  });
}
