import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/achievement_definitions.dart';
import '../models/goal.dart';
import '../models/quest.dart';
import '../services/goal_service.dart';
import '../services/stats_insights_service.dart';
import '../services/storage_service.dart';
import '../services/xp_service.dart';
import 'profile_provider.dart';
import 'quest_provider.dart';

final goalServiceProvider = Provider<GoalService>(
  (ref) => GoalService(storage: ref.watch(storageServiceProvider)),
);

final goalsProvider = StateNotifierProvider<GoalsNotifier, List<Goal>>((ref) {
  return GoalsNotifier(ref.watch(storageServiceProvider), ref);
});

final activeGoalsProvider = Provider<List<Goal>>((ref) {
  return ref.watch(goalsProvider).where((g) => g.status == GoalStatus.active).toList();
});

final completedGoalsProvider = Provider<List<Goal>>((ref) {
  final goals = ref.watch(goalsProvider).where((g) => g.status == GoalStatus.completed).toList();
  goals.sort((a, b) => (b.completedAt ?? b.createdAt).compareTo(a.completedAt ?? a.createdAt));
  return goals;
});

/// Progress (0.0-1.0) per goal id, combining goal + quest state so screens
/// rebuild when either changes.
final goalProgressMapProvider = Provider<Map<String, double>>((ref) {
  final goals = ref.watch(goalsProvider);
  final quests = ref.watch(questsProvider);
  final service = ref.watch(goalServiceProvider);
  return {for (final g in goals) g.id: service.progress(g, quests)};
});

class GoalCompletionResult {
  final LevelUpResult levelUp;
  final List<AchievementDefinition> newAchievements;

  const GoalCompletionResult({required this.levelUp, required this.newAchievements});
}

class GoalsNotifier extends StateNotifier<List<Goal>> {
  final StorageService storage;
  final Ref ref;

  GoalsNotifier(this.storage, this.ref) : super(storage.getGoals());

  void reload() => state = storage.getGoals();

  /// Persists [goal], then decomposes it into quests (Claude if configured,
  /// else the local template fallback) and adds them via questsProvider so
  /// the quest list stays in sync automatically. Returns the generated
  /// quests (may be empty if decomposition failed entirely).
  Future<List<Quest>> createGoal(Goal goal) async {
    await storage.saveGoal(goal);
    reload();

    final quests = await ref.read(goalServiceProvider).decompose(goal);
    for (final q in quests) {
      await ref.read(questsProvider.notifier).addQuest(q);
    }
    return quests;
  }

  /// Marks [goalId] completed, awards a lump-sum XP bonus to its linked
  /// stat, and checks for newly-unlocked achievements.
  Future<GoalCompletionResult> completeGoal(String goalId) async {
    final goal = storage.getGoal(goalId);
    if (goal == null || goal.status != GoalStatus.active) {
      return const GoalCompletionResult(
        levelUp: LevelUpResult(levelsGained: 0, newLevel: 0),
        newAchievements: [],
      );
    }

    goal.status = GoalStatus.completed;
    goal.completedAt = DateTime.now();
    await storage.saveGoal(goal);
    reload();

    final levelUp = await ref.read(statsProvider.notifier).applyXp(
          goal.statId,
          XpService.goalCompletionBonusXp,
        );

    final stats = storage.getStats();
    final completedQuests = storage.getQuests().where((q) => q.status == QuestStatus.completed).toList();
    final context = AchievementContext(
      stats: stats,
      completedQuests: completedQuests,
      streak: StatsInsightsService.currentStreak(completedQuests),
      overallLevel: XpService.overallLevel(stats),
      goals: storage.getGoals(),
    );
    final newAchievements = await ref.read(achievementServiceProvider).checkAndUnlock(context);
    if (newAchievements.isNotEmpty) {
      ref.read(unlockedAchievementsProvider.notifier).reload();
    }

    return GoalCompletionResult(levelUp: levelUp, newAchievements: newAchievements);
  }

  /// Called after a transaction contributes to a financial goal's amount.
  /// Completes the goal if its target has been reached.
  Future<GoalCompletionResult?> checkFinancialGoalCompletion(String goalId) async {
    final goal = storage.getGoal(goalId);
    if (goal == null || goal.status != GoalStatus.active) return null;
    if (goal.targetAmount == null || goal.currentAmount < goal.targetAmount!) return null;
    return completeGoal(goalId);
  }
}
