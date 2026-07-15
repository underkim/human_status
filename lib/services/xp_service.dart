import '../models/quest.dart';
import '../models/stat.dart';

class LevelUpResult {
  final int levelsGained;
  final int newLevel;

  const LevelUpResult({required this.levelsGained, required this.newLevel});

  bool get leveledUp => levelsGained > 0;
}

class XpService {
  static double xpToNextLevel(int level) => 100.0 * level;

  /// Quests linked to a Goal (via Quest.goalId) earn a bonus over regular
  /// quest XP, since they represent progress toward a larger, less frequent
  /// commitment rather than a routine task.
  static const double goalQuestXpMultiplier = 1.5;

  /// Lump-sum XP awarded to a Goal's linked stat when the goal itself is
  /// completed, on top of whatever XP its linked quests already earned.
  static const double goalCompletionBonusXp = 100.0;

  static double applyGoalMultiplier(double baseXp) => baseXp * goalQuestXpMultiplier;

  /// [quest]가 완료 시 실제로 지급하는 스텟별 XP — 목표 연결 퀘스트의 1.5배
  /// 보너스가 반영된 값. 지급(completeQuest)과 집계(통계·리포트)가 반드시
  /// 같은 값을 읽도록 여기 한 곳에서만 계산한다.
  static Map<String, double> effectiveRewards(Quest quest) => {
        for (final e in quest.statRewards.entries)
          e.key: quest.goalId != null ? applyGoalMultiplier(e.value) : e.value,
      };

  /// Adds [xpGained] to [stat], rolling over into level-ups as needed.
  /// Mutates [stat] in place and returns the result of the operation.
  static LevelUpResult applyXp(Stat stat, double xpGained) {
    if (xpGained <= 0) {
      return LevelUpResult(levelsGained: 0, newLevel: stat.level);
    }
    final startLevel = stat.level;
    stat.currentXp += xpGained;
    while (stat.currentXp >= xpToNextLevel(stat.level)) {
      stat.currentXp -= xpToNextLevel(stat.level);
      stat.level += 1;
    }
    return LevelUpResult(
      levelsGained: stat.level - startLevel,
      newLevel: stat.level,
    );
  }

  /// Overall character level derived from the average of all stat levels.
  static int overallLevel(List<Stat> stats) {
    if (stats.isEmpty) return 1;
    final sum = stats.fold<int>(0, (acc, s) => acc + s.level);
    return (sum / stats.length).floor();
  }

  static double progress(Stat stat) {
    final needed = xpToNextLevel(stat.level);
    if (needed <= 0) return 0;
    return (stat.currentXp / needed).clamp(0, 1).toDouble();
  }
}
