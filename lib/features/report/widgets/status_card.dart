/// The overall status of a full test, and what it is made of.
///
/// The status is the engine's own: the smoothed deviation, the persistence rule and the context
/// check-in. This card only shows it, with the exact breakdown by area, the (up to) three
/// measurements that moved the index most, and the context the user logged. "What may explain
/// this" lists things the user told the app -- poor sleep, tiredness, illness -- and never a
/// medical cause.
library;

import 'package:flutter/material.dart';

import '../../../app/l10n/generated/app_localizations.dart';
import '../../../app/theme.dart';
import '../../../app/widgets.dart';
import '../../../data/models.dart';
import '../../../engine/constants.dart';
import '../../../engine/screening_engine.dart';
import '../calculators/analysis.dart';
import 'report_text.dart';

/// Status, contributions, top measurements and logged context for one full test.
class SessionStatusCard extends StatelessWidget {
  const SessionStatusCard({
    required this.session,
    required this.topFeatures,
    this.calibratingCount = 0,
    this.early = false,
    super.key,
  });

  final SessionRecord session;

  /// The measurements that pushed the index up most, largest first.
  final List<TopContributor> topFeatures;

  /// How many measurements still have no baseline.
  final int calibratingCount;

  /// True for the first scored full test, whose status is an early one.
  final bool early;

  @override
  Widget build(BuildContext context) {
    final text = AppText.of(context);
    final notes = contextNotes(session.checkIn);
    final total = topFeatures.fold<double>(0, (a, b) => a + b.share);

    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          StatusBadge(status: session.status),
          const SizedBox(height: 14),
          Text(
            _body(text),
            style: context.texts.bodyMedium?.copyWith(height: 1.5),
          ),
          if (early) ...[
            const SizedBox(height: 10),
            Text(
              text.summaryEarlyNote,
              style: context.texts.bodySmall?.copyWith(
                color: context.colors.onSurfaceVariant,
                height: 1.4,
              ),
            ),
          ],
          if (calibratingCount > 0) ...[
            const SizedBox(height: 10),
            Text(
              text.resCalibratingNote(calibratingCount, kExtensionTests),
              style: context.texts.bodySmall?.copyWith(
                color: context.colors.onSurfaceVariant,
                height: 1.4,
              ),
            ),
          ],
          if (session.contributions != null && session.countsTowardsTrend) ...[
            const SizedBox(height: 20),
            Text(
              text.summaryWhatContributed,
              style: context.texts.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            ContributionBreakdown(contributions: session.contributions!),
            const SizedBox(height: 20),
            Text(
              text.resTopFeatures,
              style: context.texts.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            if (topFeatures.isEmpty)
              Text(text.resTopFeaturesNone, style: context.texts.bodyMedium)
            else
              for (var i = 0; i < topFeatures.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      Text(
                        '${i + 1}.  ',
                        style: context.texts.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Expanded(
                        child: Text(
                          featureLabel(text, topFeatures[i].key),
                          style: context.texts.bodyMedium,
                        ),
                      ),
                      Text(
                        '${(topFeatures[i].share / total * 100).round()}%',
                        style: context.texts.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
          ],
          const SizedBox(height: 20),
          Text(
            text.resMayExplain,
            style: context.texts.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            notes.isEmpty
                ? text.resMayExplainNone
                : text.resMayExplainBody(
                    notes.map((n) => contextNoteLabel(text, n)).join(', '),
                  ),
            style: context.texts.bodyMedium?.copyWith(height: 1.4),
          ),
        ],
      ),
    );
  }

  String _body(AppText text) => switch (session.status) {
    ScreeningStatus.stable => text.statusStableBody,
    ScreeningStatus.mildDeviation => text.statusMildBody,
    ScreeningStatus.notableDeviation => text.statusNotableBody,
    ScreeningStatus.buildingBaseline => text.dashboardBaselineExplainer,
    ScreeningStatus.excludedContext => text.statusExcludedBody(
      confoundingNotes(session.checkIn)
          .map((n) => contextNoteLabel(text, n))
          .join(', '),
    ),
    ScreeningStatus.invalidSession => text.statusInvalidBody,
  };
}
