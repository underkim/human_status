import '../data/achievement_definitions.dart';
import '../models/quest.dart';
import 'stats_insights_service.dart';
import 'storage_service.dart';
import 'xp_service.dart';

class AchievementService {
  final StorageService storage;

  AchievementService({required this.storage});

  /// 현재 저장소 상태로 업적 판정 컨텍스트를 만든다 — 퀘스트 완료·목표
  /// 완료·목표 생성 등 체크 지점마다 같은 조립 코드를 반복하지 않도록.
  AchievementContext currentContext() {
    final stats = storage.getStats();
    final completedQuests =
        storage.getQuests().where((q) => q.status == QuestStatus.completed).toList();
    return AchievementContext(
      stats: stats,
      completedQuests: completedQuests,
      streak: StatsInsightsService.currentStreak(completedQuests),
      overallLevel: XpService.overallLevel(stats),
      goals: storage.getGoals(),
    );
  }

  /// Evaluates every achievement definition against [context] and persists
  /// any that are newly met. Returns the definitions that were unlocked by
  /// this call (empty if none), so the caller can show a celebration.
  Future<List<AchievementDefinition>> checkAndUnlock(AchievementContext context) async {
    final unlocked = storage.getUnlockedAchievements();
    final newlyUnlocked = <AchievementDefinition>[];

    for (final def in achievementDefinitions) {
      if (unlocked.containsKey(def.id)) continue;
      if (def.isUnlocked(context)) {
        await storage.unlockAchievement(def.id, DateTime.now());
        newlyUnlocked.add(def);
      }
    }
    return newlyUnlocked;
  }
}
