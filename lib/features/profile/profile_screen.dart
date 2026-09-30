/// Settings.
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

/// Language, hand, reminders, and the way through to privacy.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = AppText.of(context);
    final profile = ref.watch(profileProvider).value;

    if (profile == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final repository = ref.read(repositoryProvider);

    Future<void> save(UserProfile updated) async {
      await repository.saveProfile(updated);
      await _applyReminder(ref, updated);
    }

    return Scaffold(
      appBar: AppBar(title: Text(text.profileTitle)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(kPagePadding),
          children: [
            SectionCard(
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 26,
                    backgroundColor: context.colors.primaryContainer,
                    child: Text(
                      profile.greetingName.characters.first.toUpperCase(),
                      style: context.texts.titleLarge?.copyWith(
                        color: context.colors.onPrimaryContainer,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          profile.displayName ?? profile.greetingName,
                          style: context.texts.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (profile.email != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            profile.email!,
                            style: context.texts.bodySmall?.copyWith(
                              color: context.colors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            SectionCard(
              title: text.settingsLanguage,
              child: ChoiceQuestion<String>(
                question: '',
                selected: profile.languageCode,
                onSelected: (code) =>
                    save(profile.copyWith(languageCode: code)),
                options: [
                  (value: 'en', label: text.languageEnglish),
                  (value: 'ta', label: text.languageTamil),
                ],
              ),
            ),
            const SizedBox(height: 14),

            SectionCard(
              title: text.settingsHandTitle,
              subtitle: text.settingsHandBody,
              child: ChoiceQuestion<DominantHand>(
                question: '',
                selected: profile.dominantHand,
                onSelected: (hand) =>
                    save(profile.copyWith(dominantHand: hand)),
                options: [
                  (value: DominantHand.right, label: text.handRight),
                  (value: DominantHand.left, label: text.handLeft),
                ],
              ),
            ),
            const SizedBox(height: 14),

            SectionCard(
              title: text.profileReminders,
              subtitle: text.profileRemindersBody,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SwitchListTile(
                    value: profile.reminderEnabled,
                    onChanged: (enabled) =>
                        save(profile.copyWith(reminderEnabled: enabled)),
                    title: Text(
                      profile.reminderEnabled
                          ? text.profileReminderEvery(
                              profile.reminderIntervalDays,
                            )
                          : text.profileRemindersOff,
                    ),
                    contentPadding: EdgeInsets.zero,
                  ),
                  if (profile.reminderEnabled) ...[
                    const SizedBox(height: 10),
                    ChoiceQuestion<int>(
                      question: '',
                      selected: profile.reminderIntervalDays,
                      onSelected: (days) =>
                          save(profile.copyWith(reminderIntervalDays: days)),
                      options: [
                        for (final days in [1, 2, 3, 7])
                          (value: days, label: text.profileReminderEvery(days)),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 14),

            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.lock_outline),
                    title: Text(text.privacyTitle),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push(Routes.privacy),
                  ),
                  const Divider(),
                  ListTile(
                    leading: const Icon(Icons.info_outline),
                    title: Text(text.aboutTitle),
                    subtitle: Text(text.aboutVersion('1.0.0')),
                    onTap: () => _showAbout(context),
                  ),
                  const Divider(),
                  ListTile(
                    leading: Icon(Icons.logout, color: context.colors.error),
                    title: Text(
                      text.signOut,
                      style: TextStyle(color: context.colors.error),
                    ),
                    onTap: () => ref.read(authServiceProvider).signOut(),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            const NotADiagnosisNote(),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  /// Brings the scheduled reminder into line with the saved settings.
  ///
  /// Done here rather than in the repository: the reminder text has to be localised, and
  /// the repository has no business knowing about the widget tree.
  Future<void> _applyReminder(WidgetRef ref, UserProfile profile) async {
    final scheduler = ref.read(notificationServiceProvider);
    if (!profile.reminderEnabled) {
      await scheduler.cancelReminder();
      return;
    }

    final text = AppText.of(ref.context);
    final granted = await scheduler.requestPermission();
    if (!granted) return;

    await scheduler.scheduleReminder(
      intervalDays: profile.reminderIntervalDays,
      title: text.reminderTitle,
      body: text.reminderBody,
    );
  }

  void _showAbout(BuildContext context) {
    final text = AppText.of(context);
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(text.aboutTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(text.aboutVersion('1.0.0')),
            const SizedBox(height: 14),
            Text(text.aboutBody, style: const TextStyle(height: 1.4)),
            const SizedBox(height: 14),
            Text(text.notADiagnosisLong, style: const TextStyle(height: 1.4)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(text.close),
          ),
        ],
      ),
    );
  }
}
