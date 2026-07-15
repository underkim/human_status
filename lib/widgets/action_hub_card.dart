import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/goal_provider.dart';
import '../providers/profile_provider.dart';
import '../providers/quest_provider.dart';
import '../screens/quest_form_screen.dart';
import '../screens/quests_screen.dart';
import '../services/daily_summary_service.dart';
import '../theme/app_spacing.dart';
import 'achievement_dialog.dart';
import 'level_up_dialog.dart';
import 'quest_card.dart';

/// 홈 상단 "오늘의 행동" 허브 — 지금 당장 할 일을 스크롤 없이 완료할 수
/// 있게 한다. 진행중 퀘스트가 있으면 [nextQuestProvider]가 고른 단 하나를
/// 강조하고, 없으면 추천 퀘스트 채택을, 그마저 없으면 퀘스트 추가 CTA를
/// 보여준다. 완료 처리 중에는 버튼을 잠가 중복 제출을 막고, 실패 시에는
/// 카드를 그대로 둔 채 재시도 가능한 스낵바만 띄운다(성공 시 피드백은
/// 퀘스트 탭과 동일하게 스낵바 + 레벨업/업적 다이얼로그).
class ActionHubCard extends ConsumerStatefulWidget {
  /// HomeShell 안에서는 이 콜백으로 퀘스트 탭으로 전환한다(중복 화면 push
  /// 방지). 독립 실행/테스트에서는 null이면 QuestsScreen을 직접 push한다.
  final VoidCallback? onViewAllQuests;

  const ActionHubCard({super.key, this.onViewAllQuests});

  @override
  ConsumerState<ActionHubCard> createState() => _ActionHubCardState();
}

class _ActionHubCardState extends ConsumerState<ActionHubCard> {
  bool _completing = false;

  Future<void> _completeHighlighted(String id, String title) async {
    if (_completing) return;
    setState(() => _completing = true);
    try {
      final result = await ref.read(questsProvider.notifier).completeQuest(id);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('"$title" 완료!')));
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
          content: const Text('퀘스트 완료에 실패했어요. 다시 시도해주세요.'),
          action: SnackBarAction(
            label: '재시도',
            onPressed: () => _completeHighlighted(id, title),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _completing = false);
    }
  }

  void _viewAllQuests(BuildContext context) {
    final callback = widget.onViewAllQuests;
    if (callback != null) {
      callback();
      return;
    }
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const QuestsScreen()));
  }

  void _addQuest(BuildContext context) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const QuestFormScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final stats = ref.watch(statsProvider);
    final goals = ref.watch(goalsProvider);
    final nextQuest = ref.watch(nextQuestProvider);
    final suggested = ref.watch(suggestedQuestsProvider);
    final summary = ref.watch(todaySummaryProvider);

    Widget body;
    if (nextQuest != null) {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('다음 퀘스트', style: theme.textTheme.titleSmall),
          QuestCard(
            quest: nextQuest,
            stats: stats,
            goals: goals,
            actions: [
              FilledButton(
                onPressed: _completing
                    ? null
                    : () => _completeHighlighted(nextQuest.id, nextQuest.title),
                child: _completing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('완료'),
              ),
            ],
          ),
        ],
      );
    } else if (suggested.isNotEmpty) {
      final top = suggested.first;
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('추천 퀘스트', style: theme.textTheme.titleSmall),
          QuestCard(
            quest: top,
            stats: stats,
            goals: goals,
            actions: [
              FilledButton(
                onPressed: () =>
                    ref.read(questsProvider.notifier).adoptSuggestion(top.id),
                child: const Text('채택하고 시작'),
              ),
            ],
          ),
        ],
      );
    } else {
      // 이 지점에 도달했다는 건 DashboardScreen이 이미 진짜 첫 실행이
      // 아니라고 판단했다는 뜻(퀘스트나 목표를 만든 이력이 있음) — 지금
      // 당장 진행중/추천 항목이 없을 뿐이므로 다음 행동을 만들 CTA를 준다.
      body = Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '지금 진행중인 퀘스트가 없어요. 새 퀘스트를 추가해보세요.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: AppSpacing.sm),
            FilledButton.icon(
              onPressed: () => _addQuest(context),
              icon: const Icon(Icons.add_task),
              label: const Text('퀘스트 추가'),
            ),
          ],
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('오늘의 행동', style: theme.textTheme.titleLarge),
            const SizedBox(height: AppSpacing.xs),
            Text(
              '오늘 완료 ${summary.completedCount}개 · +${formatXp(summary.xp)} XP',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: AppSpacing.sm),
            body,
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => _viewAllQuests(context),
                child: const Text('전체 퀘스트 보기'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
