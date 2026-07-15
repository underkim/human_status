import '../models/quest.dart';
import 'local_calendar.dart' as cal;

/// A snapshot of the user's long-term progression, derived purely from
/// completed quests as of an (injectable) instant — no persistence, no
/// currencies, no schema of its own. Feeds the dashboard's "성장 여정" card
/// and the top of InsightsScreen so both read the exact same numbers.
class ProgressionSnapshot {
  /// Consecutive local-calendar days (ending today or yesterday) with at
  /// least one valid completion. Zero once a day has been missed.
  final int currentStreak;

  /// The longest such run ever observed, all-time.
  final int longestStreak;

  /// Unique active days from this week's Monday through [now], inclusive.
  /// Always 0..7.
  final int activeDaysThisWeek;

  /// Whether at least one quest was validly completed on [now]'s calendar
  /// day — lets the UI distinguish "today already secured" from "streak is
  /// alive only because of yesterday".
  final bool completedToday;

  const ProgressionSnapshot({
    required this.currentStreak,
    required this.longestStreak,
    required this.activeDaysThisWeek,
    required this.completedToday,
  });

  static const empty = ProgressionSnapshot(
    currentStreak: 0,
    longestStreak: 0,
    activeDaysThisWeek: 0,
    completedToday: false,
  );
}

/// Unique local-calendar days with at least one valid completion. Only
/// [QuestStatus.completed] quests with a non-null completedAt at or before
/// [now] count — active/suggested/dismissed quests, future timestamps, and
/// repeated completions on the same day (deduped by the Set) are excluded.
Set<DateTime> _validCompletionDays(List<Quest> quests, DateTime now) {
  final days = <DateTime>{};
  for (final q in quests) {
    if (q.status != QuestStatus.completed) continue;
    final completedAt = q.completedAt;
    if (completedAt == null) continue;
    if (completedAt.isAfter(now)) continue;
    days.add(cal.dateOnly(completedAt));
  }
  return days;
}

int _currentStreak(Set<DateTime> days, DateTime today) {
  if (days.isEmpty) return 0;

  var cursor = today;
  if (!days.contains(cursor)) {
    cursor = cal.addDays(cursor, -1);
    if (!days.contains(cursor)) return 0;
  }

  var streak = 0;
  while (days.contains(cursor)) {
    streak++;
    cursor = cal.addDays(cursor, -1);
  }
  return streak;
}

int _longestStreak(Set<DateTime> days) {
  if (days.isEmpty) return 0;

  final sorted = days.toList()..sort();
  var longest = 1;
  var run = 1;
  for (var i = 1; i < sorted.length; i++) {
    if (sorted[i] == cal.addDays(sorted[i - 1], 1)) {
      run++;
    } else {
      run = 1;
    }
    if (run > longest) longest = run;
  }
  return longest;
}

int _activeDaysThisWeek(Set<DateTime> days, DateTime today) {
  final monday = cal.startOfWeek(today);
  var count = 0;
  for (var d = monday; !d.isAfter(today); d = cal.addDays(d, 1)) {
    if (days.contains(d)) count++;
  }
  return count;
}

/// Computes a [ProgressionSnapshot] from [quests] as of [now] (defaults to
/// the wall clock; inject an explicit value in tests/providers for
/// determinism).
ProgressionSnapshot computeProgressionSnapshot(
  List<Quest> quests, {
  DateTime? now,
}) {
  final effectiveNow = now ?? DateTime.now();
  final today = cal.dateOnly(effectiveNow);
  final days = _validCompletionDays(quests, effectiveNow);

  return ProgressionSnapshot(
    currentStreak: _currentStreak(days, today),
    longestStreak: _longestStreak(days),
    activeDaysThisWeek: _activeDaysThisWeek(days, today),
    completedToday: days.contains(today),
  );
}
