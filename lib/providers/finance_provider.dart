import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/transaction.dart';
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
    final linkedGoal = await ref.read(financeServiceProvider).addTransaction(tx);
    reload();
    if (linkedGoal != null) {
      ref.read(goalsProvider.notifier).reload();
      await ref.read(goalsProvider.notifier).checkFinancialGoalCompletion(linkedGoal.id);
    }
  }

  Future<void> deleteTransaction(String id) async {
    await storage.deleteTransaction(id);
    reload();
  }

  /// Bulk-imports transactions (e.g. from a CSV file). Unlike addTransaction,
  /// this skips the goal-linking check since imported rows never carry a
  /// linkedGoalId.
  Future<void> importTransactions(List<Transaction> transactions) async {
    await ref.read(financeServiceProvider).importTransactions(transactions);
    reload();
  }
}
