/// Informed consent, and the settings that go with it.
///
/// This screen is a gate, not a formality: the router will not let a signed-in user
/// past it until the current consent version has been accepted. It is also where the
/// two choices that cannot sensibly be defaulted are made -- which hand, and whether
/// anything is backed up.
///
/// Sync defaults to off. That is the only defensible default for health-related data,
/// and it is also the honest one: the app is fully usable without it, so offering it
/// pre-enabled would be collecting data because we could rather than because the user
/// wanted it.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/l10n/generated/app_localizations.dart';
import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../app/widgets.dart';
import '../../data/models.dart';

/// Explains what the app does and does not do, then records consent.
class ConsentScreen extends ConsumerStatefulWidget {
  const ConsentScreen({super.key});

  @override
  ConsumerState<ConsentScreen> createState() => _ConsentScreenState();
}

class _ConsentScreenState extends ConsumerState<ConsentScreen> {
  bool _agreed = false;
  bool _syncEnabled = false;
  bool _busy = false;
  DominantHand _hand = DominantHand.right;
  String _language = 'en';
  bool _initialisedFromProfile = false;

  Future<void> _accept(UserProfile profile) async {
    setState(() => _busy = true);
    try {
      final repository = ref.read(repositoryProvider);
      await repository.saveProfile(
        profile.copyWith(dominantHand: _hand, languageCode: _language),
      );
      await repository.recordConsent(
        // Reloaded so the consent is recorded on top of the hand and language just
        // saved, rather than on the stale copy this screen was built with.
        profile: (await repository.loadProfile(profile.id))!,
        syncEnabled: _syncEnabled,
      );
      // No navigation here: the router redirects once the profile stream reports
      // that current consent exists.
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = AppText.of(context);
    final profile = ref.watch(profileProvider).value;

    if (profile == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // Seed the controls from whatever is stored, once, so that a user who reaches
    // this screen again after a consent-version bump keeps their earlier choices.
    if (!_initialisedFromProfile) {
      _initialisedFromProfile = true;
      _hand = profile.dominantHand;
      _language = profile.languageCode;
      _syncEnabled = profile.syncEnabled;
    }

    return Scaffold(
      appBar: AppBar(title: Text(text.consentTitle)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(kPagePadding),
          children: [
            SectionCard(
              title: text.consentWhatItDoes,
              leading: Icon(
                Icons.check_circle_outline,
                color: context.colors.primary,
              ),
              child: Text(
                text.consentWhatItDoesBody,
                style: context.texts.bodyMedium?.copyWith(height: 1.5),
              ),
            ),
            const SizedBox(height: 14),

            SectionCard(
              title: text.consentWhatItDoesNot,
              leading: Icon(Icons.block_outlined, color: context.colors.error),
              child: Text(
                text.consentWhatItDoesNotBody,
                style: context.texts.bodyMedium?.copyWith(height: 1.5),
              ),
            ),
            const SizedBox(height: 14),

            SectionCard(
              title: text.consentDataTitle,
              leading: Icon(Icons.lock_outline, color: context.colors.primary),
              child: Text(
                text.consentDataBody,
                style: context.texts.bodyMedium?.copyWith(height: 1.5),
              ),
            ),
            const SizedBox(height: 22),

            SectionCard(
              title: text.settingsHandTitle,
              subtitle: text.settingsHandBody,
              child: ChoiceQuestion<DominantHand>(
                question: '',
                selected: _hand,
                onSelected: (hand) => setState(() => _hand = hand),
                options: [
                  (value: DominantHand.right, label: text.handRight),
                  (value: DominantHand.left, label: text.handLeft),
                ],
              ),
            ),
            const SizedBox(height: 14),

            SectionCard(
              title: text.settingsLanguage,
              child: ChoiceQuestion<String>(
                question: '',
                selected: _language,
                onSelected: (code) => setState(() => _language = code),
                options: [
                  (value: 'en', label: text.languageEnglish),
                  (value: 'ta', label: text.languageTamil),
                ],
              ),
            ),
            const SizedBox(height: 14),

            SectionCard(
              title: text.settingsSyncTitle,
              subtitle: text.settingsSyncBody,
              child: RadioGroup<bool>(
                groupValue: _syncEnabled,
                onChanged: (value) =>
                    setState(() => _syncEnabled = value ?? false),
                child: Column(
                  children: [
                    RadioListTile<bool>(
                      value: false,
                      title: Text(text.settingsSyncOff),
                      contentPadding: EdgeInsets.zero,
                    ),
                    RadioListTile<bool>(
                      value: true,
                      title: Text(text.settingsSyncOn),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 22),

            const NotADiagnosisNote(long: true),
            const SizedBox(height: 18),

            CheckboxListTile(
              value: _agreed,
              onChanged: (value) => setState(() => _agreed = value ?? false),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
              title: Text(
                text.consentAgree,
                style: context.texts.bodyMedium?.copyWith(height: 1.4),
              ),
            ),
            const SizedBox(height: 14),

            PrimaryButton(
              label: text.continueAction,
              busy: _busy,
              // Disabled rather than hidden, and disabled until the box is ticked,
              // which is test case TC2. Consent that can be given by tapping past a
              // screen is not consent.
              onPressed: _agreed ? () => _accept(profile) : null,
            ),
            if (!_agreed) ...[
              const SizedBox(height: 10),
              Text(
                text.consentMustAgree,
                textAlign: TextAlign.center,
                style: context.texts.bodySmall?.copyWith(
                  color: context.colors.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}
