import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/goal_provider.dart';
import '../providers/profile_provider.dart';
import '../providers/quest_provider.dart';
import '../theme/app_spacing.dart';
import '../widgets/achievement_dialog.dart';
import '../widgets/action_hub_card.dart';
import '../widgets/empty_state.dart';
import '../widgets/level_up_dialog.dart';
import '../widgets/progression_journey_card.dart';
import '../widgets/quest_card.dart';
import '../widgets/stat_bar.dart';
import 'goal_form_screen.dart';

class DashboardScreen extends ConsumerWidget {
  /// HomeShell 안에서 넘겨주면 "전체 퀘스트 보기"가 퀘스트 탭으로 전환한다
  /// (중복 화면 push 방지). 독립 실행/테스트에서는 null로 두면 허브가 안전한
  /// 대체 라우트(QuestsScreen push)를 쓴다.
  final VoidCallback? onViewAllQuests;

  const DashboardScreen({super.key, this.onViewAllQuests});

  /// 홈의 성공 기준은 "화면을 벗어나지 않고 퀘스트 하나를 완료"할 수 있는 것 —
  /// 퀘스트 탭과 동일한 완료 처리(스낵바 + 레벨업/업적 다이얼로그)를 그대로 쓴다.
  Future<void> _completeQuest(
    BuildContext context,
    WidgetRef ref,
    String id,
  ) async {
    final matches = ref.read(questsProvider).where((q) => q.id == id);
    final quest = matches.isNotEmpty ? matches.first : null;
    final result = await ref.read(questsProvider.notifier).completeQuest(id);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(quest != null ? '"${quest.title}" 완료!' : '퀘스트를 완료했어요!'),
      ),
    );
    await showLevelUpDialog(context, ref.read(statsProvider), result.levelUps);
    if (!context.mounted) return;
    await showAchievementDialog(context, result.newAchievements);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(statsProvider);
    final overallLevel = ref.watch(overallLevelProvider);
    final activeQuests = ref.watch(activeQuestsProvider);
    final activeGoals = ref.watch(activeGoalsProvider);
    final goalProgress = ref.watch(goalProgressMapProvider);
    final goals = ref.watch(goalsProvider);
    final allQuests = ref.watch(questsProvider);
    final nextQuest = ref.watch(nextQuestProvider);
    // 퀘스트·목표를 (완료 이력 포함) 한 번도 만든 적 없는 진짜 최초 상태에서만
    // 안내 문구 두 개 대신 행동 하나를 준다. 한 번이라도 퀘스트를 완료했거나
    // 목표를 만든 적이 있다면, 지금 당장 진행중/추천 항목이 없더라도
    // 돌아온 사용자이므로 아래 허브(요약 + CTA)를 계속 보여준다.
    final isFirstRun = allQuests.isEmpty && goals.isEmpty;
    // 위 허브에서 이미 강조된 퀘스트는 아래 목록에서 중복 표시하지 않는다.
    final remainingActiveQuests = activeQuests
        .where((q) => q.id != nextQuest?.id)
        .toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Human Status')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          if (isFirstRun) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '시작해볼까요?',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      '첫 목표를 만들면 AI가 실행할 작은 퀘스트로 나눠드려요. 퀘스트를 완료할 때마다 스텟이 자라요.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    FilledButton.icon(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const GoalFormScreen(),
                        ),
                      ),
                      icon: const Icon(Icons.flag),
                      label: const Text('첫 목표 만들기'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
          ] else ...[
            ActionHubCard(onViewAllQuests: onViewAllQuests),
            const SizedBox(height: AppSpacing.lg),
            const ProgressionJourneyCard(),
            const SizedBox(height: AppSpacing.lg),
          ],
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                children: [
                  Text('종합 레벨', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Lv.$overallLevel',
                    style: Theme.of(context).textTheme.displaySmall,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text('스텟', style: Theme.of(context).textTheme.titleLarge),
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.sm,
              ),
              child: Column(
                children: stats.map((s) => StatBar(stat: s)).toList(),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('진행중인 퀘스트', style: Theme.of(context).textTheme.titleLarge),
              Text('${activeQuests.length}개'),
            ],
          ),
          if (remainingActiveQuests.isEmpty)
            EmptyState(
              icon: Icons.checklist_outlined,
              message: activeQuests.isEmpty
                  ? '진행중인 퀘스트가 없어요.\n퀘스트 탭에서 추가해보세요.'
                  : '위 오늘의 행동에서 다음 퀘스트를 완료해보세요.',
            )
          else
            ...remainingActiveQuests
                .take(3)
                .map(
                  (q) => QuestCard(
                    quest: q,
                    stats: stats,
                    goals: goals,
                    actions: [
                      FilledButton(
                        onPressed: () => _completeQuest(context, ref, q.id),
                        child: const Text('완료'),
                      ),
                    ],
                  ),
                ),
          const SizedBox(height: AppSpacing.lg),
          Text('진행중인 목표', style: Theme.of(context).textTheme.titleLarge),
          if (activeGoals.isEmpty)
            const EmptyState(
              icon: Icons.flag_outlined,
              message: '설정된 목표가 없어요.\n목표 탭에서 추가해보세요.',
            )
          else
            ...activeGoals
                .take(3)
                .map(
                  (g) => Card(
                    margin: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            g.title,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(AppRadius.sm),
                            child: LinearProgressIndicator(
                              value: goalProgress[g.id] ?? 0,
                              minHeight: 6,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
        ],
      ),
    );
  }
}
