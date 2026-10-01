/// Results and trends.
///
/// Three tabs once there is a full test: the latest test with a card for each of its eight
/// steps, the charts over time, and the log of every test, counted or not. Before the first
/// full test there is nothing of the user's own to show, so the screen invites them to take one
/// and shows an example built from their real baseline.
///
/// The charts only claim a trend from six valid tests; the tests the check-in set aside stay in
/// the log and appear as hollow markers, never silently dropped.
library;

// Flutter has its own Baseline widget, which would clash with the engine's.
import 'package:flutter/material.dart' hide Baseline;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/l10n/generated/app_localizations.dart';
import '../../app/providers.dart';
import '../../app/router.dart';
import '../../app/theme.dart';
import '../../app/widgets.dart';
import '../report/screens/results_views.dart';
import 'example_trends.dart';

/// Latest test, trends and log.
class TrendsScreen extends ConsumerStatefulWidget {
  const TrendsScreen({super.key});

  @override
  ConsumerState<TrendsScreen> createState() => _TrendsScreenState();
}

class _TrendsScreenState extends ConsumerState<TrendsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this);

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = AppText.of(context);
    final verdictReady = ref.watch(verdictReadyProvider);
    final baseline = ref.watch(engineProvider).value?.baseline;

    // Before the first full test the user is invited to take one, and shown an example so the
    // screen is not empty.
    if (!verdictReady) {
      return Scaffold(
        appBar: AppBar(title: Text(text.trendsTitle)),
        body: baseline != null
            ? ListView(
                padding: const EdgeInsets.all(kPagePadding),
                children: [
                  SectionCard(
                    title: text.trendsFirstTestTitle,
                    leading: Icon(
                      Icons.play_circle_outline,
                      color: context.colors.primary,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          text.trendsFirstTestBody,
                          style: context.texts.bodyMedium?.copyWith(
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 16),
                        PrimaryButton(
                          label: text.dashboardStartFullTest,
                          icon: Icons.play_arrow_rounded,
                          onPressed: () => context.push(Routes.session),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 22),
                  // Simulated, and labelled so. The user has no results of their own yet, so
                  // this shows their real baseline and how the measurements behave against it.
                  ExampleTrendsSection(baseline: baseline),
                  const SizedBox(height: 20),
                ],
              )
            : EmptyState(icon: Icons.show_chart, message: text.trendsNoData),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(text.trendsTitle),
        actions: [
          IconButton(
            tooltip: text.reportTitle,
            icon: const Icon(Icons.picture_as_pdf_outlined),
            onPressed: () => context.push(Routes.report),
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          tabs: [
            Tab(text: text.resTabLatest),
            Tab(text: text.resTabTrends),
            Tab(text: text.resTabLog),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: const [LatestTestView(), TrendsView(), LogView()],
      ),
    );
  }
}
