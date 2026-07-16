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

const _liveQuestStatuses = {QuestStatus.active, QuestStatus.suggested};

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

/// Thrown by [GoalsNotifier.updateGoal]/[GoalsNotifier.deleteGoal] when
/// [goalId] no longer exists in storage (e.g. deleted by a concurrent call
/// or a stale UI reference). Nothing is persisted when this is thrown.
class GoalNotFoundException implements Exception {
  final String goalId;
  const GoalNotFoundException(this.goalId);

  @override
  String toString() => 'GoalNotFoundException: goal $goalId not found';
}

class GoalsNotifier extends StateNotifier<List<Goal>> {
  final StorageService storage;
  final Ref ref;

  GoalsNotifier(this.storage, this.ref) : super(storage.getGoals());

  void reload() => state = storage.getGoals();

  /// Persists edits to an existing goal (title/description/date/amount).
  /// [proposed] must be a detached copy (e.g. `existing.copy()` with the
  /// edited fields applied) — never the live Hive-boxed goal — so a failed
  /// save can never leave the caller's in-memory instance half-edited. This
  /// method re-derives the actual candidate from the *current* stored
  /// original plus [proposed]'s editable fields (title/description/
  /// targetDate/targetAmount), ignoring any immutable/progress/status/reward
  /// fields on [proposed]; a stale caller reference can never clobber
  /// concurrent progress.
  ///
  /// Does NOT re-run quest decomposition — that only happens at creation, so
  /// editing never spawns duplicate quests. If the edit lowers a financial
  /// goal's target to at or below its current amount, the goal is completed
  /// right away (returning the result so the UI can celebrate) — otherwise a
  /// financial goal has no manual complete button and would be stuck active.
  ///
  /// Runs inside [rewardLockProvider] (same critical section as
  /// [completeGoal]/[deleteGoal]) so an edit-triggered completion can never
  /// interleave with a concurrent completion or delete. If any step — the
  /// edit save, the completion's goal save, stat XP, or achievement check —
  /// fails, everything this call changed is rolled back (goal, stat,
  /// achievements, providers) before the error is rethrown. Throws
  /// [GoalNotFoundException] (persisting nothing) if [proposed.id] no longer
  /// exists in storage.
  Future<GoalCompletionResult?> updateGoal(Goal proposed) {
    return ref.read(rewardLockProvider).synchronized(() async {
      final rollback = RollbackScope();
      try {
        final original = storage.getGoal(proposed.id);
        if (original == null) throw GoalNotFoundException(proposed.id);

        final snapshot = original.copy();
        rollback.addUndo(() async {
          await storage.saveGoal(snapshot);
          reload();
        });

        final candidate = original.copy()
          ..title = proposed.title
          ..description = proposed.description
          ..targetDate = proposed.targetDate
          ..targetAmount = proposed.targetAmount;
        await storage.saveGoal(candidate);
        reload();

        final crossedFinancialTarget = candidate.targetAmount != null &&
            candidate.currentAmount >= candidate.targetAmount!;
        if (!crossedFinancialTarget) return null;
        return await completeGoalLocked(candidate.id, rollback);
      } catch (_) {
        await rollback.rollback();
        rethrow;
      }
    });
  }

  /// Deletes [goalId]. Any still-active or suggested quests generated for it
  /// are unlinked (goalId cleared) so they survive as ordinary quests instead
  /// of pointing at a goal that no longer exists; completed quests keep their
  /// link for history and for the bonus XP they already earned.
  ///
  /// Runs inside [rewardLockProvider] so this can never interleave with a
  /// concurrent [completeGoal]/[updateGoal] on the same goal. Every quest
  /// mutation and the goal itself are snapshotted as detached copies before
  /// any write, so a failure partway through (some quests already unlinked,
  /// or the final goal delete itself) restores every touched record exactly
  /// — a retry after a genuine failure can never leave partial/unlinked
  /// drift. If [goalId] no longer exists (already deleted, e.g. by a
  /// concurrent call that ran first while this one waited on the lock), this
  /// is a safe no-op.
  Future<void> deleteGoal(String goalId) {
    return ref.read(rewardLockProvider).synchronized(() async {
      final rollback = RollbackScope();
      try {
        final goal = storage.getGoal(goalId);
        if (goal == null) return;

        final goalSnapshot = goal.copy();
        rollback.addUndo(() async {
          await storage.saveGoal(goalSnapshot);
          reload();
        });

        final linkedQuests =
            storage.getQuests().where((q) => q.goalId == goalId).toList();
        for (final q in linkedQuests) {
          if (!_liveQuestStatuses.contains(q.status)) continue;
          final questSnapshot = q.copy();
          rollback.addUndo(() async {
            await storage.saveQuest(questSnapshot);
            ref.read(questsProvider.notifier).reload();
          });
          await storage.saveQuest(q.copy()..goalId = null);
        }

        await storage.deleteGoal(goalId);
        reload();
        ref.read(questsProvider.notifier).reload();
      } catch (_) {
        await rollback.rollback();
        rethrow;
      }
    });
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
  /// The completion XP bonus is lifetime-once per goal (see
  /// [Goal.completionRewardClaimed]): a financial goal that was completed,
  /// then reopened by deleting the contributing transaction, then completed
  /// again by a new one, transitions status back to completed here but is
  /// not paid the bonus (or re-checked for achievements) a second time.
  ///
  /// Runs inside the shared [rewardLockProvider] critical section so a
  /// concurrent [completeGoal] or [QuestsNotifier.completeQuest] call (e.g.
  /// this goal auto-completing via its last linked quest, racing a manual
  /// tap) can never interleave with this one — whichever acquires the lock
  /// first completes the goal; the other observes it already completed and
  /// no-ops. If any step fails, everything this call changed (goal
  /// status/completedAt/completionRewardClaimed, stat level/XP, any
  /// achievement newly unlocked during this call) is rolled back before the
  /// error is rethrown, so a retry after a genuine failure can never
  /// double-award.
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

    final alreadyClaimed = goal.completionRewardClaimed;
    final prevStatus = goal.status;
    final prevCompletedAt = goal.completedAt;
    final prevClaimed = goal.completionRewardClaimed;
    rollback.addUndo(() async {
      goal.status = prevStatus;
      goal.completedAt = prevCompletedAt;
      goal.completionRewardClaimed = prevClaimed;
      await storage.saveGoal(goal);
      reload();
    });
    goal.status = GoalStatus.completed;
    goal.completedAt = DateTime.now();
    goal.completionRewardClaimed = true;
    await storage.saveGoal(goal);
    reload();

    if (alreadyClaimed) {
      // Re-completing a goal whose bonus was already paid out (see the doc
      // comment above): status/completedAt still updates, but no second XP
      // bonus or achievement re-check runs.
      final stat = storage.getStat(goal.statId);
      return GoalCompletionResult(
        levelUp: LevelUpResult(levelsGained: 0, newLevel: stat?.level ?? 0),
        newAchievements: const [],
      );
    }

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
