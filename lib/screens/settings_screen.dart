import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'settings/api_key_settings_section.dart';
import 'settings/auto_backup_settings_section.dart';
import 'settings/manual_backup_settings_section.dart';
import 'settings/notification_settings_section.dart';
import 'settings/privacy_settings_section.dart'
    show CrashReportingSettingsTile, DataPrivacyTile;
import 'settings/reset_data_section.dart';
import '../providers/quest_provider.dart';
import '../widgets/page_content_bounds.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({
    super.key,
    this.debugPickBackupSource,
    this.debugSaveBackupFile,
  });

  /// Test-only seam replacing the platform file-picker / web paste dialog
  /// that normally supplies the raw import content: `file_selector`'s
  /// platform channel isn't available under `flutter test`. Returns the raw
  /// backup text, `''` for an explicit-but-empty selection, or `null` if
  /// the (fake) picker was cancelled. Left `null` in production, so the
  /// real picker/dialog always runs.
  @visibleForTesting
  final Future<String?> Function(BuildContext context)? debugPickBackupSource;

  /// Test-only seam replacing the "write bytes to a chosen location" step
  /// of export, for the same platform-channel reason as
  /// [debugPickBackupSource]. Left `null` in production.
  @visibleForTesting
  final Future<void> Function(String fileName, String jsonStr)?
  debugSaveBackupFile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('설정')),
      body: PageContentBounds(
        maxWidth: PageContentBounds.wide,
        child: ListView(
          children: [
            const ApiKeySettingsSection(),
            const NotificationSettingsSection(),
            const CrashReportingSettingsTile(),
            ListTile(
              leading: const Icon(Icons.refresh),
              title: const Text('추천 퀘스트 새로고침'),
              subtitle: const Text('보통 24시간마다 자동 갱신돼요. 지금 바로 새로고침할 수 있어요.'),
              onTap: () async {
                await ref.read(questsProvider.notifier).refreshSuggestions();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('추천 퀘스트를 새로고침했어요.')),
                  );
                }
              },
            ),
            const AutoBackupSettingsSection(),
            ManualBackupSettingsSection(
              debugPickBackupSource: debugPickBackupSource,
              debugSaveBackupFile: debugSaveBackupFile,
            ),
            const DataPrivacyTile(),
            const Divider(),
            const ResetDataSection(),
          ],
        ),
      ),
    );
  }
}
