/// Privacy, data export and erasure.
///
/// The screen is written to be read by someone deciding whether to trust the app, so it
/// states what stays on the phone and what does not in concrete terms rather than as a
/// policy. It also shows the backup queue honestly, including failures: a user who turned
/// backup on and whose uploads are silently failing would otherwise believe a backup exists
/// when it does not.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/l10n/generated/app_localizations.dart';
import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../app/widgets.dart';
import '../../data/local_db.dart';

/// What is stored, backup status, export and delete.
class PrivacyScreen extends ConsumerStatefulWidget {
  const PrivacyScreen({super.key});

  @override
  ConsumerState<PrivacyScreen> createState() => _PrivacyScreenState();
}

class _PrivacyScreenState extends ConsumerState<PrivacyScreen> {
  bool _busy = false;

  Future<void> _export() async {
    final userId = ref.read(currentUserIdProvider);
    if (userId == null) return;

    setState(() => _busy = true);
    try {
      final data = await ref.read(repositoryProvider).exportEverything(userId);
      final directory = await getTemporaryDirectory();
      final file = File(
        '${directory.path}/neurascan-export-'
        '${DateTime.now().toIso8601String().split('T').first}.json',
      );
      // Pretty-printed, because the point of an export is that the user can read it.
      await file.writeAsString(
        const JsonEncoder.withIndent('  ').convert(data),
      );

      if (!mounted) return;
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          text: AppText.of(context).privacyExport,
        ),
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppText.of(context).privacyExportDone)),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmAndDelete() async {
    final text = AppText.of(context);
    final userId = ref.read(currentUserIdProvider);
    if (userId == null) return;

    final sessionCount = (ref.read(sessionsProvider).value ?? const []).length;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(text.privacyDeleteConfirmTitle),
        content: Text(text.privacyDeleteConfirmBody(sessionCount)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(text.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: context.colors.error,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(text.privacyDeleteConfirmAction),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _busy = true);
    try {
      final repository = ref.read(repositoryProvider);
      final remoteCleared = await repository.deleteEverything(userId);

      // The database key is destroyed too, not only the rows. Without it, any copy of the
      // file that survives in a device backup is unreadable.
      await destroyDatabaseKey();
      await ref.read(authServiceProvider).deleteAccount();

      if (mounted && !remoteCleared) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppText.of(context).privacyDeletedRemoteFailed),
            duration: const Duration(seconds: 8),
          ),
        );
      }
      // Signing out takes the router back to the login screen.
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = AppText.of(context);
    final profile = ref.watch(profileProvider).value;
    final queue = ref.watch(syncQueueProvider);

    return Scaffold(
      appBar: AppBar(title: Text(text.privacyTitle)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(kPagePadding),
          children: [
            SectionCard(
              title: text.privacyOnDeviceTitle,
              leading: Icon(Icons.phone_android, color: context.colors.primary),
              child: Text(
                text.privacyOnDeviceBody,
                style: context.texts.bodyMedium?.copyWith(height: 1.5),
              ),
            ),
            const SizedBox(height: 14),

            SectionCard(
              title: text.privacyStoredTitle,
              leading: Icon(Icons.lock_outline, color: context.colors.primary),
              child: Text(
                text.privacyStoredBody,
                style: context.texts.bodyMedium?.copyWith(height: 1.5),
              ),
            ),
            const SizedBox(height: 14),

            SectionCard(
              title: text.privacySyncTitle,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    profile?.syncEnabled ?? false
                        ? text.settingsSyncOn
                        : text.settingsSyncOff,
                    style: context.texts.bodyMedium,
                  ),
                  if (profile?.syncEnabled ?? false) ...[
                    const SizedBox(height: 12),
                    Text(
                      text.privacySyncPending(queue.pendingCount),
                      style: context.texts.bodySmall?.copyWith(
                        color: context.colors.onSurfaceVariant,
                      ),
                    ),
                    if (queue.abandonedCount > 0) ...[
                      const SizedBox(height: 6),
                      Text(
                        text.privacySyncFailed(queue.abandonedCount),
                        style: context.texts.bodySmall?.copyWith(
                          color: context.colors.error,
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                    OutlinedButton.icon(
                      onPressed: _busy
                          ? null
                          : () => ref.read(repositoryProvider).syncNow(),
                      icon: const Icon(Icons.cloud_upload_outlined),
                      label: Text(text.privacySyncNow),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 22),

            OutlinedButton.icon(
              onPressed: _busy ? null : _export,
              icon: const Icon(Icons.download_outlined),
              label: Text(text.privacyExport),
            ),
            const SizedBox(height: 22),

            SectionCard(
              title: text.privacyDeleteTitle,
              leading: Icon(Icons.delete_outline, color: context.colors.error),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    text.privacyDeleteBody,
                    style: context.texts.bodyMedium?.copyWith(height: 1.5),
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: context.colors.error,
                      side: BorderSide(color: context.colors.error),
                    ),
                    onPressed: _busy ? null : _confirmAndDelete,
                    icon: const Icon(Icons.delete_forever_outlined),
                    label: Text(text.privacyDeleteConfirmAction),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}
