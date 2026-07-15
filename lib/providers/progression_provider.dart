import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/achievement_definitions.dart';
import '../services/achievement_progress_service.dart';
import '../services/progression_service.dart';
import 'goal_provider.dart';
import 'profile_provider.dart';
import 'quest_provider.dart';

/// The instant "now" is evaluated at for every progression calculation.
/// Like any Riverpod [Provider], the value this computes is cached until
/// invalidated — it does NOT call [DateTime.now] again on every read, so a
/// session left open across midnight would otherwise keep reporting
/// yesterday's snapshot forever. `HumanStatusApp` invalidates this provider
/// whenever the app resumes from the background (alongside
/// `DailyRefreshController.refreshIfDue`, see main.dart), which is enough to
/// pick up the new day without a timer of its own. Overridden with a fixed
/// value (or a mutable closure) in widget tests for determinism.
final nowProvider = Provider<DateTime>((ref) => DateTime.now());

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
