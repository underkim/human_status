import '../models/stat.dart';

class LevelUpResult {
  final int levelsGained;
  final int newLevel;

  const LevelUpResult({required this.levelsGained, required this.newLevel});

  bool get leveledUp => levelsGained > 0;
}

class XpService {
  static double xpToNextLevel(int level) => 100.0 * level;

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
