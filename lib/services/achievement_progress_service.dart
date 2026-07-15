import '../data/achievement_definitions.dart';
import '../models/goal.dart';

/// A single achievement's measured progress toward completion. [ratio] is
/// always clamped to 0..1 so a stale or over-target value (e.g. currentXp
/// beyond a level threshold) never overshoots the progress bar.
class AchievementProgress {
  final double current;
  final double target;
  final String label;

  const AchievementProgress({
    required this.current,
    required this.target,
    required this.label,
  });

  double get ratio =>
      target <= 0 ? 0 : (current / target).clamp(0, 1).toDouble();
}

/// The locked achievement closest to completion, ready for display.
class NextAchievementProgress {
  final AchievementDefinition definition;
  final double current;
  final double target;
  final double ratio;
  final String label;

  const NextAchievementProgress({
    required this.definition,
    required this.current,
    required this.target,
    required this.ratio,
    required this.label,
  });

  String get title => definition.title;
  String get icon => definition.icon;
}

int _completedGoalsCount(AchievementContext ctx) =>
    ctx.goals.where((g) => g.status == GoalStatus.completed).length;

AchievementProgress _countProgress(int current, int target, String suffix) {
  final clamped = current > target ? target : current;
  return AchievementProgress(
    current: clamped.toDouble(),
    target: target.toDouble(),
    label: '$clamped/$target$suffix',
  );
}

AchievementProgress _levelProgress(int current, int target) {
  final clamped = current > target ? target : current;
  return AchievementProgress(
    current: clamped.toDouble(),
    target: target.toDouble(),
    label: 'Lv.$clamped/Lv.$target',
  );
}

/// Measures progress toward the achievement identified by [id], deriving
/// current/target from the exact same [AchievementContext] fields that
/// [AchievementDefinition.isUnlocked] reads — so a progress bar showing
/// "100%" and the achievement actually unlocking are never inconsistent.
/// Returns null for achievements with no meaningful measurable progress:
/// an unrecognized id, or `financial_goal_reached`, whose unlock predicate
/// requires a *completed* financial goal (see [AchievementDefinition] for
/// `financial_goal_reached`) — there is no continuous signal (an active
/// goal's amount ratio) that stays threshold-consistent with that
/// predicate, since an active goal at 100% of its target is not the same
/// as a completed one. Reporting a fabricated ratio here would risk a
/// progress bar reading 100% while the achievement itself never unlocks,
/// so this achievement is excluded from "next" selection entirely rather
/// than measured inconsistently.
AchievementProgress? measureAchievementProgress(
  String id,
  AchievementContext ctx,
) {
  switch (id) {
    case 'first_quest':
      return _countProgress(ctx.completedQuests.length, 1, '개 완료');
    case 'quests_10':
      return _countProgress(ctx.completedQuests.length, 10, '개 완료');
    case 'quests_50':
      return _countProgress(ctx.completedQuests.length, 50, '개 완료');
    case 'streak_3':
      return _countProgress(ctx.streak, 3, '일 연속');
    case 'streak_7':
      return _countProgress(ctx.streak, 7, '일 연속');
    case 'any_stat_lv5':
      final maxLevel = ctx.stats.isEmpty
          ? 0
          : ctx.stats.map((s) => s.level).reduce((a, b) => a > b ? a : b);
      return _levelProgress(maxLevel, 5);
    case 'all_stats_lv2':
      if (ctx.stats.isEmpty) return null;
      final minLevel = ctx.stats
          .map((s) => s.level)
          .reduce((a, b) => a < b ? a : b);
      return _levelProgress(minLevel, 2);
    case 'overall_lv5':
      return _levelProgress(ctx.overallLevel, 5);
    case 'first_goal_set':
      return _countProgress(ctx.goals.length, 1, '개');
    case 'first_goal_completed':
      return _countProgress(_completedGoalsCount(ctx), 1, '개 달성');
    case 'goals_completed_5':
      return _countProgress(_completedGoalsCount(ctx), 5, '개 달성');
    case 'financial_goal_reached':
      // Excluded — see the doc comment above for why no active-goal ratio
      // can be reported without contradicting isUnlocked's own threshold.
      return null;
    default:
      return null;
  }
}

/// The locked, measurable achievement with the highest clamped progress
/// ratio — the one the user is closest to unlocking next. Ties keep
/// whichever comes first in [achievementDefinitions]. Never marks or
/// unlocks anything; [AchievementService] remains the sole authority for
/// that. Returns null once every measurable achievement is unlocked (or
/// none can be measured, e.g. no stats/goals exist yet).
NextAchievementProgress? computeNextAchievementProgress(
  AchievementContext ctx,
  Set<String> unlockedIds,
) {
  NextAchievementProgress? best;
  for (final def in achievementDefinitions) {
    if (unlockedIds.contains(def.id)) continue;
    final progress = measureAchievementProgress(def.id, ctx);
    if (progress == null) continue;
    if (best == null || progress.ratio > best.ratio) {
      best = NextAchievementProgress(
        definition: def,
        current: progress.current,
        target: progress.target,
        ratio: progress.ratio,
        label: progress.label,
      );
    }
  }
  return best;
}
