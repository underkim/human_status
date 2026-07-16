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

class GoalsListView extends ConsumerStatefulWidget {
  const GoalsListView({super.key});

  @override
  ConsumerState<GoalsListView> createState() => _GoalsListViewState();
}

class _GoalsListViewState extends ConsumerState<GoalsListView> {
  // 목표별 진행중 가드 — 같은 목표에 대한 완료/삭제 콜백이 리빌드 이전에
  // 연달아 들어와도 한 번만 처리되도록 한다. finance_screen.dart의
  // _pendingDeletes와 같은 패턴.
  final Set<String> _completingGoals = {};
  final Set<String> _pendingDeletes = {};

  Future<void> _completeGoal(Goal goal) async {
    if (_completingGoals.contains(goal.id)) return;
    setState(() => _completingGoals.add(goal.id));
    try {
      final result = await ref.read(goalsProvider.notifier).completeGoal(goal.id);
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      messenger.showSnackBar(
        SnackBar(content: Text('"${goal.title}" 목표를 달성했어요!')),
      );
      await showLevelUpDialog(context, ref.read(statsProvider), {
        goal.statId: result.levelUp,
      });
      if (!mounted) return;
      await showAchievementDialog(context, result.newAchievements);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('목표 완료 처리에 실패했어요. 잠시 후 다시 시도해주세요.')),
        );
      }
    } finally {
      if (mounted) setState(() => _completingGoals.remove(goal.id));
    }
  }

  Future<void> _confirmDelete(Goal goal) async {
    // 확인창이 뜨기도 전에 같은 목표를 빠르게 두 번 눌러도 확인창은 하나만
    // 뜨도록, 다이얼로그를 열기 직전에(첫 await 이전에 동기적으로) pending
    // 집합에 넣는다.
    if (_pendingDeletes.contains(goal.id)) return;
    setState(() => _pendingDeletes.add(goal.id));
    try {
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
      if (confirmed != true || !mounted) return;
      try {
        await ref.read(goalsProvider.notifier).deleteGoal(goal.id);
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('목표를 삭제하지 못했어요. 잠시 후 다시 시도해주세요.')),
          );
        }
      }
    } finally {
      if (mounted) setState(() => _pendingDeletes.remove(goal.id));
    }
  }

  @override
  Widget build(BuildContext context) {
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
              isCompleting: _completingGoals.contains(g.id),
              onComplete: g.targetAmount == null
                  ? () => _completeGoal(g)
                  : null,
              onEdit: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => GoalFormScreen(existing: g)),
              ),
              onDelete: () => _confirmDelete(g),
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
