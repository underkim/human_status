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

  Future<void> deleteTransaction(String id) => storage.deleteTransaction(id);

  /// Bulk-persists imported transactions. Imported rows never carry a
  /// linkedGoalId, so there's no goal-amount adjustment to do here.
  Future<void> importTransactions(List<Transaction> transactions) =>
      storage.saveTransactions(transactions);
}
