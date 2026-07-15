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
import 'goal_provider.dart';
import 'profile_provider.dart';

final recommendationServiceProvider = Provider<QuestRecommendationService>(
  (ref) =>
      QuestRecommendationService(storage: ref.watch(storageServiceProvider)),
);

final achievementServiceProvider = Provider<AchievementService>(
  (ref) => AchievementService(storage: ref.watch(storageServiceProvider)),
);

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

  Future<void> addQuest(Quest quest) async {
    await storage.saveQuest(quest);
    reload();
  }

  /// Persists edits to an existing quest (title/description/rewards/etc.).
  /// XP already awarded for a completed quest is not retroactively changed —
  /// this only rewrites the stored record.
  Future<void> updateQuest(Quest quest) async {
    await storage.saveQuest(quest);
    reload();
  }

  Future<void> deleteQuest(String id) async {
    await storage.deleteQuest(id);
    reload();
  }

  Future<void> adoptSuggestion(String id) async {
    final quest = storage.getQuests().firstWhere((q) => q.id == id);
    quest.status = QuestStatus.active;
    await storage.saveQuest(quest);
    reload();
  }

  Future<void> dismissSuggestion(String id) async {
    await storage.deleteQuest(id);
    reload();
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
    quest.completedAt = DateTime.now();
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
