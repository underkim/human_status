import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/achievement_definitions.dart';
import '../services/achievement_progress_service.dart';
import '../services/progression_service.dart';
import 'clock_provider.dart';
import 'goal_provider.dart';
import 'profile_provider.dart';
import 'quest_provider.dart';

export 'clock_provider.dart';

/// Reactive [ProgressionSnapshot] — rebuilds whenever quests change (a
/// completion, an edit, a deletion) or [nowProvider] moves.
final progressionSnapshotProvider = Provider<ProgressionSnapshot>((ref) {
  final quests = ref.watch(questsProvider);
  final now = ref.watch(nowProvider);
  return computeProgressionSnapshot(quests, now: now);
});

/// The locked achievement the user is closest to unlocking next, or null
/// once every measurable achievement is unlocked. Shares the exact streak
/// value used elsewhere in the app so this can never disagree with the
/// current-streak display.
final nextAchievementProgressProvider = Provider<NextAchievementProgress?>((
  ref,
) {
  final stats = ref.watch(statsProvider);
  final completedQuests = ref.watch(completedQuestsProvider);
  final goals = ref.watch(goalsProvider);
  final unlocked = ref.watch(unlockedAchievementsProvider);
  final streak = ref.watch(progressionSnapshotProvider).currentStreak;
  final overallLevel = ref.watch(overallLevelProvider);

  final ctx = AchievementContext(
    stats: stats,
    completedQuests: completedQuests,
    streak: streak,
    overallLevel: overallLevel,
    goals: goals,
  );
  return computeNextAchievementProgress(ctx, unlocked.keys.toSet());
});
