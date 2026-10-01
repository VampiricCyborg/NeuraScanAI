/// What the user sees immediately after a test.
///
/// Different screens in one, depending on what happened: a baseline test, a scored full test
/// with its comparison against the baseline and the previous test, or a test the check-in set
/// aside. Each says plainly which case this is, because a user who is not told why a test did
/// not count will assume the app is broken.
///
/// The recall words are shown here and only here. They are the one part of a test a user can
/// check for themselves, and seeing "you remembered nineteen of twenty-four, these were the
/// ones you missed" is far more meaningful than a fraction.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/l10n/generated/app_localizations.dart';
import '../../app/providers.dart';
import '../../app/router.dart';
import '../../app/theme.dart';
import '../../app/widgets.dart';
import '../../data/models.dart';
import '../../engine/screening_engine.dart';
import '../report/screens/results_views.dart';

/// The result of the session just completed.
class SummaryScreen extends ConsumerWidget {
  const SummaryScreen({this.sessionId, super.key});

  /// Which session to show. Falls back to the most recent one.
  final String? sessionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = AppText.of(context);
    final sessions = ref.watch(sessionsProvider).value ?? const [];

    final session = sessionId == null
        ? (sessions.isEmpty ? null : sessions.last)
        : sessions.where((s) => s.id == sessionId).firstOrNull;

    if (session == null) {
      return Scaffold(
        appBar: AppBar(title: Text(text.summaryTitle)),
        body: EmptyState(
          icon: Icons.history,
          message: text.dashboardNoSessionsYet,
          action: FilledButton(
            onPressed: () => context.go(Routes.home),
            child: Text(text.summaryBackToHome),
          ),
        ),
      );
    }

    // A full test that counted gets the whole result: its status, what it is made of and a
    // card for each of its eight steps. The first one has only an early status, and says so.
    final scored = session.countsTowardsTrend;

    return Scaffold(
      appBar: AppBar(
        title: Text(text.summaryTitle),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(kPagePadding),
          children: [
            if (scored)
              LatestTestView(sessionId: session.id, shrinkWrap: true)
            else
              _OutcomeCard(session: session),
            const SizedBox(height: 14),

            if (session.recallDetail != null) ...[
              _RecallCard(detail: session.recallDetail!),
              const SizedBox(height: 14),
            ],

            if (!session.valid && session.invalidReasons.isNotEmpty) ...[
              SectionCard(
                title: text.sessionInvalidReasons,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final reason in session.invalidReasons)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('•  '),
                            Expanded(child: Text(reason)),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
            ],

            if (!scored) ...[
              const NotADiagnosisNote(),
              const SizedBox(height: 20),
            ],

            if (scored)
              OutlinedButton.icon(
                onPressed: () => context.push(Routes.report),
                icon: const Icon(Icons.description_outlined),
                label: Text(text.summaryViewReport),
              ),
            const SizedBox(height: 10),
            PrimaryButton(
              label: text.summaryBackToHome,
              onPressed: () => context.go(Routes.home),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}

/// The headline outcome.
class _OutcomeCard extends ConsumerWidget {
  const _OutcomeCard({required this.session});

  final SessionRecord session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = AppText.of(context);

    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          StatusBadge(status: session.status),
          const SizedBox(height: 16),
          Text(
            _body(text, ref),
            style: context.texts.bodyMedium?.copyWith(height: 1.5),
          ),
          if (session.status == ScreeningStatus.buildingBaseline) ...[
            const SizedBox(height: 18),
            _baselineProgress(ref),
          ],
        ],
      ),
    );
  }

  Widget _baselineProgress(WidgetRef ref) {
    final progress = ref.watch(baselineTestProgressProvider);
    final hasPractice =
        (ref.watch(profileProvider).value?.baselineEpoch ?? 0) == 0;
    return BaselineProgress(
      done: progress.done,
      total: progress.total,
      hasPractice: hasPractice,
    );
  }

  String _body(AppText text, WidgetRef ref) => switch (session.status) {
    ScreeningStatus.stable => text.statusStableBody,
    ScreeningStatus.mildDeviation => text.statusMildBody,
    ScreeningStatus.notableDeviation => text.statusNotableBody,
    ScreeningStatus.buildingBaseline => text.dashboardBaselineExplainer,
    ScreeningStatus.excludedContext => text.statusExcludedBody(
      session.checkIn.confoundingReasons.join(', '),
    ),
    ScreeningStatus.invalidSession => text.sessionInvalidBody,
  };
}

/// Which words were remembered.
class _RecallCard extends StatelessWidget {
  const _RecallCard({required this.detail});

  final RecallDetail detail;

  @override
  Widget build(BuildContext context) {
    final text = AppText.of(context);
    final total = detail.recalled.length + detail.missed.length;

    return SectionCard(
      title: text.summaryRecallResult(detail.recalled.length, total),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (detail.recalled.isNotEmpty) ...[
            _WordGroup(
              label: text.summaryWordsRemembered,
              words: detail.recalled,
              color: context.colors.primary,
            ),
            const SizedBox(height: 14),
          ],
          if (detail.missed.isNotEmpty)
            _WordGroup(
              label: text.summaryWordsMissed,
              words: detail.missed,
              color: context.colors.outline,
            ),
        ],
      ),
    );
  }
}

class _WordGroup extends StatelessWidget {
  const _WordGroup({
    required this.label,
    required this.words,
    required this.color,
  });

  final String label;
  final List<String> words;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: context.texts.labelLarge?.copyWith(
            color: context.colors.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final word in words)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: color.withValues(alpha: 0.3)),
                ),
                child: Text(word, style: context.texts.bodyMedium),
              ),
          ],
        ),
      ],
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
