import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/goal.dart';
import '../models/stat.dart';
import '../providers/goal_provider.dart';
import '../providers/profile_provider.dart';
import '../widgets/achievement_dialog.dart';
import '../widgets/level_up_dialog.dart';

class GoalsListView extends ConsumerWidget {
  const GoalsListView({super.key});

  Future<void> _completeGoal(BuildContext context, WidgetRef ref, Goal goal) async {
    final result = await ref.read(goalsProvider.notifier).completeGoal(goal.id);
    if (!context.mounted) return;
    await showLevelUpDialog(context, ref.read(statsProvider), {goal.statId: result.levelUp});
    if (!context.mounted) return;
    await showAchievementDialog(context, result.newAchievements);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(statsProvider);
    final active = ref.watch(activeGoalsProvider);
    final completed = ref.watch(completedGoalsProvider);
    final progress = ref.watch(goalProgressMapProvider);

    if (active.isEmpty && completed.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            '아직 설정한 목표가 없어요.\n오른쪽 아래 + 버튼으로 목표를 추가해보세요.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (active.isNotEmpty) ...[
          Text('진행중인 목표', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          ...active.map((g) => _GoalCard(
                goal: g,
                stats: stats,
                progress: progress[g.id] ?? 0,
                onComplete: g.targetAmount == null ? () => _completeGoal(context, ref, g) : null,
              )),
        ],
        if (completed.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('달성한 목표', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          ...completed.map((g) => _GoalCard(goal: g, stats: stats, progress: 1, onComplete: null)),
        ],
      ],
    );
  }
}

class _GoalCard extends StatelessWidget {
  final Goal goal;
  final List<Stat> stats;
  final double progress;
  final VoidCallback? onComplete;

  const _GoalCard({
    required this.goal,
    required this.stats,
    required this.progress,
    required this.onComplete,
  });

  String _statLabel() {
    for (final s in stats) {
      if (s.id == goal.statId) return '${s.icon} ${s.name}';
    }
    return goal.statId;
  }

  @override
  Widget build(BuildContext context) {
    final isCompleted = goal.status == GoalStatus.completed;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(goal.title, style: Theme.of(context).textTheme.titleMedium)),
                Chip(label: Text(_statLabel()), visualDensity: VisualDensity.compact),
              ],
            ),
            if (goal.description.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(goal.description, style: Theme.of(context).textTheme.bodyMedium),
            ],
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(value: progress, minHeight: 8),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  goal.targetAmount != null
                      ? '${goal.currentAmount.toInt()} / ${goal.targetAmount!.toInt()}'
                      : '${(progress * 100).toInt()}%',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (goal.targetDate != null)
                  Text(
                    '~${goal.targetDate!.toString().split(' ').first}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              ],
            ),
            if (onComplete != null) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(onPressed: onComplete, child: const Text('목표 달성')),
              ),
            ],
            if (isCompleted) ...[
              const SizedBox(height: 6),
              Row(
                children: const [
                  Icon(Icons.check_circle, size: 16, color: Colors.green),
                  SizedBox(width: 4),
                  Text('달성 완료'),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
