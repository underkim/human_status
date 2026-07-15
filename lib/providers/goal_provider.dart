import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/achievement_definitions.dart';
import '../models/goal.dart';
import '../models/quest.dart';
import '../services/goal_service.dart';
import '../services/reward_transaction.dart';
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
  return ref
      .watch(goalsProvider)
      .where((g) => g.status == GoalStatus.active)
      .toList();
});

final completedGoalsProvider = Provider<List<Goal>>((ref) {
  final goals = ref
      .watch(goalsProvider)
      .where((g) => g.status == GoalStatus.completed)
      .toList();
  goals.sort(
    (a, b) =>
        (b.completedAt ?? b.createdAt).compareTo(a.completedAt ?? a.createdAt),
  );
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

  const GoalCompletionResult({
    required this.levelUp,
    required this.newAchievements,
  });
}

class GoalCreationResult {
  final List<Quest> quests;
  final List<AchievementDefinition> newAchievements;

  const GoalCreationResult({
    required this.quests,
    required this.newAchievements,
  });
}

/// Thrown by [GoalsNotifier.createGoal] when called with `requireQuests:
/// true` and decomposition produces no quests. Nothing is persisted when
/// this is thrown — see createGoal's doc comment.
class GoalRequiresQuestsException implements Exception {
  const GoalRequiresQuestsException();

  @override
  String toString() =>
      'GoalRequiresQuestsException: decomposition produced no quests';
}

class GoalsNotifier extends StateNotifier<List<Goal>> {
  final StorageService storage;
  final Ref ref;

  GoalsNotifier(this.storage, this.ref) : super(storage.getGoals());

  void reload() => state = storage.getGoals();

  /// Persists edits to an existing goal (title/description/date/amount).
  /// Does NOT re-run quest decomposition — that only happens at creation, so
  /// editing never spawns duplicate quests. If the edit lowers a financial
  /// goal's target to at or below its current amount, the goal is completed
  /// right away (returning the result so the UI can celebrate) — otherwise a
  /// financial goal has no manual complete button and would be stuck active.
  Future<GoalCompletionResult?> updateGoal(Goal goal) async {
    await storage.saveGoal(goal);
    reload();
    return checkFinancialGoalCompletion(goal.id);
  }

  /// Deletes [goalId]. Any still-active or suggested quests generated for it
  /// are unlinked (goalId cleared) so they survive as ordinary quests instead
  /// of pointing at a goal that no longer exists; completed quests keep their
  /// link for history and for the bonus XP they already earned.
  Future<void> deleteGoal(String goalId) async {
    for (final q in storage.getQuests()) {
      if (q.goalId != goalId) continue;
      if (q.status == QuestStatus.active || q.status == QuestStatus.suggested) {
        q.goalId = null;
        await storage.saveQuest(q);
      }
    }
    await storage.deleteGoal(goalId);
    reload();
    ref.read(questsProvider.notifier).reload();
  }

  /// Decomposes [goal] into quests (Claude if configured, else the local
  /// template fallback), then persists the goal and adds the quests via
  /// questsProvider so the quest list stays in sync automatically. Also
  /// evaluates achievements right away — '목표 설정' 같은 생성 기반 업적이
  /// 다음 완료 시점까지 밀리지 않도록. Returns the generated quests (may be
  /// empty if decomposition failed entirely) plus any newly-unlocked
  /// achievements.
  ///
  /// If [requireQuests] is true (used by onboarding's starter-goal flow,
  /// where a goal with no actionable quest would strand the user), a
  /// decomposition that yields zero quests throws
  /// [GoalRequiresQuestsException] instead of succeeding. Decomposition runs
  /// before anything is saved, so that case leaves storage untouched — a
  /// retry can never create a duplicate goal. If persisting the goal/quests
  /// or the achievement check throws for any other reason, everything this
  /// call had written (the goal, any quests already added, any achievements
  /// unlocked during this call) is rolled back before the error is
  /// rethrown, so a retry after a genuine failure doesn't duplicate either.
  /// Regular (non-onboarding) goal creation is unaffected: [requireQuests]
  /// defaults to false, so an empty decomposition still succeeds exactly as
  /// before.
  Future<GoalCreationResult> createGoal(
    Goal goal, {
    bool requireQuests = false,
  }) async {
    final quests = await ref.read(goalServiceProvider).decompose(goal);
    if (requireQuests && quests.isEmpty) {
      throw const GoalRequiresQuestsException();
    }

    final unlockedBefore = storage.getUnlockedAchievements().keys.toSet();
    final addedQuestIds = <String>[];
    try {
      await storage.saveGoal(goal);
      reload();

      for (final q in quests) {
        await ref.read(questsProvider.notifier).addQuest(q);
        addedQuestIds.add(q.id);
      }

      final achievementService = ref.read(achievementServiceProvider);
      final newAchievements = await achievementService.checkAndUnlock(
        achievementService.currentContext(),
      );
      if (newAchievements.isNotEmpty) {
        ref.read(unlockedAchievementsProvider.notifier).reload();
      }
      return GoalCreationResult(
        quests: quests,
        newAchievements: newAchievements,
      );
    } catch (_) {
      for (final id in addedQuestIds) {
        await storage.deleteQuest(id);
      }
      await storage.deleteGoal(goal.id);
      final unlockedAfter = storage.getUnlockedAchievements().keys.toSet();
      for (final id in unlockedAfter.difference(unlockedBefore)) {
        await storage.deleteUnlockedAchievement(id);
      }
      reload();
      ref.read(questsProvider.notifier).reload();
      ref.read(unlockedAchievementsProvider.notifier).reload();
      rethrow;
    }
  }

  /// Marks [goalId] completed, awards a lump-sum XP bonus to its linked
  /// stat, and checks for newly-unlocked achievements.
  ///
  /// Runs inside the shared [rewardLockProvider] critical section so a
  /// concurrent [completeGoal] or [QuestsNotifier.completeQuest] call (e.g.
  /// this goal auto-completing via its last linked quest, racing a manual
  /// tap) can never interleave with this one — whichever acquires the lock
  /// first completes the goal; the other observes it already completed and
  /// no-ops. If any step fails, everything this call changed (goal
  /// status/completedAt, stat level/XP, any achievement newly unlocked
  /// during this call) is rolled back before the error is rethrown, so a
  /// retry after a genuine failure can never double-award.
  Future<GoalCompletionResult> completeGoal(String goalId) {
    return ref.read(rewardLockProvider).synchronized(() async {
      final rollback = RollbackScope();
      try {
        return await completeGoalLocked(goalId, rollback);
      } catch (_) {
        await rollback.rollback();
        rethrow;
      }
    });
  }

  /// The actual goal-completion transaction, assuming the caller already
  /// holds [rewardLockProvider]. Exposed (not private) so
  /// [QuestsNotifier.completeQuest] can fold a linked goal's auto-completion
  /// into its own [RollbackScope] instead of nesting a second lock
  /// acquisition/rollback boundary — do not call this directly unless you
  /// are already inside a `rewardLockProvider.synchronized(...)` block.
  Future<GoalCompletionResult> completeGoalLocked(
    String goalId,
    RollbackScope rollback,
  ) async {
    final goal = storage.getGoal(goalId);
    if (goal == null || goal.status != GoalStatus.active) {
      return const GoalCompletionResult(
        levelUp: LevelUpResult(levelsGained: 0, newLevel: 0),
        newAchievements: [],
      );
    }

    final prevStatus = goal.status;
    final prevCompletedAt = goal.completedAt;
    rollback.addUndo(() async {
      goal.status = prevStatus;
      goal.completedAt = prevCompletedAt;
      await storage.saveGoal(goal);
      reload();
    });
    goal.status = GoalStatus.completed;
    goal.completedAt = DateTime.now();
    await storage.saveGoal(goal);
    reload();

    final statsNotifier = ref.read(statsProvider.notifier);
    final statBefore = storage.getStat(goal.statId);
    if (statBefore != null) {
      final snapLevel = statBefore.level;
      final snapXp = statBefore.currentXp;
      rollback.addUndo(
        () => statsNotifier.restore(goal.statId, snapLevel, snapXp),
      );
    }
    final levelUp = await statsNotifier.applyXp(
      goal.statId,
      XpService.goalCompletionBonusXp,
    );

    final unlockedBefore = storage.getUnlockedAchievements().keys.toSet();
    rollback.addUndo(() async {
      final addedIds = storage
          .getUnlockedAchievements()
          .keys
          .toSet()
          .difference(unlockedBefore);
      for (final id in addedIds) {
        await storage.deleteUnlockedAchievement(id);
      }
      ref.read(unlockedAchievementsProvider.notifier).reload();
    });
    final achievementService = ref.read(achievementServiceProvider);
    final newAchievements = await achievementService.checkAndUnlock(
      achievementService.currentContext(),
    );
    if (newAchievements.isNotEmpty) {
      ref.read(unlockedAchievementsProvider.notifier).reload();
    }

    return GoalCompletionResult(
      levelUp: levelUp,
      newAchievements: newAchievements,
    );
  }

  /// Called after a transaction contributes to a financial goal's amount.
  /// Completes the goal if its target has been reached.
  Future<GoalCompletionResult?> checkFinancialGoalCompletion(
    String goalId,
  ) async {
    final goal = storage.getGoal(goalId);
    if (goal == null || goal.status != GoalStatus.active) return null;
    if (goal.targetAmount == null || goal.currentAmount < goal.targetAmount!) {
      return null;
    }
    return completeGoal(goalId);
  }
}
