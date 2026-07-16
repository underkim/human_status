import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/goal.dart';
import '../models/quest.dart';
import '../models/stat.dart';
import '../providers/goal_provider.dart';
import '../providers/profile_provider.dart';
import '../providers/quest_provider.dart';
import '../theme/app_spacing.dart';
import '../widgets/achievement_dialog.dart';
import '../widgets/action_hub_card.dart';
import '../widgets/empty_state.dart';
import '../widgets/level_up_dialog.dart';
import '../widgets/page_content_bounds.dart';
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
      body: PageContentBounds(
        maxWidth: PageContentBounds.wide,
        child: ListView(
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
                    Text(
                      '종합 레벨',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
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
              _RemainingActiveQuests(
                quests: remainingActiveQuests.take(3).toList(),
                stats: stats,
                goals: goals,
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
                      margin: const EdgeInsets.symmetric(
                        vertical: AppSpacing.xs,
                      ),
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
      ),
    );
  }
}

/// 허브 아래 "진행중인 퀘스트" 목록의 남은 카드들 — 퀘스트별 완료 가드는
/// 재빌드 이전(첫 await 이전)에 동기적으로 세팅되어 연타를 막고, 완료
/// 처리 중인 카드만 스피너로 잠근다(나머지 행은 그대로 조작 가능).
/// quests_screen.dart의 `_ActiveTab`과 같은 패턴 — 홈의 성공 기준은
/// "화면을 벗어나지 않고 퀘스트 하나를 완료"할 수 있는 것이므로, 완료
/// 피드백(스낵바 + 레벨업/업적 다이얼로그)도 퀘스트 탭과 동일하게 쓴다.
class _RemainingActiveQuests extends ConsumerStatefulWidget {
  final List<Quest> quests;
  final List<Stat> stats;
  final List<Goal> goals;

  const _RemainingActiveQuests({
    required this.quests,
    required this.stats,
    required this.goals,
  });

  @override
  ConsumerState<_RemainingActiveQuests> createState() =>
      _RemainingActiveQuestsState();
}

class _RemainingActiveQuestsState
    extends ConsumerState<_RemainingActiveQuests> {
  final Set<String> _completingIds = {};

  Future<void> _completeQuest(Quest quest) async {
    // 실패 스낵바의 재시도 액션은 ScaffoldMessenger(이 State보다 상위)가
    // 들고 있어서, 리스트 리빌드/화면 전환으로 이 State가 이미 dispose된
    // 뒤에도 그 콜백이 호출될 수 있다 — setState를 부르기 전에 반드시
    // 먼저 확인한다.
    if (!mounted) return;
    if (_completingIds.contains(quest.id)) return;
    setState(() => _completingIds.add(quest.id));
    try {
      final result = await ref
          .read(questsProvider.notifier)
          .completeQuest(quest.id);
      if (!mounted) return;
      // 다른 화면이 먼저 완료/삭제해 이 호출이 조용한 무결과였다면
      // (didComplete == false) 성공 UI도 에러 UI도 띄우지 않는다.
      if (!result.didComplete) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('"${quest.title}" 완료!')));
      await showLevelUpDialog(
        context,
        ref.read(statsProvider),
        result.levelUps,
      );
      if (!mounted) return;
      await showAchievementDialog(context, result.newAchievements);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('퀘스트 완료 처리에 실패했어요. 잠시 후 다시 시도해주세요.'),
          action: SnackBarAction(
            label: '재시도',
            onPressed: () => _completeQuest(quest),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _completingIds.remove(quest.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: widget.quests.map((q) {
        final completing = _completingIds.contains(q.id);
        return QuestCard(
          quest: q,
          stats: widget.stats,
          goals: widget.goals,
          actions: [
            FilledButton(
              onPressed: completing ? null : () => _completeQuest(q),
              child: completing
                  ? pendingActionIndicator('완료 처리 중')
                  : const Text('완료'),
            ),
          ],
        );
      }).toList(),
    );
  }
}
