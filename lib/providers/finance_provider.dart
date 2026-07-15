import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/transaction.dart';
import '../services/budget_service.dart';
import '../services/finance_service.dart';
import '../services/storage_service.dart';
import 'goal_provider.dart';
import 'profile_provider.dart';

final financeServiceProvider = Provider<FinanceService>(
  (ref) => FinanceService(storage: ref.watch(storageServiceProvider)),
);

final transactionsProvider = StateNotifierProvider<TransactionsNotifier, List<Transaction>>((ref) {
  return TransactionsNotifier(ref.watch(storageServiceProvider), ref);
});

final monthlySummaryProvider = Provider.family<MonthlySummary, String>((ref, monthKey) {
  final transactions = ref.watch(transactionsProvider);
  return FinanceService.summarize(transactions, monthKey);
});

class TransactionsNotifier extends StateNotifier<List<Transaction>> {
  final StorageService storage;
  final Ref ref;

  TransactionsNotifier(this.storage, this.ref) : super(storage.getTransactions());

  void reload() => state = storage.getTransactions();

  Future<void> addTransaction(Transaction tx) async {
    final spentBefore = _currentMonthExpense();
    final linkedGoal = await ref.read(financeServiceProvider).addTransaction(tx);
    reload();
    if (linkedGoal != null) {
      ref.read(goalsProvider.notifier).reload();
      await ref.read(goalsProvider.notifier).checkFinancialGoalCompletion(linkedGoal.id);
    }
    await _notifyIfBudgetJustExceeded(spentBefore);
  }

  Future<void> deleteTransaction(String id) async {
    final adjustedGoal = await ref.read(financeServiceProvider).deleteTransaction(id);
    reload();
    if (adjustedGoal != null) {
      ref.read(goalsProvider.notifier).reload();
    }
  }

  /// Bulk-imports transactions (e.g. from a CSV file). Unlike addTransaction,
  /// this skips the goal-linking check since imported rows never carry a
  /// linkedGoalId.
  Future<void> importTransactions(List<Transaction> transactions) async {
    final spentBefore = _currentMonthExpense();
    await ref.read(financeServiceProvider).importTransactions(transactions);
    reload();
    await _notifyIfBudgetJustExceeded(spentBefore);
  }

  double _currentMonthExpense() =>
      FinanceService.summarize(storage.getTransactions(), monthKeyOf(DateTime.now())).expense;

  /// 이번 저장으로 이번 달 지출이 예산을 '처음' 넘어섰을 때만 로컬 알림을
  /// 한 번 보낸다 — 이미 초과 상태에서의 추가 지출은 조용히 지나간다.
  Future<void> _notifyIfBudgetJustExceeded(double spentBefore) async {
    final budget = storage.getFinancialPlan().monthlyBudget;
    final spentAfter = _currentMonthExpense();
    if (!BudgetService.justExceeded(
        budget: budget, spentBefore: spentBefore, spentAfter: spentAfter)) {
      return;
    }
    try {
      await ref
          .read(notificationServiceProvider)
          .showBudgetExceeded(spent: spentAfter, budget: budget!);
    } catch (_) {
      // 알림 실패(권한/플랫폼)가 거래 저장을 실패로 만들면 안 된다.
    }
  }
}
