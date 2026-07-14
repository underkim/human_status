import '../models/goal.dart';
import '../models/transaction.dart';
import 'storage_service.dart';

/// 'YYYY-MM' key used to group transactions by calendar month.
String monthKeyOf(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}';

class MonthlySummary {
  final double income;
  final double expense;

  const MonthlySummary({required this.income, required this.expense});

  double get net => income - expense;
}

class FinanceService {
  final StorageService storage;

  FinanceService({required this.storage});

  static MonthlySummary summarize(List<Transaction> transactions, String monthKey) {
    final inMonth = transactions.where((t) => monthKeyOf(t.date) == monthKey);
    final income = inMonth
        .where((t) => t.type == TransactionType.income)
        .fold(0.0, (a, t) => a + t.amount);
    final expense = inMonth
        .where((t) => t.type == TransactionType.expense)
        .fold(0.0, (a, t) => a + t.amount);
    return MonthlySummary(income: income, expense: expense);
  }

  /// 최근 [months]개월(기준 달 포함)의 월별 지출 합계를 과거→현재 순으로.
  /// 거래가 없는 달도 0으로 채워 추이 축이 끊기지 않게 한다.
  static Map<String, double> monthlyExpenses(
    List<Transaction> transactions, {
    DateTime? now,
    int months = 6,
  }) {
    final anchor = now ?? DateTime.now();
    final result = <String, double>{};
    for (var i = months - 1; i >= 0; i--) {
      result[monthKeyOf(DateTime(anchor.year, anchor.month - i))] = 0;
    }
    for (final t in transactions) {
      if (t.type != TransactionType.expense) continue;
      final key = monthKeyOf(t.date);
      if (result.containsKey(key)) result[key] = result[key]! + t.amount;
    }
    return result;
  }

  /// [monthKey]에 해당하는 지출을 카테고리별로 합산해, 금액 내림차순으로
  /// 정렬된 맵을 돌려준다 — "이번 달 돈이 어디로 갔는지" 분석용.
  static Map<String, double> expenseByCategory(List<Transaction> transactions, String monthKey) {
    final totals = <String, double>{};
    for (final t in transactions) {
      if (t.type != TransactionType.expense || monthKeyOf(t.date) != monthKey) continue;
      totals[t.category] = (totals[t.category] ?? 0) + t.amount;
    }
    final sorted = totals.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return {for (final e in sorted) e.key: e.value};
  }

  /// Saves [tx]. If it's linked to a financial goal (targetAmount set), the
  /// linked goal's currentAmount is adjusted (income adds, expense
  /// subtracts) and the updated Goal is returned so the caller can check for
  /// completion. Returns null when unlinked or the linked goal isn't
  /// financial.
  Future<Goal?> addTransaction(Transaction tx) async {
    await storage.saveTransaction(tx);
    if (tx.linkedGoalId == null) return null;

    final goal = storage.getGoal(tx.linkedGoalId!);
    if (goal == null || goal.targetAmount == null) return null;

    goal.currentAmount += tx.type == TransactionType.expense ? -tx.amount : tx.amount;
    await storage.saveGoal(goal);
    return goal;
  }

  /// Deletes [id], reverting its contribution to a linked financial goal's
  /// currentAmount (the mirror of addTransaction's adjustment) so deleting
  /// a mistaken entry doesn't leave phantom progress. Returns the adjusted
  /// goal, or null when the transaction was unlinked or already gone.
  Future<Goal?> deleteTransaction(String id) async {
    final matches = storage.getTransactions().where((t) => t.id == id);
    final tx = matches.isNotEmpty ? matches.first : null;
    await storage.deleteTransaction(id);
    if (tx == null || tx.linkedGoalId == null) return null;

    final goal = storage.getGoal(tx.linkedGoalId!);
    if (goal == null || goal.targetAmount == null) return null;

    goal.currentAmount -= tx.type == TransactionType.expense ? -tx.amount : tx.amount;
    await storage.saveGoal(goal);
    return goal;
  }

  /// Bulk-persists imported transactions. Imported rows never carry a
  /// linkedGoalId, so there's no goal-amount adjustment to do here.
  Future<void> importTransactions(List<Transaction> transactions) =>
      storage.saveTransactions(transactions);
}
