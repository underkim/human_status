import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/achievement_definitions.dart';
import '../models/quest.dart';
import '../services/achievement_service.dart';
import '../services/daily_summary_service.dart';
import '../services/quest_priority_service.dart';
import '../services/quest_recommendation_service.dart';
import '../services/reward_transaction.dart';
import '../services/storage_service.dart';
import '../services/xp_service.dart';
import 'clock_provider.dart';
import 'goal_provider.dart';
import 'profile_provider.dart';

final recommendationServiceProvider = Provider<QuestRecommendationService>(
  (ref) =>
      QuestRecommendationService(storage: ref.watch(storageServiceProvider)),
);

final achievementServiceProvider = Provider<AchievementService>(
  (ref) => AchievementService(storage: ref.watch(storageServiceProvider)),
);

/// Thrown by [QuestsNotifier.addQuest] when a record with the same id
/// already exists in storage (e.g. two concurrent creates for the same
/// stable draft id). Nothing is persisted when this is thrown — the
/// existing record is never silently overwritten.
class QuestAlreadyExistsException implements Exception {
  final String questId;
  const QuestAlreadyExistsException(this.questId);

  @override
  String toString() =>
      'QuestAlreadyExistsException: quest $questId already exists';
}

/// Thrown by [QuestsNotifier.updateQuest] when [questId] no longer exists
/// in storage (e.g. deleted by a concurrent call or a stale UI reference).
/// Nothing is persisted when this is thrown.
class QuestNotFoundException implements Exception {
  final String questId;
  const QuestNotFoundException(this.questId);

  @override
  String toString() => 'QuestNotFoundException: quest $questId not found';
}

class QuestCompletionResult {
  final Map<String, LevelUpResult> levelUps;
  final List<AchievementDefinition> newAchievements;
  final GoalCompletionResult? goalCompletion;

  const QuestCompletionResult({
    required this.levelUps,
    required this.newAchievements,
    this.goalCompletion,
  });
}

final questsProvider = StateNotifierProvider<QuestsNotifier, List<Quest>>((
  ref,
) {
  return QuestsNotifier(ref.watch(storageServiceProvider), ref);
});

final activeQuestsProvider = Provider<List<Quest>>((ref) {
  return ref
      .watch(questsProvider)
      .where((q) => q.status == QuestStatus.active)
      .toList();
});

final suggestedQuestsProvider = Provider<List<Quest>>((ref) {
  return ref
      .watch(questsProvider)
      .where((q) => q.status == QuestStatus.suggested)
      .toList();
});

final completedQuestsProvider = Provider<List<Quest>>((ref) {
  final quests = ref
      .watch(questsProvider)
      .where((q) => q.status == QuestStatus.completed)
      .toList();
  quests.sort(
    (a, b) =>
        (b.completedAt ?? b.createdAt).compareTo(a.completedAt ?? a.createdAt),
  );
  return quests;
});

/// 홈 허브에 강조할 단 하나의 "다음 퀘스트" — 규칙은 [selectNextQuest] 참고.
final nextQuestProvider = Provider<Quest?>((ref) {
  return selectNextQuest(ref.watch(activeQuestsProvider));
});

/// 오늘(로컬 달력 기준) 완료 개수와 실지급 XP 합계 — 홈 허브 요약에 쓰인다.
final todaySummaryProvider = Provider<DailySummary>((ref) {
  return computeTodaySummary(ref.watch(questsProvider));
});

class QuestsNotifier extends StateNotifier<List<Quest>> {
  final StorageService storage;
  final Ref ref;

  QuestsNotifier(this.storage, this.ref) : super(storage.getQuests());

  void reload() => state = storage.getQuests();

  /// Creates [quest] as a brand-new record. Takes an unconditional defensive
  /// copy before writing, so a caller that keeps its own reference (e.g. a
  /// form's local `Quest` built from user input) can never have that
  /// reference silently mutated later by something else touching the stored
  /// record.
  ///
  /// Runs inside [rewardLockProvider] so two concurrent creates for the same
  /// id (e.g. a stable draft id resubmitted before the first call's outcome
  /// is observed) can never both write — whichever acquires the lock first
  /// wins; if a record with [quest.id] already exists by the time this one
  /// runs, it throws [QuestAlreadyExistsException] instead of silently
  /// overwriting it. Registers a rollback *before* the save, so a failure
  /// detected only after the write actually landed (e.g. a follow-up
  /// integrity check) removes the just-created record and reloads — a retry
  /// after a genuine failure creates exactly one quest.
  Future<void> addQuest(Quest quest) {
    return ref.read(rewardLockProvider).synchronized(() async {
      if (storage.getQuest(quest.id) != null) {
        throw QuestAlreadyExistsException(quest.id);
      }

      final rollback = RollbackScope();
      rollback.addUndo(() async {
        await storage.deleteQuest(quest.id);
        reload();
      });
      try {
        await storage.saveQuest(quest.copy());
        reload();
      } catch (_) {
        await rollback.rollback();
        rethrow;
      }
    });
  }

  /// Persists edits to an existing quest. [proposed] must be a detached
  /// copy (e.g. `existing.copy()` with only the edited fields changed) —
  /// never the live Hive-boxed quest — so a failed save can never leave the
  /// caller's in-memory instance half-edited. This re-derives the actual
  /// candidate from the *current* stored original plus [proposed]'s
  /// editable fields (title/description/statRewards/difficulty/
  /// isRecurring), ignoring any id/status/source/createdAt/completedAt/
  /// goalId on [proposed] — a stale caller reference (or an edit racing a
  /// concurrent completion) can never revert completed status, already-
  /// awarded XP history, or the quest's goal link.
  ///
  /// XP already awarded for a completed quest is not retroactively changed
  /// — this only rewrites the stored record.
  ///
  /// Runs inside [rewardLockProvider] (the same critical section as
  /// [completeQuest]) so this can never interleave with a concurrent
  /// completion of the same quest. Snapshots the stored original before any
  /// write and rolls back to it exactly on a one-shot failure — including a
  /// failure detected only after the write actually landed — so a retry
  /// after a genuine failure never leaves partial edits. Throws
  /// [QuestNotFoundException] (persisting nothing) if [proposed.id] no
  /// longer exists in storage.
  Future<void> updateQuest(Quest proposed) {
    return ref.read(rewardLockProvider).synchronized(() async {
      final original = storage.getQuest(proposed.id);
      if (original == null) throw QuestNotFoundException(proposed.id);

      final snapshot = original.copy();
      final rollback = RollbackScope();
      rollback.addUndo(() async {
        await storage.saveQuest(snapshot);
        reload();
      });

      final candidate = original.copy()
        ..title = proposed.title
        ..description = proposed.description
        ..statRewards = Map<String, double>.from(proposed.statRewards)
        ..difficulty = proposed.difficulty
        ..isRecurring = proposed.isRecurring;
      try {
        await storage.saveQuest(candidate);
        reload();
      } catch (_) {
        await rollback.rollback();
        rethrow;
      }
    });
  }

  /// Shared body for [deleteQuest]/[dismissSuggestion], assuming the caller
  /// already holds [rewardLockProvider]. Re-reads [id] from storage — inside
  /// the same lock acquisition, never a second one — and only proceeds if
  /// [shouldDelete] accepts its *current* status; this is what lets each
  /// caller apply its own precondition (see below) against whichever status
  /// actually won the race, instead of a stale one captured before the lock
  /// was acquired. Snapshots the stored quest as a detached copy before
  /// deletion so a one-shot failure detected only after the underlying
  /// delete actually landed (not merely a guard that stopped an unperformed
  /// delete) can restore it via a real save.
  Future<void> _deleteQuestLocked(
    String id, {
    required bool Function(QuestStatus status) shouldDelete,
  }) async {
    final quest = storage.getQuest(id);
    if (quest == null || !shouldDelete(quest.status)) return;

    final snapshot = quest.copy();
    final rollback = RollbackScope();
    rollback.addUndo(() async {
      await storage.saveQuest(snapshot);
      reload();
    });
    try {
      await storage.deleteQuest(id);
      reload();
    } catch (_) {
      await rollback.rollback();
      rethrow;
    }
  }

  /// Deletes [id] — the active-tab "delete" action, so [id] is normally
  /// active when tapped. Runs inside [rewardLockProvider] so this can never
  /// interleave with a concurrent completeQuest/updateQuest/adoptSuggestion
  /// on the same quest.
  ///
  /// If [id] no longer exists (already deleted, e.g. by a concurrent
  /// duplicate call that ran first while this one waited on the lock), this
  /// is a safe no-op. If a concurrent [completeQuest] won the lock first —
  /// this call was queued behind it — [id]'s *current* status (re-read
  /// inside this same lock acquisition) is now completed; deleting it would
  /// erase completed history and the XP it already awarded, so this is also
  /// a safe no-op rather than a delete. (The reverse order — this delete
  /// wins first — leaves nothing for the queued completeQuest to act on, so
  /// it already no-ops on its own; see [_completeQuestLocked].) Does not
  /// alter any linked goal semantics — a quest never needs to unlink
  /// anything on its own deletion (contrast [GoalsNotifier.deleteGoal],
  /// which unlinks its quests).
  Future<void> deleteQuest(String id) {
    return ref.read(rewardLockProvider).synchronized(
      () => _deleteQuestLocked(
        id,
        shouldDelete: (status) => status != QuestStatus.completed,
      ),
    );
  }

  /// Adopts a suggested quest, moving it from suggested to active. Builds a
  /// detached copy of the stored quest changing only `status` — the live
  /// Hive-boxed instance is never mutated directly.
  ///
  /// Runs inside [rewardLockProvider] so this can never interleave with a
  /// concurrent completeQuest/updateQuest/deleteQuest on the same quest — if
  /// [id] no longer exists, or is no longer [QuestStatus.suggested] (already
  /// adopted or dismissed by a concurrent call that ran first while this one
  /// waited on the lock), this is a safe no-op rather than overwriting
  /// whatever state won the race. Registers a rollback before the write so a
  /// one-shot after-write failure restores the stored suggested quest
  /// exactly.
  Future<void> adoptSuggestion(String id) {
    return ref.read(rewardLockProvider).synchronized(() async {
      final quest = storage.getQuest(id);
      if (quest == null || quest.status != QuestStatus.suggested) return;

      final snapshot = quest.copy();
      final rollback = RollbackScope();
      rollback.addUndo(() async {
        await storage.saveQuest(snapshot);
        reload();
      });

      final candidate = quest.copy()..status = QuestStatus.active;
      try {
        await storage.saveQuest(candidate);
        reload();
      } catch (_) {
        await rollback.rollback();
        rethrow;
      }
    });
  }

  /// Dismisses a suggested quest by deleting it outright — reuses
  /// [_deleteQuestLocked]'s snapshot/delete/rollback semantics, but with its
  /// own precondition: [id]'s *current* status (re-read inside this lock
  /// acquisition, not the stale status the caller observed before this call
  /// was queued) must still be [QuestStatus.suggested].
  ///
  /// This matters because [dismissSuggestion] previously aliased
  /// [deleteQuest] outright, which deletes by id regardless of status — if a
  /// concurrent [adoptSuggestion] won the lock first (suggested -> active)
  /// while this dismiss was queued behind it, the alias would go on to
  /// delete that now-*active* quest instead of safely no-op'ing. Runs inside
  /// [rewardLockProvider] (a single acquisition — no nested lock) so the
  /// status check and the delete/rollback happen atomically together.
  Future<void> dismissSuggestion(String id) {
    return ref.read(rewardLockProvider).synchronized(
      () => _deleteQuestLocked(
        id,
        shouldDelete: (status) => status == QuestStatus.suggested,
      ),
    );
  }

  /// Completes a quest, awarding XP to every stat it's linked to (with a
  /// bonus multiplier if the quest is linked to a Goal), then evaluates
  /// achievements and auto-completes the linked Goal if this was its last
  /// outstanding quest. Returns level-up results per stat plus any
  /// newly-unlocked achievements so the UI can show celebrations.
  ///
  /// Runs inside the shared [rewardLockProvider] critical section (see
  /// [GoalsNotifier.completeGoal]) so two concurrent calls for the same
  /// quest — e.g. the complete button tapped twice before the UI
  /// rebuilds — can never both observe it as active, and so this quest's
  /// linked-goal auto-completion can never interleave with a manual
  /// [GoalsNotifier.completeGoal] call on the same goal. If any stat write,
  /// quest/goal persistence, or achievement check fails, everything this
  /// call changed (stat levels/XP, quest status/completedAt, the linked
  /// goal's status/completedAt/XP/achievements if it was auto-completed, and
  /// any achievement newly unlocked during this call) is rolled back before
  /// the error is rethrown, so a retry after a genuine failure can never
  /// double-award.
  Future<QuestCompletionResult> completeQuest(String id) {
    return ref.read(rewardLockProvider).synchronized(() async {
      final rollback = RollbackScope();
      try {
        return await _completeQuestLocked(id, rollback);
      } catch (_) {
        await rollback.rollback();
        rethrow;
      }
    });
  }

  Future<QuestCompletionResult> _completeQuestLocked(
    String id,
    RollbackScope rollback,
  ) async {
    final matches = storage.getQuests().where((q) => q.id == id);
    final quest = matches.isNotEmpty ? matches.first : null;
    // 완료 버튼이 리빌드 전에 연타되면 같은 id로 두 번 들어온다 — 이미
    // 완료됐거나(또는 사라졌거나) 애초에 진행중이 아닌 퀘스트에는 XP를
    // 지급하지 않고 조용히 무시한다(추천·삭제 상태 퀘스트 방어 포함). 이
    // 잠금 안에서 storage를 다시 읽으므로, 동시에 들어온 두 번째 호출은
    // 첫 번째가 커밋한 completed 상태를 정확히 관찰한다.
    if (quest == null || quest.status != QuestStatus.active) {
      return const QuestCompletionResult(levelUps: {}, newAchievements: []);
    }

    // 이 트랜잭션 전체에서 쓸 "지금"을 여기서 딱 한 번 확정한다 — nowProvider
    // 는 다른 Provider와 마찬가지로 무효화 전까지 값을 캐시해 두므로, 앱을
    // 켜 둔 채 자정을 넘긴 뒤 resume 없이 바로 완료하더라도 캐시된 어제
    // 인스턴스가 아니라 실제 현재 시각이 잡히도록 먼저 invalidate한다.
    // completedAt에 DateTime.now()를 직접 쓰지 않는 이유: 성장 여정 스냅샷
    // (progressionSnapshotProvider)이 같은 nowProvider를 기준으로 "오늘"을
    // 판단하므로, 서로 다른 시계로 계산하면 방금 완료한 퀘스트가 "오늘"로
    // 집계되지 않는 분리가 생길 수 있다.
    ref.invalidate(nowProvider);
    final now = ref.read(nowProvider);

    final statsNotifier = ref.read(statsProvider.notifier);
    final levelUps = <String, LevelUpResult>{};
    for (final entry in XpService.effectiveRewards(quest).entries) {
      final statId = entry.key;
      final statBefore = storage.getStat(statId);
      if (statBefore != null) {
        final snapLevel = statBefore.level;
        final snapXp = statBefore.currentXp;
        rollback.addUndo(
          () => statsNotifier.restore(statId, snapLevel, snapXp),
        );
      }
      levelUps[statId] = await statsNotifier.applyXp(statId, entry.value);
    }

    final prevStatus = quest.status;
    final prevCompletedAt = quest.completedAt;
    rollback.addUndo(() async {
      quest.status = prevStatus;
      quest.completedAt = prevCompletedAt;
      await storage.saveQuest(quest);
      reload();
    });
    quest.status = QuestStatus.completed;
    quest.completedAt = now;
    await storage.saveQuest(quest);
    reload();

    GoalCompletionResult? goalCompletion;
    if (quest.goalId != null) {
      final goal = storage.getGoal(quest.goalId!);
      final goalService = ref.read(goalServiceProvider);
      if (goal != null &&
          goalService.isAutoCompletable(goal, storage.getQuests())) {
        goalCompletion = await ref
            .read(goalsProvider.notifier)
            .completeGoalLocked(goal.id, rollback);
      }
    }

    final unlockedBefore = storage.getUnlockedAchievements().keys.toSet();
    rollback.addUndo(() async {
      final addedIds = storage
          .getUnlockedAchievements()
          .keys
          .toSet()
          .difference(unlockedBefore);
      for (final aid in addedIds) {
        await storage.deleteUnlockedAchievement(aid);
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

    final allNewAchievements = <AchievementDefinition>[
      ...(goalCompletion?.newAchievements ?? const []),
      ...newAchievements,
    ];

    return QuestCompletionResult(
      levelUps: levelUps,
      newAchievements: allNewAchievements,
      goalCompletion: goalCompletion,
    );
  }

  Future<void> refreshSuggestions() async {
    await ref.read(recommendationServiceProvider).refreshIfNeeded();
    reload();
    ref.read(profileProvider.notifier).reload();
  }
}
