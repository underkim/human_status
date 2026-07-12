import '../data/achievement_definitions.dart';
import 'storage_service.dart';

class AchievementService {
  final StorageService storage;

  AchievementService({required this.storage});

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
