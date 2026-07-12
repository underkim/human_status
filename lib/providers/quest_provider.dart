import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/achievement_definitions.dart';
import '../models/quest.dart';
import '../services/achievement_service.dart';
import '../services/quest_recommendation_service.dart';
import '../services/stats_insights_service.dart';
import '../services/storage_service.dart';
import '../services/xp_service.dart';
import 'goal_provider.dart';
import 'profile_provider.dart';

final recommendationServiceProvider = Provider<QuestRecommendationService>(
  (ref) => QuestRecommendationService(storage: ref.watch(storageServiceProvider)),
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

final questsProvider = StateNotifierProvider<QuestsNotifier, List<Quest>>((ref) {
  return QuestsNotifier(ref.watch(storageServiceProvider), ref);
});

final activeQuestsProvider = Provider<List<Quest>>((ref) {
  return ref.watch(questsProvider).where((q) => q.status == QuestStatus.active).toList();
});

final suggestedQuestsProvider = Provider<List<Quest>>((ref) {
  return ref.watch(questsProvider).where((q) => q.status == QuestStatus.suggested).toList();
});

final completedQuestsProvider = Provider<List<Quest>>((ref) {
  final quests = ref.watch(questsProvider).where((q) => q.status == QuestStatus.completed).toList();
  quests.sort((a, b) => (b.completedAt ?? b.createdAt).compareTo(a.completedAt ?? a.createdAt));
  return quests;
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
  Future<QuestCompletionResult> completeQuest(String id) async {
    final quest = storage.getQuests().firstWhere((q) => q.id == id);
    final statsNotifier = ref.read(statsProvider.notifier);
    final levelUps = <String, LevelUpResult>{};
    for (final entry in quest.statRewards.entries) {
      final xp = quest.goalId != null ? XpService.applyGoalMultiplier(entry.value) : entry.value;
      levelUps[entry.key] = await statsNotifier.applyXp(entry.key, xp);
    }

    quest.status = QuestStatus.completed;
    quest.completedAt = DateTime.now();
    await storage.saveQuest(quest);
    reload();

    GoalCompletionResult? goalCompletion;
    if (quest.goalId != null) {
      final goal = storage.getGoal(quest.goalId!);
      final goalService = ref.read(goalServiceProvider);
      if (goal != null && goalService.isAutoCompletable(goal, storage.getQuests())) {
        goalCompletion = await ref.read(goalsProvider.notifier).completeGoal(goal.id);
      }
    }

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
    final allNewAchievements = <AchievementDefinition>[
      ...(goalCompletion?.newAchievements ?? const []),
      ...newAchievements,
    ];
    if (newAchievements.isNotEmpty) {
      ref.read(unlockedAchievementsProvider.notifier).reload();
    }

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
