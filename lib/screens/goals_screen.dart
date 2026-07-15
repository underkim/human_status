import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/goal.dart';
import '../providers/goal_provider.dart';
import '../providers/profile_provider.dart';
import '../theme/app_spacing.dart';
import '../utils/formatters.dart';
import '../widgets/achievement_dialog.dart';
import '../widgets/empty_state.dart';
import '../widgets/goal_progress_card.dart';
import '../widgets/level_up_dialog.dart';
import 'goal_form_screen.dart';

/// Top-level 목표 destination — Scaffold chrome around [GoalsListView].
class GoalsScreen extends StatelessWidget {
  const GoalsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('목표')),
      body: const GoalsListView(),
      floatingActionButton: FloatingActionButton(
        // 탭마다 고유 heroTag — quests_screen.dart의 FAB 주석 참고.
        heroTag: 'goals_fab',
        onPressed: () => Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const GoalFormScreen())),
        child: const Icon(Icons.add),
      ),
    );
  }
}

class GoalsListView extends ConsumerWidget {
  const GoalsListView({super.key});

  Future<void> _completeGoal(
    BuildContext context,
    WidgetRef ref,
    Goal goal,
  ) async {
    final result = await ref.read(goalsProvider.notifier).completeGoal(goal.id);
    if (!context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      SnackBar(content: Text('"${goal.title}" 목표를 달성했어요!')),
    );
    await showLevelUpDialog(context, ref.read(statsProvider), {
      goal.statId: result.levelUp,
    });
    if (!context.mounted) return;
    await showAchievementDialog(context, result.newAchievements);
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    Goal goal,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('목표 삭제'),
        content: Text('"${goal.title}" 목표를 삭제할까요? 연결된 진행중 퀘스트는 일반 퀘스트로 남아요.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(goalsProvider.notifier).deleteGoal(goal.id);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(statsProvider);
    final active = [...ref.watch(activeGoalsProvider)]
      ..sort((a, b) {
        // 기한이 가까운 목표부터 — "지금 뭐가 급한지"가 목록 순서만으로 보이게.
        if (a.targetDate == null && b.targetDate == null) return 0;
        if (a.targetDate == null) return 1;
        if (b.targetDate == null) return -1;
        return a.targetDate!.compareTo(b.targetDate!);
      });
    final completed = ref.watch(completedGoalsProvider);
    final progress = ref.watch(goalProgressMapProvider);

    if (active.isEmpty && completed.isEmpty) {
      return const EmptyState(
        icon: Icons.flag_outlined,
        message: '아직 설정한 목표가 없어요.\n오른쪽 아래 + 버튼으로 목표를 추가해보세요.',
      );
    }

    String statLabel(String statId) {
      for (final s in stats) {
        if (s.id == statId) return '${s.icon} ${s.name}';
      }
      return statId;
    }

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        if (active.isNotEmpty) ...[
          Text('진행중인 목표', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: AppSpacing.sm),
          ...active.map(
            (g) => GoalProgressCard(
              title: g.title,
              description: g.description.isNotEmpty ? g.description : null,
              progress: progress[g.id] ?? 0,
              trailingInfo: g.targetAmount != null
                  ? '${formatWon(g.currentAmount)} / ${formatWon(g.targetAmount!)}'
                  : '${((progress[g.id] ?? 0) * 100).toInt()}%',
              statLabel: statLabel(g.statId),
              targetDateLabel: g.targetDate != null
                  ? formatDday(g.targetDate!)
                  : null,
              completionHint: g.targetAmount != null
                  ? '금액이 목표에 도달하면 자동으로 완료돼요'
                  : '연결된 퀘스트를 모두 마치면 자동으로 완료돼요 · 직접 완료도 가능해요',
              onComplete: g.targetAmount == null
                  ? () => _completeGoal(context, ref, g)
                  : null,
              onEdit: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => GoalFormScreen(existing: g)),
              ),
              onDelete: () => _confirmDelete(context, ref, g),
            ),
          ),
        ],
        if (completed.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.lg),
          Text('달성한 목표', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: AppSpacing.sm),
          ...completed.map(
            (g) => GoalProgressCard(
              title: g.title,
              description: g.description.isNotEmpty ? g.description : null,
              progress: 1,
              trailingInfo: g.targetAmount != null
                  ? '${formatWon(g.currentAmount)} / ${formatWon(g.targetAmount!)}'
                  : '100%',
              statLabel: statLabel(g.statId),
              isCompleted: true,
            ),
          ),
        ],
      ],
    );
  }
}
