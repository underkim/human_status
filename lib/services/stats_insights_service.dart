import '../models/quest.dart';
import 'xp_service.dart';

class StatsInsightsService {
  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Adds [days] (may be negative) to a date-only [DateTime] using calendar
  /// fields rather than a fixed Duration, so it stays exactly at local
  /// midnight across DST transitions instead of drifting to 23:00/01:00.
  static DateTime _addDays(DateTime dateOnly, int days) =>
      DateTime(dateOnly.year, dateOnly.month, dateOnly.day + days);

  /// Consecutive days (ending today or yesterday) with at least one
  /// completed quest. If nothing was completed today, the streak is still
  /// considered "alive" as long as yesterday had a completion.
  static int currentStreak(List<Quest> completedQuests) {
    final dates = completedQuests
        .where((q) => q.completedAt != null)
        .map((q) => _dateOnly(q.completedAt!))
        .toSet();
    if (dates.isEmpty) return 0;

    var cursor = _dateOnly(DateTime.now());
    if (!dates.contains(cursor)) {
      cursor = _addDays(cursor, -1);
      if (!dates.contains(cursor)) return 0;
    }

    var streak = 0;
    while (dates.contains(cursor)) {
      streak++;
      cursor = _addDays(cursor, -1);
    }
    return streak;
  }

  /// Total XP (summed across all stats) earned per calendar day for the
  /// last [days] days, oldest first. Days with no completions are 0.
  static Map<DateTime, double> xpByDay(List<Quest> completedQuests, {int days = 7}) {
    final today = _dateOnly(DateTime.now());
    final result = <DateTime, double>{
      for (var i = days - 1; i >= 0; i--) _addDays(today, -i): 0.0,
    };

    for (final q in completedQuests) {
      if (q.completedAt == null) continue;
      final day = _dateOnly(q.completedAt!);
      if (!result.containsKey(day)) continue;
      final xp = XpService.effectiveRewards(q).values.fold(0.0, (a, b) => a + b);
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
    final today = _dateOnly(now ?? DateTime.now());
    // 이번 주 일요일(주의 끝)까지 채운 뒤 weeks*7일 전 월요일부터 시작.
    final endOfWeek = _addDays(today, 7 - today.weekday); // 일요일
    final start = _addDays(endOfWeek, -(weeks * 7 - 1)); // 월요일

    final result = <DateTime, int>{};
    for (var d = start; !d.isAfter(endOfWeek); d = _addDays(d, 1)) {
      result[d] = 0;
    }
    for (final q in completedQuests) {
      if (q.completedAt == null) continue;
      final day = _dateOnly(q.completedAt!);
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
