import '../models/goal.dart';
import '../models/quest.dart';
import '../models/transaction.dart';

enum ReportPeriod { weekly, monthly }

/// Aggregated activity for one report period: [start] inclusive, [end]
/// exclusive, both at local midnight.
class PeriodReport {
  final DateTime start;
  final DateTime end;
  final int questsCompleted;
  final Map<String, double> xpByStat;
  final int goalsCompleted;
  final List<String> completedGoalTitles;
  final double income;
  final double expense;
  final String? topExpenseCategory;
  final double topExpenseAmount;

  const PeriodReport({
    required this.start,
    required this.end,
    required this.questsCompleted,
    required this.xpByStat,
    required this.goalsCompleted,
    required this.completedGoalTitles,
    required this.income,
    required this.expense,
    required this.topExpenseCategory,
    required this.topExpenseAmount,
  });

  double get xpEarned => xpByStat.values.fold(0.0, (a, b) => a + b);

  double get net => income - expense;

  /// Stat that gained the most XP this period, null when nothing was earned.
  String? get topStatId {
    String? top;
    var max = 0.0;
    xpByStat.forEach((statId, xp) {
      if (xp > max) {
        max = xp;
        top = statId;
      }
    });
    return top;
  }

  bool get isEmpty => questsCompleted == 0 && goalsCompleted == 0 && income == 0 && expense == 0;
}

/// Builds weekly/monthly summaries of quests, goals, and finances. Pure
/// functions over already-loaded lists — no storage access.
class ReportService {
  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  /// The [periodsAgo]-th period counting back from the one containing [now]
  /// (0 = current). Weeks start on Monday; months on the 1st. Uses calendar
  /// arithmetic so boundaries stay at local midnight across DST.
  static (DateTime, DateTime) periodRange(
    ReportPeriod period,
    DateTime now, {
    int periodsAgo = 0,
  }) {
    final today = _dateOnly(now);
    switch (period) {
      case ReportPeriod.weekly:
        final start = DateTime(
          today.year,
          today.month,
          today.day - (today.weekday - 1) - 7 * periodsAgo,
        );
        return (start, DateTime(start.year, start.month, start.day + 7));
      case ReportPeriod.monthly:
        final start = DateTime(today.year, today.month - periodsAgo, 1);
        return (start, DateTime(start.year, start.month + 1, 1));
    }
  }

  static bool _inRange(DateTime? d, DateTime start, DateTime end) =>
      d != null && !d.isBefore(start) && d.isBefore(end);

  static PeriodReport build({
    required List<Quest> quests,
    required List<Goal> goals,
    required List<Transaction> transactions,
    required DateTime start,
    required DateTime end,
  }) {
    final xpByStat = <String, double>{};
    var questsCompleted = 0;
    for (final q in quests) {
      if (q.status != QuestStatus.completed || !_inRange(q.completedAt, start, end)) continue;
      questsCompleted++;
      q.statRewards.forEach((statId, xp) {
        xpByStat[statId] = (xpByStat[statId] ?? 0) + xp;
      });
    }

    final completedGoalTitles = [
      for (final g in goals)
        if (g.status == GoalStatus.completed && _inRange(g.completedAt, start, end)) g.title,
    ];

    var income = 0.0;
    var expense = 0.0;
    final expenseByCategory = <String, double>{};
    for (final t in transactions) {
      if (!_inRange(t.date, start, end)) continue;
      if (t.type == TransactionType.income) {
        income += t.amount;
      } else {
        expense += t.amount;
        expenseByCategory[t.category] = (expenseByCategory[t.category] ?? 0) + t.amount;
      }
    }

    String? topExpenseCategory;
    var topExpenseAmount = 0.0;
    expenseByCategory.forEach((category, amount) {
      if (amount > topExpenseAmount) {
        topExpenseAmount = amount;
        topExpenseCategory = category;
      }
    });

    return PeriodReport(
      start: start,
      end: end,
      questsCompleted: questsCompleted,
      xpByStat: xpByStat,
      goalsCompleted: completedGoalTitles.length,
      completedGoalTitles: completedGoalTitles,
      income: income,
      expense: expense,
      topExpenseCategory: topExpenseCategory,
      topExpenseAmount: topExpenseAmount,
    );
  }
}
