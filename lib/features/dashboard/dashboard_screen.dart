/// The home screen.
///
/// Answers two questions and nothing else: where do I stand, and what should I do
/// next. Everything else is a tap away, because a dashboard that shows every number
/// at once is a dashboard nobody reads.
///
/// While the baseline is still building, the standing result is replaced by progress
/// towards it. That is the honest thing to show -- there is no result yet -- and it is
/// also the retention problem the app has to solve, since a user who does not
/// understand why the first sessions say nothing will stop before the baseline is set.
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
import '../../engine/constants.dart';
import '../../engine/features.dart';
import '../../engine/screening_engine.dart';

/// Status, next action and a short history.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = AppText.of(context);
    final profile = ref.watch(profileProvider).value;
    final engine = ref.watch(engineProvider).value;
    final sessions = ref.watch(sessionsProvider).value ?? const [];
    final latest = ref.watch(latestScoredSessionProvider);
    final status = ref.watch(currentStatusProvider);

    if (profile == null || engine == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final baselineReady = engine.baselineReady;

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => ref.read(repositoryProvider).syncNow(),
          child: ListView(
            padding: const EdgeInsets.all(kPagePadding),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      text.dashboardGreeting(profile.greetingName),
                      style: context.texts.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                sessions.isEmpty
                    ? text.dashboardNoSessionsYet
                    : text.dashboardLastSession(
                        _relativeDay(text, sessions.last.completedAt),
                      ),
                style: context.texts.bodyMedium?.copyWith(
                  color: context.colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 22),

              if (baselineReady && latest == null)
                // The baseline has just been set and nothing has been compared with it yet.
                // Saying so is better than showing "building your baseline" for a baseline
                // that is finished.
                SectionCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.check_circle_outline,
                            color: context.colors.primary,
                          ),
                          const SizedBox(width: 10),
                          Flexible(
                            child: Text(
                              text.statusBaselineSet,
                              style: context.texts.titleMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        text.statusBaselineSetBody,
                        style: context.texts.bodyMedium?.copyWith(height: 1.5),
                      ),
                      const SizedBox(height: 14),
                      OutlinedButton.icon(
                        onPressed: () => context.go(Routes.trends),
                        icon: const Icon(Icons.show_chart),
                        label: Text(text.summaryViewTrends),
                      ),
                    ],
                  ),
                )
              else if (baselineReady)
                _StatusCard(status: status, session: latest)
              else
                SectionCard(
                  child: BaselineProgress(
                    collected:
                        kBaselineSessions -
                        ref.watch(baselineRemainingProvider),
                    required_: kBaselineSessions,
                  ),
                ),
              const SizedBox(height: 14),

              PrimaryButton(
                label: text.dashboardStartSession,
                icon: Icons.play_arrow_rounded,
                onPressed: () => context.push(Routes.session),
              ),
              const SizedBox(height: 22),

              if (baselineReady && latest?.domainScores != null) ...[
                SectionCard(
                  title: text.summaryWhatContributed,
                  child: ContributionBreakdown(
                    contributions:
                        latest!.contributions ??
                        {for (final domain in Domain.values) domain: 0.0},
                  ),
                ),
                const SizedBox(height: 14),
                OutlinedButton.icon(
                  onPressed: () => context.push(Routes.report),
                  icon: const Icon(Icons.description_outlined),
                  label: Text(text.summaryViewReport),
                ),
                const SizedBox(height: 22),
              ],

              const NotADiagnosisNote(),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  /// A short, human phrase for when a session happened.
  ///
  /// Relative rather than a date, because "two days ago" is what matters for a
  /// cadence of one session every two to three days.
  String _relativeDay(AppText text, DateTime when) {
    final now = DateTime.now();
    final days = DateTime(
      now.year,
      now.month,
      now.day,
    ).difference(DateTime(when.year, when.month, when.day)).inDays;

    if (days <= 0) {
      return now.difference(when).inMinutes < 60
          ? text.timeJustNow
          : text.timeToday;
    }
    if (days == 1) return text.timeYesterday;
    return text.timeDaysAgo(days);
  }
}

/// The standing result.
class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.status, required this.session});

  final ScreeningStatus status;
  final SessionRecord? session;

  @override
  Widget build(BuildContext context) {
    final text = AppText.of(context);

    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          StatusBadge(status: status),
          const SizedBox(height: 16),
          Text(
            _body(text, status, session),
            style: context.texts.bodyMedium?.copyWith(height: 1.5),
          ),
          if (status.warrantsConsultation) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: context.colors.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.medical_services_outlined,
                    size: 20,
                    color: context.colors.onPrimaryContainer,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      text.reportTalkToDoctorBody,
                      style: context.texts.bodySmall?.copyWith(
                        color: context.colors.onPrimaryContainer,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _body(AppText text, ScreeningStatus status, SessionRecord? session) =>
      switch (status) {
        ScreeningStatus.stable => text.statusStableBody,
        ScreeningStatus.mildDeviation => text.statusMildBody,
        ScreeningStatus.notableDeviation => text.statusNotableBody,
        ScreeningStatus.buildingBaseline => text.dashboardBaselineExplainer,
        ScreeningStatus.excludedContext => text.statusExcludedBody(
          session?.checkIn.confoundingReasons.join(', ') ?? '',
        ),
        ScreeningStatus.invalidSession => text.statusInvalidBody,
      };
}
