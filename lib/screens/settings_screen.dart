import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/stat.dart';
import '../providers/asset_snapshot_provider.dart';
import '../providers/finance_provider.dart';
import '../providers/financial_planning_provider.dart';
import '../providers/goal_provider.dart';
import '../providers/profile_provider.dart';
import '../providers/quest_provider.dart';
import '../services/backup_service.dart';
import '../services/storage_service.dart';
import '../theme/app_colors.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
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
          const SnackBar(content: Text('API 키를 저장하지 못했습니다. 잠시 후 다시 시도해주세요.')),
        );
      }
      return;
    }
    ref.read(profileProvider.notifier).reload();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.isEmpty ? 'API 키가 삭제되었습니다.' : 'API 키가 저장되었습니다.'),
        ),
      );
    }
  }

  Future<void> _editReminder(BuildContext context, WidgetRef ref) async {
    if (kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('알림은 이 플랫폼(웹)에서는 지원되지 않아요.')),
      );
      return;
    }

    final storage = ref.read(storageServiceProvider);
    final profile = ref.read(profileProvider);
    final current = profile.reminderMinutesSinceMidnight;

    final action = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('알림 시간'),
        content: Text(
          current != null
              ? '매일 ${(current ~/ 60).toString().padLeft(2, '0')}:${(current % 60).toString().padLeft(2, '0')}에 알림을 보내드려요.'
              : '진행중인 퀘스트를 알려주는 매일 알림을 설정할 수 있어요.',
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

    if (action == 'off') {
      try {
        await notificationService.cancelReminder();
      } catch (_) {
        if (context.mounted) _showGenericNotificationError(context);
        return;
      }
      profile.reminderMinutesSinceMidnight = null;
      await storage.saveProfile(profile);
      ref.read(profileProvider.notifier).reload();
      return;
    }

    if (!context.mounted) return;
    final initial = current != null
        ? TimeOfDay(hour: current ~/ 60, minute: current % 60)
        : TimeOfDay.now();
    final picked = await showTimePicker(context: context, initialTime: initial);
    if (picked == null) return;

    final bool granted;
    try {
      granted = await notificationService.scheduleDailyReminder(
        hour: picked.hour,
        minute: picked.minute,
        activeQuestCount: ref.read(activeQuestsProvider).length,
      );
    } catch (_) {
      if (context.mounted) _showGenericNotificationError(context);
      return;
    }

    profile.reminderMinutesSinceMidnight = picked.hour * 60 + picked.minute;
    await storage.saveProfile(profile);
    ref.read(profileProvider.notifier).reload();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            granted
                ? '알림 시간이 저장되었습니다.'
                : '시간은 저장됐지만 알림 권한이 꺼져 있어요 — 기기 설정에서 허용해주세요.',
          ),
        ),
      );
    }
  }

  /// Shown when scheduling/cancelling a reminder throws (e.g. a platform or
  /// timezone-resolution exception) — never leaks raw exception details,
  /// and the caller is expected to leave the prior profile value untouched.
  void _showGenericNotificationError(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('알림 설정을 변경하지 못했습니다. 잠시 후 다시 시도해주세요.')),
    );
  }

  Future<void> _toggleWeeklyReport(
    BuildContext context,
    WidgetRef ref,
    bool enabled,
  ) async {
    final storage = ref.read(storageServiceProvider);
    final profile = ref.read(profileProvider);
    final notificationService = ref.read(notificationServiceProvider);

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

    profile.weeklyReportReminderEnabled = enabled;
    await storage.saveProfile(profile);
    ref.read(profileProvider.notifier).reload();

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
      ).showSnackBar(const SnackBar(content: Text('초기화되었습니다.')));
    }
  }

  Future<void> _exportBackup(BuildContext context, WidgetRef ref) async {
    final jsonStr = BackupService(
      storage: ref.read(storageServiceProvider),
    ).encode();

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
                await Clipboard.setData(ClipboardData(text: jsonStr));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('클립보드에 복사되었습니다.')),
                  );
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
    final location = await getSaveLocation(suggestedName: fileName);
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
        ).showSnackBar(const SnackBar(content: Text('백업 파일을 저장했습니다.')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('백업 저장에 실패했습니다: $e')));
      }
    }
  }

  Future<void> _importBackup(BuildContext context, WidgetRef ref) async {
    String? jsonStr;
    if (kIsWeb) {
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
      try {
        jsonStr = await file.readAsString();
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('파일을 읽을 수 없습니다: $e')));
        }
        return;
      }
    }
    if (jsonStr == null || jsonStr.trim().isEmpty) return;

    // 가져오기는 기존 데이터를 전부 교체하는 파괴적 작업이라 반드시 확인을 거친다.
    if (!context.mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('백업 가져오기'),
        content: const Text('현재 모든 데이터가 백업 내용으로 교체됩니다. 계속할까요?'),
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
      await BackupService(
        storage: ref.read(storageServiceProvider),
      ).restore(jsonStr);
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
        ).showSnackBar(const SnackBar(content: Text('가져오기가 완료되었습니다.')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('가져오기에 실패했습니다: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(profileProvider);
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
      body: ListView(
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
            onTap: () => _editReminder(context, ref),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.summarize_outlined),
            title: const Text('주간 리포트 알림'),
            subtitle: Text(
              kIsWeb ? '이 플랫폼(웹)에서는 지원되지 않아요' : '일요일 20:00에 한 주 활동 요약을 알려드려요',
            ),
            value: profile.weeklyReportReminderEnabled && !kIsWeb,
            onChanged: kIsWeb
                ? null
                : (v) => _toggleWeeklyReport(context, ref, v),
          ),
          ListTile(
            leading: const Icon(Icons.refresh),
            title: const Text('추천 퀘스트 새로고침'),
            subtitle: const Text('보통 24시간마다 자동 갱신돼요. 지금 바로 새로고침할 수 있어요.'),
            onTap: () async {
              await ref.read(questsProvider.notifier).refreshSuggestions();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('추천 퀘스트를 새로고침했습니다.')),
                );
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.upload_file),
            title: const Text('백업 내보내기'),
            onTap: () => _exportBackup(context, ref),
          ),
          ListTile(
            leading: const Icon(Icons.download),
            title: const Text('백업 가져오기'),
            onTap: () => _importBackup(context, ref),
          ),
          const Divider(),
          ListTile(
            leading: Icon(Icons.delete_forever, color: context.appColors.error),
            title: Text(
              '데이터 초기화',
              style: TextStyle(color: context.appColors.error),
            ),
            onTap: () => _confirmReset(context, ref),
          ),
        ],
      ),
    );
  }
}
