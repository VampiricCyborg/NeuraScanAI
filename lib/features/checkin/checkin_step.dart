/// The three-question context check-in.
///
/// This is the cheapest part of the design and the one that contributed most to the
/// evaluation results. Ordinary bad days are the dominant source of false alarms in
/// frequent self-screening, and no amount of signal processing can distinguish a tired day
/// from an early decline -- but the person can, if asked.
///
/// The screen therefore explains what an honest answer is for, because a user who thinks
/// admitting tiredness will be held against them has a reason to under-report, and the
/// whole mechanism depends on them not doing that.
library;

import 'package:flutter/material.dart';

import '../../app/l10n/generated/app_localizations.dart';
import '../../app/theme.dart';
import '../../app/widgets.dart';
import '../../data/models.dart';

/// Asks about sleep, tiredness and illness.
class CheckInStep extends StatefulWidget {
  const CheckInStep({required this.onSubmitted, super.key});

  final ValueChanged<CheckIn> onSubmitted;

  @override
  State<CheckInStep> createState() => _CheckInStepState();
}

class _CheckInStepState extends State<CheckInStep> {
  SleepQuality? _sleep;
  FatigueLevel? _fatigue;
  bool? _illness;

  bool get _complete => _sleep != null && _fatigue != null && _illness != null;

  /// What the answers so far would mean for this session.
  bool get _wouldBeExcluded =>
      (_sleep?.isConfounding ?? false) ||
      (_fatigue?.isConfounding ?? false) ||
      (_illness ?? false);

  @override
  Widget build(BuildContext context) {
    final text = AppText.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  text.checkInTitle,
                  style: context.texts.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  text.checkInBody,
                  style: context.texts.bodyMedium?.copyWith(
                    color: context.colors.onSurfaceVariant,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 24),

                SectionCard(
                  child: ChoiceQuestion<SleepQuality>(
                    question: text.checkInSleepQuestion,
                    selected: _sleep,
                    onSelected: (value) => setState(() => _sleep = value),
                    options: [
                      (value: SleepQuality.good, label: text.checkInSleepGood),
                      (value: SleepQuality.fair, label: text.checkInSleepFair),
                      (value: SleepQuality.poor, label: text.checkInSleepPoor),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                SectionCard(
                  child: ChoiceQuestion<FatigueLevel>(
                    question: text.checkInFatigueQuestion,
                    selected: _fatigue,
                    onSelected: (value) => setState(() => _fatigue = value),
                    options: [
                      (
                        value: FatigueLevel.none,
                        label: text.checkInFatigueNone,
                      ),
                      (
                        value: FatigueLevel.some,
                        label: text.checkInFatigueSome,
                      ),
                      (
                        value: FatigueLevel.very,
                        label: text.checkInFatigueVery,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                SectionCard(
                  child: ChoiceQuestion<bool>(
                    question: text.checkInIllnessQuestion,
                    selected: _illness,
                    onSelected: (value) => setState(() => _illness = value),
                    options: [
                      (value: false, label: text.checkInIllnessNo),
                      (value: true, label: text.checkInIllnessYes),
                    ],
                  ),
                ),

                if (_wouldBeExcluded) ...[
                  const SizedBox(height: 18),
                  // Shown before the session starts rather than after. Telling someone
                  // their four minutes will not count towards the trend is information
                  // they should have while they can still choose to come back later.
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: context.colors.secondaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.nights_stay_outlined,
                          size: 20,
                          color: context.colors.onSecondaryContainer,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            text.checkInWillBeExcluded,
                            style: context.texts.bodySmall?.copyWith(
                              color: context.colors.onSecondaryContainer,
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
          ),
        ),
        const SizedBox(height: 16),
        PrimaryButton(
          label: text.continueAction,
          onPressed: _complete
              ? () => widget.onSubmitted(
                  CheckIn(
                    sleep: _sleep!,
                    fatigue: _fatigue!,
                    illnessOrMedicationChange: _illness!,
                    answeredAt: DateTime.now(),
                  ),
                )
              : null,
        ),
      ],
    );
  }
}
