import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/stat.dart';
import '../../providers/asset_snapshot_provider.dart';
import '../../providers/finance_provider.dart';
import '../../providers/financial_planning_provider.dart';
import '../../providers/goal_provider.dart';
import '../../providers/profile_provider.dart';
import '../../providers/quest_provider.dart';
import '../../services/storage_service.dart';
import '../../theme/app_colors.dart';

/// 데이터 초기화 — 확인 후 스텟을 기본값으로 되돌리고, secure storage
/// 전용일 수 있는 레거시 API 키 필드는 건드리지 않는다.
class ResetDataSection extends ConsumerWidget {
  const ResetDataSection({super.key});

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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      leading: Icon(Icons.delete_forever, color: context.appColors.error),
      title: Text('데이터 초기화', style: TextStyle(color: context.appColors.error)),
      onTap: () => _confirmReset(context, ref),
    );
  }
}
