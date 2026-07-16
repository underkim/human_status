import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/goal.dart';
import '../models/transaction.dart';
import '../services/budget_service.dart';
import '../services/finance_service.dart';
import '../services/reward_transaction.dart';
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

/// Thrown by [TransactionsNotifier.addTransaction] when a transaction id
/// already exists in storage with different field values than the one being
/// added. An exact repeat of an already-applied add (same id, same fields —
/// e.g. a UI retry after a response was lost) is a safe no-op instead; only
/// a genuine id collision with different data is rejected, and rejected
/// before any write happens.
class DuplicateTransactionException implements Exception {
  final String id;
  const DuplicateTransactionException(this.id);

  @override
  String toString() =>
      'DuplicateTransactionException: transaction $id already exists with different data';
}

bool _sameTransactionPayload(Transaction a, Transaction b) =>
    a.type == b.type &&
    a.category == b.category &&
    a.memo == b.memo &&
    a.amount == b.amount &&
    a.date == b.date &&
    a.linkedGoalId == b.linkedGoalId &&
    a.createdAt == b.createdAt;

class TransactionsNotifier extends StateNotifier<List<Transaction>> {
  final StorageService storage;
  final Ref ref;

  TransactionsNotifier(this.storage, this.ref) : super(storage.getTransactions());

  void reload() => state = storage.getTransactions();

  /// Persists [tx] and, if it's linked to a financial goal, adjusts that
  /// goal's amount and completes it if the target is now reached — all as
  /// one atomic operation.
  ///
  /// Runs inside the shared [rewardLockProvider] critical section (see
  /// [GoalsNotifier.completeGoal]) so this can never interleave with a
  /// concurrent add/delete of the same or a different transaction, nor with
  /// a quest/goal completion touching the same goal. Undo state for the
  /// transaction write and any goal-amount adjustment is registered before
  /// each mutation runs; if this goal-completion pushes the goal over its
  /// target, [GoalsNotifier.completeGoalLocked] folds its own rollback steps
  /// (stat XP, achievements, goal status) into the same [RollbackScope]. Any
  /// failure rolls back everything this call changed and rethrows — a retry
  /// after a genuine failure can never double-adjust or double-award.
  ///
  /// Two concurrent adds of the same transaction id can never both mutate:
  /// the second (having queued behind the first on the lock) sees the
  /// already-persisted row. If its fields exactly match, it's a no-op
  /// success; if they differ, it's rejected via [DuplicateTransactionException]
  /// before touching anything.
  ///
  /// The budget-exceeded notification is intentionally outside the atomic
  /// commit (best-effort, see [_notifyIfBudgetJustExceeded]) — a notification
  /// failure must never roll back an otherwise-successful transaction.
  Future<void> addTransaction(Transaction tx) async {
    final spentBefore = _currentMonthExpense();
    await ref.read(rewardLockProvider).synchronized(() async {
      final rollback = RollbackScope();
      try {
        await _addTransactionLocked(tx, rollback);
      } catch (_) {
        await rollback.rollback();
        rethrow;
      }
    });
    reload();
    ref.read(goalsProvider.notifier).reload();
    await _notifyIfBudgetJustExceeded(spentBefore);
  }

  Future<void> _addTransactionLocked(Transaction tx, RollbackScope rollback) async {
    final existing = storage.getTransactions().where((t) => t.id == tx.id);
    if (existing.isNotEmpty) {
      if (_sameTransactionPayload(existing.first, tx)) return;
      throw DuplicateTransactionException(tx.id);
    }

    Goal? goal;
    if (tx.linkedGoalId != null) {
      final candidate = storage.getGoal(tx.linkedGoalId!);
      if (candidate != null && candidate.targetAmount != null) goal = candidate;
    }
    final prevAmount = goal?.currentAmount;
    rollback.addUndo(() async {
      await storage.deleteTransaction(tx.id);
      reload();
      if (goal != null) {
        goal.currentAmount = prevAmount!;
        await storage.saveGoal(goal);
        ref.read(goalsProvider.notifier).reload();
      }
    });

    final linkedGoal = await ref.read(financeServiceProvider).addTransaction(tx);
    if (linkedGoal == null) return;
    ref.read(goalsProvider.notifier).reload();

    if (linkedGoal.status == GoalStatus.active && linkedGoal.currentAmount >= linkedGoal.targetAmount!) {
      await ref.read(goalsProvider.notifier).completeGoalLocked(linkedGoal.id, rollback);
    }
  }

  /// Deletes [id] and, if it was linked to a financial goal, reverts its
  /// contribution to that goal's amount (reopening the goal if the deletion
  /// drops it below target) — atomically, under the same critical section
  /// and rollback guarantees as [addTransaction]. Deleting a transaction
  /// that already doesn't exist (e.g. a retried delete) is a no-op.
  ///
  /// Reopening a goal this way never refunds its completion bonus: see
  /// [Goal.completionRewardClaimed].
  Future<void> deleteTransaction(String id) async {
    await ref.read(rewardLockProvider).synchronized(() async {
      final rollback = RollbackScope();
      try {
        await _deleteTransactionLocked(id, rollback);
      } catch (_) {
        await rollback.rollback();
        rethrow;
      }
    });
    reload();
    ref.read(goalsProvider.notifier).reload();
  }

  Future<void> _deleteTransactionLocked(String id, RollbackScope rollback) async {
    final matches = storage.getTransactions().where((t) => t.id == id);
    final tx = matches.isNotEmpty ? matches.first : null;
    if (tx == null) return;

    Goal? goal;
    if (tx.linkedGoalId != null) {
      final candidate = storage.getGoal(tx.linkedGoalId!);
      if (candidate != null && candidate.targetAmount != null) goal = candidate;
    }
    final prevAmount = goal?.currentAmount;
    final prevStatus = goal?.status;
    final prevCompletedAt = goal?.completedAt;
    rollback.addUndo(() async {
      await storage.saveTransaction(tx);
      reload();
      if (goal != null) {
        goal.currentAmount = prevAmount!;
        goal.status = prevStatus!;
        goal.completedAt = prevCompletedAt;
        await storage.saveGoal(goal);
        ref.read(goalsProvider.notifier).reload();
      }
    });

    final adjustedGoal = await ref.read(financeServiceProvider).deleteTransaction(id);
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
