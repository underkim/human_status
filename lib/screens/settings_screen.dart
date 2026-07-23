import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/stat.dart';
import '../models/user_profile.dart';
import '../providers/asset_snapshot_provider.dart';
import '../providers/auto_backup_provider.dart';
import '../providers/backup_provider.dart';
import '../providers/finance_provider.dart';
import '../providers/financial_planning_provider.dart';
import '../providers/goal_provider.dart';
import '../providers/observability_provider.dart';
import '../providers/profile_provider.dart';
import '../providers/quest_provider.dart';
import '../services/auto_backup_controller.dart';
import '../services/backup_service.dart';
import '../services/storage_service.dart';
import '../theme/app_colors.dart';
import '../widgets/page_content_bounds.dart';

class SettingsScreen extends ConsumerStatefulWidget {
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
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _exportInProgress = false;
  bool _importInProgress = false;
  bool _notificationChangeInProgress = false;

  UserProfile _copyProfile(UserProfile source) => UserProfile(
    lastQuestRefresh: source.lastQuestRefresh,
    claudeApiKey: source.claudeApiKey,
    reminderMinutesSinceMidnight: source.reminderMinutesSinceMidnight,
    lastAdviceRefresh: source.lastAdviceRefresh,
    cachedAdvice: source.cachedAdvice
        .map((entry) => Map<String, dynamic>.from(entry))
        .toList(),
    weeklyReportReminderEnabled: source.weeklyReportReminderEnabled,
    onboardingCompleted: source.onboardingCompleted,
    preferredStatId: source.preferredStatId,
  );

  Future<({bool saved, bool restored})> _saveNotificationProfile({
    required WidgetRef ref,
    required UserProfile candidate,
    required Future<void> Function() compensate,
  }) async {
    final storage = ref.read(storageServiceProvider);
    // Captured before the first await: this screen can be popped (disposed)
    // while storage.saveProfile is in flight, and a disposed ConsumerState's
    // `ref` throws on any further read. The notifier itself is a plain
    // object independent of this widget's lifecycle, so calling .reload()
    // on the captured reference still safely refreshes the *global*
    // profileProvider state for every other still-mounted screen — skipping
    // the reload via a `mounted` check here would wrongly leave that global
    // state stale just because this particular screen closed first.
    final profileNotifier = ref.read(profileProvider.notifier);
    try {
      await storage.saveProfile(candidate);
    } catch (_) {
      var restored = false;
      try {
        await compensate();
        restored = true;
      } catch (_) {
        // A stronger warning below tells the user when even compensation
        // failed; the persistence error never escapes as an unhandled future.
      }
      return (saved: false, restored: restored);
    }
    profileNotifier.reload();
    return (saved: true, restored: true);
  }

  Future<void> _editApiKey(BuildContext context, WidgetRef ref) async {
    final storage = ref.read(storageServiceProvider);
    final controller = TextEditingController(text: storage.claudeApiKey ?? '');

    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Claude API 키'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('설정하면 추천 퀘스트가 Claude AI로 생성돼요. 비워두면 로컬 규칙 기반으로 동작합니다.'),
            if (kIsWeb) ...[
              const SizedBox(height: 8),
              Text(
                '웹에서는 브라우저에 저장된 API 키의 보호 수준이 낮아요. 신뢰할 수 있는 기기의 HTTPS 환경에서만 입력해주세요.',
                style: TextStyle(color: context.appColors.warning),
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              obscureText: true,
              decoration: const InputDecoration(hintText: 'sk-ant-...'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, ''),
            child: const Text('키 삭제'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('저장'),
          ),
        ],
      ),
    );
    if (result == null) return;

    try {
      if (result.isEmpty) {
        await storage.deleteClaudeApiKey();
      } else {
        await storage.saveClaudeApiKey(result);
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('API 키를 저장하지 못했어요. 잠시 후 다시 시도해주세요.')),
        );
      }
      return;
    }
    ref.read(profileProvider.notifier).reload();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.isEmpty ? 'API 키를 삭제했어요.' : 'API 키를 저장했어요.'),
        ),
      );
    }
  }

  Future<void> _editReminder(BuildContext context, WidgetRef ref) async {
    if (_notificationChangeInProgress) return;
    if (kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('알림은 이 플랫폼(웹)에서는 지원되지 않아요.')),
      );
      return;
    }

    setState(() => _notificationChangeInProgress = true);
    try {
      final originalProfile = _copyProfile(ref.read(profileProvider));
      final current = originalProfile.reminderMinutesSinceMidnight;

      final action = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('알림 시간'),
          content: Text(
            current != null
                ? '매일 ${(current ~/ 60).toString().padLeft(2, '0')}:${(current % 60).toString().padLeft(2, '0')}에 알림을 보내드려요. (기기 상태에 따라 몇 분 늦을 수 있어요)'
                : '진행중인 퀘스트를 알려주는 매일 알림을 설정할 수 있어요. (기기 상태에 따라 몇 분 늦을 수 있어요)',
          ),
          actions: [
            if (current != null)
              TextButton(
                onPressed: () => Navigator.pop(context, 'off'),
                child: const Text('끄기'),
              ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, 'set'),
              child: const Text('시간 설정'),
            ),
          ],
        ),
      );
      if (action == null) return;

      final notificationService = ref.read(notificationServiceProvider);
      final activeQuestCount = ref.read(activeQuestsProvider).length;

      if (action == 'off') {
        try {
          await notificationService.cancelReminder();
        } catch (_) {
          if (context.mounted) _showGenericNotificationError(context);
          return;
        }
        final candidate = _copyProfile(originalProfile)
          ..reminderMinutesSinceMidnight = null;
        final outcome = await _saveNotificationProfile(
          ref: ref,
          candidate: candidate,
          compensate: () async {
            await notificationService.scheduleDailyReminder(
              hour: current! ~/ 60,
              minute: current % 60,
              activeQuestCount: activeQuestCount,
            );
          },
        );
        if (!outcome.saved && context.mounted) {
          _showGenericNotificationError(context, restored: outcome.restored);
        }
        return;
      }

      if (!context.mounted) return;
      final initial = current != null
          ? TimeOfDay(hour: current ~/ 60, minute: current % 60)
          : TimeOfDay.now();
      final picked = await showTimePicker(
        context: context,
        initialTime: initial,
      );
      if (picked == null) return;

      final bool granted;
      try {
        granted = await notificationService.scheduleDailyReminder(
          hour: picked.hour,
          minute: picked.minute,
          activeQuestCount: activeQuestCount,
        );
      } catch (_) {
        if (context.mounted) _showGenericNotificationError(context);
        return;
      }

      final candidate = _copyProfile(originalProfile)
        ..reminderMinutesSinceMidnight = picked.hour * 60 + picked.minute;
      final outcome = await _saveNotificationProfile(
        ref: ref,
        candidate: candidate,
        compensate: () async {
          if (current == null) {
            await notificationService.cancelReminder();
          } else {
            await notificationService.scheduleDailyReminder(
              hour: current ~/ 60,
              minute: current % 60,
              activeQuestCount: activeQuestCount,
            );
          }
        },
      );
      if (!outcome.saved) {
        if (context.mounted) {
          _showGenericNotificationError(context, restored: outcome.restored);
        }
        return;
      }

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              granted
                  ? '알림 시간이 저장됐어요.'
                  : '시간은 저장됐지만 알림 권한이 꺼져 있어요 — 기기 설정에서 허용해주세요.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _notificationChangeInProgress = false);
    }
  }

  /// Shown when scheduling/cancelling a reminder throws (e.g. a platform or
  /// timezone-resolution exception) — never leaks raw exception details,
  /// and the caller is expected to leave the prior profile value untouched.
  void _showGenericNotificationError(
    BuildContext context, {
    bool restored = true,
  }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          restored
              ? '알림 설정을 변경하지 못했어요. 잠시 후 다시 시도해주세요.'
              : '알림 설정을 저장하지 못했고 이전 알림도 복원하지 못했어요. 기기 알림 설정을 확인해주세요.',
        ),
      ),
    );
  }

  Future<void> _toggleWeeklyReport(
    BuildContext context,
    WidgetRef ref,
    bool enabled,
  ) async {
    if (_notificationChangeInProgress) return;
    setState(() => _notificationChangeInProgress = true);
    final originalProfile = _copyProfile(ref.read(profileProvider));
    final notificationService = ref.read(notificationServiceProvider);

    try {
      var granted = true;
      try {
        if (enabled) {
          granted = await notificationService.scheduleWeeklyReportReminder();
        } else {
          await notificationService.cancelWeeklyReportReminder();
        }
      } catch (_) {
        if (context.mounted) _showGenericNotificationError(context);
        return;
      }

      final candidate = _copyProfile(originalProfile)
        ..weeklyReportReminderEnabled = enabled;
      final outcome = await _saveNotificationProfile(
        ref: ref,
        candidate: candidate,
        compensate: () async {
          if (enabled) {
            await notificationService.cancelWeeklyReportReminder();
          } else {
            await notificationService.scheduleWeeklyReportReminder();
          }
        },
      );
      if (!outcome.saved) {
        if (context.mounted) {
          _showGenericNotificationError(context, restored: outcome.restored);
        }
        return;
      }

      if (context.mounted && enabled) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              granted
                  ? '일요일 20:00에 주간 리포트를 알려드릴게요.'
                  : '설정은 저장됐지만 알림 권한이 꺼져 있어요 — 기기 설정에서 허용해주세요.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _notificationChangeInProgress = false);
    }
  }

  /// Formats an instant as `2026. 7. 23. 오후 3:20`. Written by hand (rather
  /// than `DateFormat.yMd().add_jm()`) so it doesn't depend on
  /// `initializeDateFormatting('ko_KR')` having run — nothing else in this
  /// app currently does that, and adding it just for this one label isn't
  /// worth the extra global init step.
  String _formatAutoBackupTimestamp(DateTime at) {
    final local = at.toLocal();
    final isAm = local.hour < 12;
    final hour12 = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final minute = local.minute.toString().padLeft(2, '0');
    return '${local.year}. ${local.month}. ${local.day}. '
        '${isAm ? '오전' : '오후'} $hour12:$minute';
  }

  /// Shortens a directory path to its last 1–2 components for the compact
  /// settings-row display (plan 3.1: "전체 경로 대신 마지막 1~2개 경로 구성요소만
  /// 화면에 표시"). The full path is only shown in the detail dialog opened
  /// from the info button.
  String _abbreviateAutoBackupPath(String path) {
    final normalized = path.replaceAll('\\', '/');
    final parts = normalized.split('/').where((s) => s.isNotEmpty).toList();
    if (parts.length <= 2) return normalized;
    return '.../${parts[parts.length - 2]}/${parts.last}';
  }

  String _autoBackupToggleSubtitle(AutoBackupState state) {
    if (!state.enabled) {
      return '꺼짐 · 폴더를 선택하면 앱을 열 때 주기적으로 백업해요';
    }
    if (state.hasUnresolvedFailure) {
      return '백업 실패 · 폴더 접근을 확인해주세요';
    }
    final freqLabel = state.frequency == AutoBackupFrequency.daily
        ? '매일'
        : '매주';
    return '켜짐 · $freqLabel';
  }

  String _autoBackupLastRunSubtitle(AutoBackupState state) {
    final successText = state.lastSuccessAt == null
        ? '아직 자동 백업하지 않았어요'
        : '마지막 성공 ${_formatAutoBackupTimestamp(state.lastSuccessAt!)}';
    if (!state.hasUnresolvedFailure) return successText;
    return '$successText · 최근 시도 실패';
  }

  void _showAutoBackupSaveFailedSnackBar(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('설정을 저장하지 못했어요. 잠시 후 다시 시도해주세요.')),
    );
  }

  void _showAutoBackupProbeFailedSnackBar(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('선택한 폴더에 쓸 수 없어요. 다른 폴더를 선택해주세요.')),
    );
  }

  Future<void> _toggleAutoBackup(
    BuildContext context,
    WidgetRef ref,
    bool enable,
  ) async {
    if (enable) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('자동 백업'),
          content: const Text(
            '앱을 시작하거나 다시 열었을 때 선택한 주기가 지났으면 백업해요. 앱이 완전히 종료된 '
            '동안에는 실행되지 않아요. 동기화 폴더를 선택하면 해당 서비스의 정책에 따라 백업 '
            '파일이 외부로 전송될 수 있어요.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('폴더 선택하고 켜기'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    final result = await ref
        .read(autoBackupProvider.notifier)
        .setEnabled(enable);
    if (!context.mounted) return;
    switch (result) {
      case AutoBackupActionResult.success:
        if (enable) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('자동 백업을 켰어요.')));
        }
        return;
      case AutoBackupActionResult.cancelled:
        return;
      case AutoBackupActionResult.probeFailed:
        _showAutoBackupProbeFailedSnackBar(context);
        return;
      case AutoBackupActionResult.saveFailed:
        _showAutoBackupSaveFailedSnackBar(context);
        return;
    }
  }

  Future<void> _selectAutoBackupDirectory(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final result = await ref
        .read(autoBackupProvider.notifier)
        .selectDirectory();
    if (!context.mounted) return;
    switch (result) {
      case AutoBackupActionResult.success:
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('백업 폴더를 저장했어요.')));
        return;
      case AutoBackupActionResult.cancelled:
        return;
      case AutoBackupActionResult.probeFailed:
        _showAutoBackupProbeFailedSnackBar(context);
        return;
      case AutoBackupActionResult.saveFailed:
        _showAutoBackupSaveFailedSnackBar(context);
        return;
    }
  }

  Future<void> _selectAutoBackupFrequency(
    BuildContext context,
    WidgetRef ref,
    AutoBackupFrequency current,
  ) async {
    final selected = await showDialog<AutoBackupFrequency>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('백업 주기'),
        content: RadioGroup<AutoBackupFrequency>(
          groupValue: current,
          onChanged: (v) => Navigator.pop(context, v),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: const [
              RadioListTile<AutoBackupFrequency>(
                title: Text('매일'),
                value: AutoBackupFrequency.daily,
              ),
              RadioListTile<AutoBackupFrequency>(
                title: Text('매주'),
                value: AutoBackupFrequency.weekly,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소'),
          ),
        ],
      ),
    );
    if (selected == null || selected == current) return;

    final result = await ref
        .read(autoBackupProvider.notifier)
        .setFrequency(selected);
    if (!context.mounted) return;
    if (result == AutoBackupActionResult.saveFailed) {
      _showAutoBackupSaveFailedSnackBar(context);
    }
  }

  Future<void> _backupNow(BuildContext context, WidgetRef ref) async {
    final outcome = await ref.read(autoBackupProvider.notifier).backupNow();
    if (!context.mounted) return;
    switch (outcome) {
      case AutoBackupRunOutcome.ran:
        final failed = ref.read(autoBackupProvider).hasUnresolvedFailure;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(failed ? '백업에 실패했어요. 폴더를 확인해주세요.' : '지금 백업했어요.'),
          ),
        );
        return;
      case AutoBackupRunOutcome.unsupported:
      case AutoBackupRunOutcome.disabled:
      case AutoBackupRunOutcome.noDirectory:
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('자동 백업이 꺼져 있거나 폴더가 설정되지 않았어요.')),
        );
        return;
    }
  }

  Future<void> _showAutoBackupFolderDialog(
    BuildContext context,
    String path,
  ) {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('백업 폴더'),
        content: SingleChildScrollView(child: SelectableText(path)),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('닫기'),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildAutoBackupSection(
    BuildContext context,
    WidgetRef ref,
    AutoBackupState state,
  ) {
    if (!state.isSupported) {
      return [
        SwitchListTile(
          secondary: const Icon(Icons.backup_outlined),
          title: const Text('자동 백업'),
          subtitle: const Text(
            '이 플랫폼에서는 폴더 자동 백업을 지원하지 않아요. 아래 수동 백업을 사용해주세요.',
          ),
          value: false,
          onChanged: null,
        ),
      ];
    }

    final directoryPath = state.directoryPath;
    return [
      SwitchListTile(
        secondary: const Icon(Icons.backup_outlined),
        title: const Text('자동 백업'),
        subtitle: Text(_autoBackupToggleSubtitle(state)),
        value: state.enabled,
        onChanged: state.isChangingSettings
            ? null
            : (v) => _toggleAutoBackup(context, ref, v),
      ),
      ListTile(
        leading: const Icon(Icons.folder_outlined),
        title: const Text('백업 폴더'),
        subtitle: Text(
          directoryPath == null
              ? '선택되지 않음'
              : _abbreviateAutoBackupPath(directoryPath),
        ),
        trailing: directoryPath == null
            ? null
            : IconButton(
                icon: const Icon(Icons.info_outline),
                tooltip: '전체 경로 보기',
                onPressed: () =>
                    _showAutoBackupFolderDialog(context, directoryPath),
              ),
        enabled: !state.isChangingSettings,
        onTap: state.isChangingSettings
            ? null
            : () => _selectAutoBackupDirectory(context, ref),
      ),
      ListTile(
        leading: const Icon(Icons.event_repeat_outlined),
        title: const Text('백업 주기'),
        subtitle: Text(
          state.frequency == AutoBackupFrequency.daily ? '매일' : '매주',
        ),
        enabled: !state.isChangingSettings,
        onTap: state.isChangingSettings
            ? null
            : () => _selectAutoBackupFrequency(context, ref, state.frequency),
      ),
      ListTile(
        leading: const Icon(Icons.history),
        title: const Text('마지막 백업'),
        subtitle: Text(_autoBackupLastRunSubtitle(state)),
        trailing: state.isBackingUp
            ? const Text('백업하는 중...')
            : TextButton(
                onPressed: () => _backupNow(context, ref),
                child: const Text('지금 백업'),
              ),
      ),
    ];
  }

  Future<void> _confirmReset(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('데이터 초기화'),
        content: const Text(
          '모든 스텟·퀘스트·목표·거래·자산·재무계획 기록이 삭제되고 처음 상태로 돌아갑니다. 계속할까요?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('초기화'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final storage = ref.read(storageServiceProvider);
    await storage.statsBox.clear();
    await storage.questsBox.clear();
    await storage.achievementsBox.clear();
    await storage.goalsBox.clear();
    await storage.transactionsBox.clear();
    await storage.assetSnapshotsBox.clear();
    await storage.financialPlanBox.clear();
    for (final s in StorageService.defaultStats) {
      await storage.saveStat(Stat(id: s.id, name: s.name, icon: s.icon));
    }
    // profileBox는 clear하지 않고 현재 레코드를 제자리에서 수정한다 —
    // clear+재생성은 아직 보안 저장소로 마이그레이션되지 못한 레거시 API
    // 키 필드(그 상태에서는 유일한 복사본)까지 지워버린다. reminderMinutes/
    // weeklyReportReminderEnabled와 (아직 남아 있을 수 있는) claudeApiKey는
    // 건드리지 않고, lastQuestRefresh/lastAdviceRefresh/cachedAdvice/
    // onboardingCompleted/preferredStatId만 초기 상태로 되돌린다.
    // lastQuestRefresh는 보존하지 않는다 — 초기화로 추천 퀘스트도 사라졌으니
    // 다음 실행에서 24시간 간격을 기다리지 않고 바로 새 추천이 생성돼야 한다.
    final profile = storage.getProfile();
    profile.lastQuestRefresh = null;
    profile.lastAdviceRefresh = null;
    profile.cachedAdvice = [];
    profile.onboardingCompleted = false;
    profile.preferredStatId = null;
    await storage.saveProfile(profile);
    ref.read(statsProvider.notifier).reload();
    ref.read(questsProvider.notifier).reload();
    ref.read(profileProvider.notifier).reload();
    ref.read(unlockedAchievementsProvider.notifier).reload();
    ref.read(goalsProvider.notifier).reload();
    ref.read(transactionsProvider.notifier).reload();
    ref.read(assetSnapshotsProvider.notifier).reload();
    ref.read(financialPlanProvider.notifier).reload();
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('초기화됐어요.')));
    }
  }

  Future<void> _exportBackup(BuildContext context, WidgetRef ref) async {
    if (_exportInProgress) return;
    setState(() => _exportInProgress = true);
    try {
      final String jsonStr;
      try {
        jsonStr = ref.read(backupServiceProvider).encode();
      } catch (_) {
        if (context.mounted) _showGenericExportError(context);
        return;
      }

      if (!context.mounted) return;

      // 웹은 파일 저장 위치 선택이 불가능해 기존 복사 다이얼로그를 유지한다.
      if (kIsWeb) {
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('백업 내보내기'),
            content: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(child: SelectableText(jsonStr)),
            ),
            actions: [
              TextButton(
                onPressed: () async {
                  try {
                    await Clipboard.setData(ClipboardData(text: jsonStr));
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('클립보드에 복사했어요.')),
                      );
                    }
                  } catch (_) {
                    if (context.mounted) _showGenericExportError(context);
                  }
                },
                child: const Text('복사'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('닫기'),
              ),
            ],
          ),
        );
        return;
      }

      final fileName =
          'human_status_backup_${DateTime.now().toString().split(' ').first}.json';

      if (widget.debugSaveBackupFile != null) {
        try {
          await widget.debugSaveBackupFile!(fileName, jsonStr);
          if (context.mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('백업 파일을 저장했어요.')));
          }
        } catch (_) {
          if (context.mounted) _showGenericExportError(context);
        }
        return;
      }

      final FileSaveLocation? location;
      try {
        location = await getSaveLocation(suggestedName: fileName);
      } catch (_) {
        if (context.mounted) _showGenericExportError(context);
        return;
      }
      if (location == null) return;

      try {
        final bytes = Uint8List.fromList(utf8.encode(jsonStr));
        await XFile.fromData(
          bytes,
          mimeType: 'application/json',
          name: fileName,
        ).saveTo(location.path);
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('백업 파일을 저장했어요.')));
        }
      } catch (_) {
        if (context.mounted) _showGenericExportError(context);
      }
    } finally {
      if (mounted) setState(() => _exportInProgress = false);
    }
  }

  void _showGenericExportError(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('백업 저장에 실패했어요. 잠시 후 다시 시도해주세요.')),
    );
  }

  /// Reloads every provider a restore can touch from storage. Each reload is
  /// best-effort: one notifier throwing (e.g. a corrupt box read) must not
  /// stop the rest from syncing, and must never swallow the caller's own
  /// failure/rollback warning — a reload failure here is silently ignored
  /// rather than rethrown.
  void _reloadBackupAffectedProviders(WidgetRef ref) {
    void safeReload(void Function() reload) {
      try {
        reload();
      } catch (_) {
        // 개별 provider 재로딩 실패가 나머지 재로딩이나 호출자가 이미
        // 보여주기로 한 실패/경고 메시지를 막아서는 안 된다.
      }
    }

    safeReload(() => ref.read(statsProvider.notifier).reload());
    safeReload(() => ref.read(questsProvider.notifier).reload());
    safeReload(() => ref.read(profileProvider.notifier).reload());
    safeReload(() => ref.read(unlockedAchievementsProvider.notifier).reload());
    safeReload(() => ref.read(goalsProvider.notifier).reload());
    safeReload(() => ref.read(transactionsProvider.notifier).reload());
    safeReload(() => ref.read(assetSnapshotsProvider.notifier).reload());
    safeReload(() => ref.read(financialPlanProvider.notifier).reload());
  }

  Future<void> _importBackup(BuildContext context, WidgetRef ref) async {
    if (_importInProgress) return;
    setState(() => _importInProgress = true);
    try {
      // 소스 선택(파일 피커/웹 붙여넣기 다이얼로그/파일 읽기) 전체를 하나의
      // 경계로 감싼다 — 플랫폼 채널이나 파일 IO가 어디서 던지든 원문 예외가
      // 새어나가지 않고 일반화된 오류만 보여준다. `return`으로 끝나는 사용자
      // 취소는 예외가 아니므로 이 catch에 걸리지 않고 조용히 종료된다.
      String? jsonStr;
      try {
        if (widget.debugPickBackupSource != null) {
          jsonStr = await widget.debugPickBackupSource!(context);
        } else if (kIsWeb) {
          final controller = TextEditingController();
          jsonStr = await showDialog<String>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('백업 가져오기'),
              content: TextField(
                controller: controller,
                autofocus: true,
                maxLines: 10,
                decoration: const InputDecoration(hintText: '백업 JSON을 붙여넣으세요'),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('취소'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, controller.text),
                  child: const Text('가져오기'),
                ),
              ],
            ),
          );
        } else {
          const typeGroup = XTypeGroup(label: 'json', extensions: ['json']);
          final file = await openFile(acceptedTypeGroups: [typeGroup]);
          if (file == null) return;
          if (await file.length() > BackupService.maxBackupBytes) {
            throw const FormatException('Backup file is too large');
          }
          jsonStr = await file.readAsString();
        }
      } catch (_) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('파일을 읽을 수 없어요. 다시 시도해주세요.')),
          );
        }
        return;
      }
      // null은 사용자가 선택/붙여넣기를 취소한 것이라 조용히 끝난다. 반면
      // 빈 문자열은 "가져오기"를 눌렀지만 내용이 없는 경우라 오류를 알려야
      // 한다 — 아래 malformed 케이스와 동일하게 교체 확인 없이 종료한다.
      if (jsonStr == null) return;
      if (utf8.encode(jsonStr).length > BackupService.maxBackupBytes) {
        if (context.mounted) _showGenericImportError(context);
        return;
      }
      if (jsonStr.trim().isEmpty) {
        if (context.mounted) _showGenericImportError(context);
        return;
      }

      final backupService = ref.read(backupServiceProvider);
      final BackupPreview preview;
      try {
        preview = backupService.inspect(jsonStr);
      } catch (_) {
        if (context.mounted) _showGenericImportError(context);
        return;
      }

      // 검사를 통과한 경우에만, 요약을 포함한 최종 교체 확인을 띄운다.
      if (!context.mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('백업 가져오기'),
          content: Text(
            '현재 모든 데이터가 아래 백업 내용으로 교체됩니다. 계속할까요?\n\n'
            '· 스텟 ${preview.statsCount}개\n'
            '· 퀘스트 ${preview.questsCount}개\n'
            '· 목표 ${preview.goalsCount}개\n'
            '· 거래 ${preview.transactionsCount}건\n'
            '· 자산 스냅샷 ${preview.assetSnapshotsCount}개\n'
            '· 업적 ${preview.achievementsCount}개\n'
            '· 재무 계획: ${preview.hasFinancialPlan ? '포함됨' : '없음'}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('교체'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;

      try {
        await backupService.restore(jsonStr);
        _reloadBackupAffectedProviders(ref);
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('가져오기가 완료됐어요.')));
        }
      } on BackupRestoreRollbackFailedException catch (_) {
        // apply와 rollback이 모두 실패해 저장소가 부분 상태일 수 있다 — 화면
        // 상태만이라도 실제 저장소와 맞추고, 문제의 심각성을 스낵바보다
        // 눈에 띄는 다이얼로그로 명확히 경고한다.
        _reloadBackupAffectedProviders(ref);
        if (context.mounted) {
          await showDialog<void>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('가져오기 실패'),
              content: const Text(
                '가져오기 도중 오류가 발생했고, 이전 상태로 되돌리는 것도 완료되지 못했어요. '
                '데이터 상태가 불완전할 수 있어요. 백업 파일로 다시 가져오기를 시도하거나 '
                '데이터를 직접 확인해주세요.',
              ),
              actions: [
                FilledButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('확인'),
                ),
              ],
            ),
          );
        }
      } on BackupRestoreException catch (_) {
        // apply는 실패했지만 rollback은 성공해 기존 데이터로 돌아갔다 —
        // mutation이 시작됐던 도메인들을 화면에도 반영한 뒤 재시도를 안내한다.
        _reloadBackupAffectedProviders(ref);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('가져오기에 실패해 기존 데이터로 되돌렸어요. 다시 시도할 수 있어요.'),
            ),
          );
        }
      } catch (_) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('가져오기에 실패했어요. 잠시 후 다시 시도해주세요.')),
          );
        }
      }
    } finally {
      if (mounted) setState(() => _importInProgress = false);
    }
  }

  Future<void> _toggleCrashReporting(
    BuildContext context,
    WidgetRef ref,
    bool enable,
  ) async {
    if (enable) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('익명 크래시 리포팅'),
          content: const Text(
            '켜면 앱이 예기치 않게 오류를 일으켰을 때 예외 종류·스택 정보와 기기·OS·앱 버전 같은 '
            '진단 정보가 Sentry(오류 수집 서비스)로 전송돼요. 퀘스트·목표·거래 등 기록한 내용이나 '
            'Claude API 키는 보내지 않아요. 언제든 다시 끌 수 있고, 자세한 내용은 설정의 '
            '"데이터 및 개인정보"에서 확인할 수 있어요.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('동의하고 켜기'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    final result = await ref
        .read(crashReportingConsentProvider.notifier)
        .setEnabled(enable);
    if (!context.mounted) return;
    if (result == ConsentChangeResult.saveFailed) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('설정을 저장하지 못했어요. 잠시 후 다시 시도해주세요.')),
      );
    }
  }

  void _showGenericImportError(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('백업 파일 형식을 확인할 수 없어요. 다른 파일을 선택해주세요.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(profileProvider);
    final crashReportingConsent = ref.watch(crashReportingConsentProvider);
    final autoBackupState = ref.watch(autoBackupProvider);
    final apiKeySet =
        (ref.read(storageServiceProvider).claudeApiKey ?? '').isNotEmpty;
    final reminderMinutes = profile.reminderMinutesSinceMidnight;
    final reminderSubtitle = kIsWeb
        ? '이 플랫폼(웹)에서는 지원되지 않아요'
        : reminderMinutes != null
        ? '매일 ${(reminderMinutes ~/ 60).toString().padLeft(2, '0')}:${(reminderMinutes % 60).toString().padLeft(2, '0')}'
        : '꺼짐 — 탭해서 설정';

    return Scaffold(
      appBar: AppBar(title: const Text('설정')),
      body: PageContentBounds(
        maxWidth: PageContentBounds.wide,
        child: ListView(
          children: [
            ListTile(
              leading: const Icon(Icons.smart_toy_outlined),
              title: const Text('Claude API 키'),
              subtitle: Text(
                apiKeySet ? '설정됨 — AI 추천 사용 중' : '설정 안 됨 — 로컬 규칙 기반 추천 사용 중',
              ),
              onTap: () => _editApiKey(context, ref),
            ),
            ListTile(
              leading: const Icon(Icons.notifications_outlined),
              title: const Text('알림 시간'),
              // 알림이 켜져 있어도 OS 권한이 거부돼 있으면 실제로는 오지 않으므로,
              // 설정 화면 표시와 실제 동작이 항상 일치하도록 권한 상태를 함께 보여준다.
              subtitle: reminderMinutes != null && !kIsWeb
                  ? FutureBuilder<bool?>(
                      future: ref
                          .read(notificationServiceProvider)
                          .areNotificationsEnabled(),
                      builder: (context, snap) {
                        if (snap.hasData && snap.data == false) {
                          return Text(
                            '$reminderSubtitle · 권한 꺼짐 — 기기 설정에서 허용해주세요',
                            style: TextStyle(color: context.appColors.warning),
                          );
                        }
                        return Text(reminderSubtitle);
                      },
                    )
                  : Text(reminderSubtitle),
              enabled: !_notificationChangeInProgress,
              onTap: _notificationChangeInProgress
                  ? null
                  : () => _editReminder(context, ref),
            ),
            SwitchListTile(
              secondary: const Icon(Icons.summarize_outlined),
              title: const Text('주간 리포트 알림'),
              subtitle: Text(
                kIsWeb ? '이 플랫폼(웹)에서는 지원되지 않아요' : '일요일 20:00에 한 주 활동 요약을 알려드려요',
              ),
              value: profile.weeklyReportReminderEnabled && !kIsWeb,
              onChanged: kIsWeb || _notificationChangeInProgress
                  ? null
                  : (v) => _toggleWeeklyReport(context, ref, v),
            ),
            SwitchListTile(
              secondary: const Icon(Icons.bug_report_outlined),
              title: const Text('익명 크래시 리포팅'),
              subtitle: Text(
                !crashReportingConsent.enabled
                    ? '꺼짐 · 오류 정보가 외부로 전송되지 않아요'
                    : crashReportingConsent.sessionInitFailed
                    ? '켜짐 · 이번 세션은 연결하지 못했어요. 다음 실행 때 다시 시도해요'
                    : '켜짐 · 앱 오류와 기기·OS 정보를 Sentry로 보내요',
              ),
              value: crashReportingConsent.enabled,
              onChanged: crashReportingConsent.isChanging
                  ? null
                  : (v) => _toggleCrashReporting(context, ref, v),
            ),
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
            ..._buildAutoBackupSection(context, ref, autoBackupState),
            ListTile(
              leading: const Icon(Icons.upload_file),
              title: const Text('백업 내보내기'),
              // 확인 대화상자를 띄우는 동안까지 애니메이션이 도는 스피너를
              // 계속 보여주면 오해를 주므로(사용자 입력을 기다리는 중일 뿐
              // 실제로 바쁜 게 아니다), 정적인 텍스트/비활성화로만 진행 중임을
              // 알린다.
              subtitle: _exportInProgress ? const Text('저장하는 중...') : null,
              enabled: !_exportInProgress,
              onTap: _exportInProgress
                  ? null
                  : () => _exportBackup(context, ref),
            ),
            ListTile(
              leading: const Icon(Icons.download),
              title: const Text('백업 가져오기'),
              subtitle: _importInProgress ? const Text('가져오는 중...') : null,
              enabled: !_importInProgress,
              onTap: _importInProgress
                  ? null
                  : () => _importBackup(context, ref),
            ),
            ListTile(
              leading: const Icon(Icons.privacy_tip_outlined),
              title: const Text('데이터 및 개인정보'),
              subtitle: const Text('기기에 저장 · API 키는 백업에서 제외'),
              onTap: () => _showDataPrivacyDialog(context),
            ),
            const Divider(),
            ListTile(
              leading: Icon(
                Icons.delete_forever,
                color: context.appColors.error,
              ),
              title: Text(
                '데이터 초기화',
                style: TextStyle(color: context.appColors.error),
              ),
              onTap: () => _confirmReset(context, ref),
            ),
          ],
        ),
      ),
    );
  }

  /// Read-only informational dialog — no storage or provider access, so it
  /// cannot mutate app state no matter how it's dismissed.
  Future<void> _showDataPrivacyDialog(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('데이터 및 개인정보'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '모든 게임 데이터(스텟·퀘스트·목표·거래 등)는 계정이나 서버 동기화 없이 이 '
                '기기에만 로컬로 저장돼요.',
              ),
              const SizedBox(height: 12),
              const Text(
                'Claude API 키는 지원되는 플랫폼에서는 보안 저장소(Android Keystore, '
                'iOS/macOS Keychain, Windows DPAPI, Linux libsecret)에 저장되고, '
                '백업 파일에는 포함되지 않아요.',
              ),
              const SizedBox(height: 12),
              const Text(
                '기기를 바꾸거나 데이터를 초기화하기 전에는 설정의 "백업 내보내기"로 먼저 '
                '내보내두는 걸 권장해요.',
              ),
              const SizedBox(height: 12),
              const Text(
                '자동 백업을 켜면 앱을 열 때 선택한 폴더에 백업 파일을 저장해요. 그 폴더가 '
                'Google Drive·OneDrive·iCloud Drive 같은 동기화 폴더라면 해당 서비스 정책에 '
                '따라 파일이 외부로 전송될 수 있어요 — 앱은 그 여부를 알거나 통제하지 않아요. '
                '자동 백업 폴더/주기 같은 기기별 설정 자체는 백업 파일에는 포함되지 않아요.',
              ),
              const SizedBox(height: 12),
              const Text(
                '웹에서는 API 키 보호 수준이 다른 플랫폼보다 낮아요. 신뢰할 수 있는 기기의 '
                'HTTPS 환경에서만 사용해주세요.',
              ),
              const SizedBox(height: 12),
              const Text(
                '익명 크래시 리포팅은 기본적으로 꺼져 있고, 설정에서 직접 켠 경우에만 오류 '
                '정보가 Sentry로 전송돼요. 자세한 처리 항목·보관 기간은 아래 버튼으로 볼 수 '
                '있어요.',
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => _showFullPrivacyPolicy(context),
                  child: const Text('개인정보처리방침 전체 보기'),
                ),
              ),
            ],
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('닫기'),
          ),
        ],
      ),
    );
  }

  /// Loads the bundled `docs/privacy_policy.md` asset and shows it verbatim
  /// (plain text, not markdown-rendered) in a scrollable dialog — this is
  /// the same document maintainers edit, so there is a single source of
  /// truth instead of a copy that can drift out of sync.
  Future<void> _showFullPrivacyPolicy(BuildContext context) async {
    String? text;
    try {
      text = await rootBundle.loadString('docs/privacy_policy.md');
    } catch (_) {
      // Falls through with text == null; shown as a load-failure message
      // below instead of leaking the raw asset-loading exception.
    }
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('개인정보처리방침'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: SelectableText(
              text ?? '문서를 불러오지 못했어요. 잠시 후 다시 시도해주세요.',
            ),
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('닫기'),
          ),
        ],
      ),
    );
  }
}
