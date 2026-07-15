import '../models/quest.dart';
import 'local_calendar.dart' as cal;
import 'xp_service.dart';

class StatsInsightsService {
  /// True when [q] is a genuinely valid completion as of [now]: actually
  /// [QuestStatus.completed] (not active/suggested/dismissed, even if a
  /// stale `completedAt` lingers on the record), has a `completedAt`, and
  /// that timestamp is not later than [now]. Every calendar-day calculation
  /// in this service funnels through this single check, so a caller that
  /// passes a raw/unfiltered quest list directly gets the same trustworthy
  /// semantics as one that pre-filtered through `completedQuestsProvider`.
  static bool _isValidCompletion(Quest q, DateTime now) =>
      q.status == QuestStatus.completed &&
      q.completedAt != null &&
      !q.completedAt!.isAfter(now);

  /// Consecutive days (ending today or yesterday) with at least one
  /// completed quest. If nothing was completed today, the streak is still
  /// considered "alive" as long as yesterday had a completion. A completion
  /// timestamped after [now] is ignored, so a clock-skewed or backdated
  /// record can never inflate the streak. [now] defaults to the wall clock;
  /// pass it explicitly to keep this deterministic in tests.
  static int currentStreak(List<Quest> completedQuests, {DateTime? now}) {
    final effectiveNow = now ?? DateTime.now();
    final dates = completedQuests
        .where((q) => _isValidCompletion(q, effectiveNow))
        .map((q) => cal.dateOnly(q.completedAt!))
        .toSet();
    if (dates.isEmpty) return 0;

    var cursor = cal.dateOnly(effectiveNow);
    if (!dates.contains(cursor)) {
      cursor = cal.addDays(cursor, -1);
      if (!dates.contains(cursor)) return 0;
    }

    var streak = 0;
    while (dates.contains(cursor)) {
      streak++;
      cursor = cal.addDays(cursor, -1);
    }
    return streak;
  }

  /// Total XP (summed across all stats) earned per calendar day for the
  /// last [days] days, oldest first. Days with no completions are 0. A
  /// completion timestamped later than [now] (even if it falls on today's
  /// calendar date) is excluded, so it can never inflate a total the user
  /// hasn't actually earned yet.
  static Map<DateTime, double> xpByDay(
    List<Quest> completedQuests, {
    int days = 7,
    DateTime? now,
  }) {
    final effectiveNow = now ?? DateTime.now();
    final today = cal.dateOnly(effectiveNow);
    final result = <DateTime, double>{
      for (var i = days - 1; i >= 0; i--) cal.addDays(today, -i): 0.0,
    };

    for (final q in completedQuests) {
      if (!_isValidCompletion(q, effectiveNow)) continue;
      final day = cal.dateOnly(q.completedAt!);
      if (!result.containsKey(day)) continue;
      final xp = XpService.effectiveRewards(
        q,
      ).values.fold(0.0, (a, b) => a + b);
      result[day] = result[day]! + xp;
    }
    return result;
  }

  /// Completed-quest count per day for the [weeks]-week window ending on the
  /// week that contains today, as full Monday→Sunday weeks (so a heatmap
  /// grid has no ragged edges). Ordered oldest day first; days with no
  /// completions are 0. The window always starts on a Monday and ends on the
  /// Sunday of the current week.
  static Map<DateTime, int> completionCountByDay(
    List<Quest> completedQuests, {
    DateTime? now,
    int weeks = 16,
  }) {
    final today = cal.dateOnly(now ?? DateTime.now());
    // 이번 주 일요일(주의 끝)까지 채운 뒤 weeks*7일 전 월요일부터 시작.
    final endOfWeek = cal.addDays(today, 7 - today.weekday); // 일요일
    final start = cal.addDays(endOfWeek, -(weeks * 7 - 1)); // 월요일

    final result = <DateTime, int>{};
    for (var d = start; !d.isAfter(endOfWeek); d = cal.addDays(d, 1)) {
      result[d] = 0;
    }
    for (final q in completedQuests) {
      if (q.completedAt == null) continue;
      final day = cal.dateOnly(q.completedAt!);
      if (result.containsKey(day)) result[day] = result[day]! + 1;
    }
    return result;
  }

  /// Total XP ever earned per stat, summed across all completed quests.
  /// Uses effectiveRewards so goal-linked quests count their 1.5x bonus,
  /// matching what applyXp actually credited.
  static Map<String, double> totalXpByStat(List<Quest> completedQuests) {
    final result = <String, double>{};
    for (final q in completedQuests) {
      XpService.effectiveRewards(q).forEach((statId, xp) {
        result[statId] = (result[statId] ?? 0) + xp;
      });
    }
    return result;
  }
}
