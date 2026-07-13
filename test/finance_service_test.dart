import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:human_status/models/goal.dart';
import 'package:human_status/models/transaction.dart';
import 'package:human_status/services/finance_service.dart';
import 'package:human_status/services/storage_service.dart';
import 'package:uuid/uuid.dart';

Transaction _tx({
  required TransactionType type,
  required double amount,
  DateTime? date,
  String? linkedGoalId,
  String category = 'test',
}) {
  return Transaction(
    id: const Uuid().v4(),
    type: type,
    category: category,
    memo: '',
    amount: amount,
    date: date ?? DateTime(2026, 7, 1),
    linkedGoalId: linkedGoalId,
    createdAt: DateTime.now(),
  );
}

void main() {
  group('FinanceService.summarize', () {
    test('sums income and expense within the target month only', () {
      final txs = [
        _tx(type: TransactionType.income, amount: 100, date: DateTime(2026, 7, 1)),
        _tx(type: TransactionType.income, amount: 50, date: DateTime(2026, 7, 15)),
        _tx(type: TransactionType.expense, amount: 30, date: DateTime(2026, 7, 20)),
        _tx(type: TransactionType.expense, amount: 999, date: DateTime(2026, 6, 30)), // outside month
      ];

      final summary = FinanceService.summarize(txs, monthKeyOf(DateTime(2026, 7, 10)));

      expect(summary.income, 150);
      expect(summary.expense, 30);
      expect(summary.net, 120);
    });

    test('returns zero for a month with no matching transactions', () {
      final summary = FinanceService.summarize([], '2026-01');
      expect(summary.income, 0);
      expect(summary.expense, 0);
      expect(summary.net, 0);
    });
  });

  group('FinanceService.expenseByCategory', () {
    test('sums per category, sorted by amount descending', () {
      final txs = [
        _tx(type: TransactionType.expense, amount: 30, category: '식비'),
        _tx(type: TransactionType.expense, amount: 70, category: '식비'),
        _tx(type: TransactionType.expense, amount: 200, category: '주거'),
        _tx(type: TransactionType.expense, amount: 50, category: '교통'),
      ];

      final result = FinanceService.expenseByCategory(txs, '2026-07');

      expect(result.keys.toList(), ['주거', '식비', '교통']);
      expect(result['식비'], 100);
      expect(result['주거'], 200);
    });

    test('ignores income and transactions outside the month', () {
      final txs = [
        _tx(type: TransactionType.income, amount: 1000, category: '급여'),
        _tx(type: TransactionType.expense, amount: 40, category: '식비', date: DateTime(2026, 6, 30)),
        _tx(type: TransactionType.expense, amount: 10, category: '식비'),
      ];

      final result = FinanceService.expenseByCategory(txs, '2026-07');

      expect(result, {'식비': 10});
    });

    test('is empty when there are no expenses in the month', () {
      expect(FinanceService.expenseByCategory([], '2026-07'), isEmpty);
    });
  });

  group('FinanceService.monthlyExpenses', () {
    test('covers the last N months in past-to-present order, zero-filling empty months', () {
      final txs = [
        _tx(type: TransactionType.expense, amount: 100, date: DateTime(2026, 7, 5)),
        _tx(type: TransactionType.expense, amount: 40, date: DateTime(2026, 5, 20)),
        _tx(type: TransactionType.income, amount: 999, date: DateTime(2026, 6, 1)), // 수입은 제외
        _tx(type: TransactionType.expense, amount: 7, date: DateTime(2025, 12, 31)), // 범위 밖
      ];

      final result = FinanceService.monthlyExpenses(txs, now: DateTime(2026, 7, 14));

      expect(result.keys.toList(), ['2026-02', '2026-03', '2026-04', '2026-05', '2026-06', '2026-07']);
      expect(result['2026-05'], 40);
      expect(result['2026-06'], 0);
      expect(result['2026-07'], 100);
    });

    test('handles a window crossing a year boundary', () {
      final result = FinanceService.monthlyExpenses([], now: DateTime(2026, 2, 1));
      expect(result.keys.toList(), ['2025-09', '2025-10', '2025-11', '2025-12', '2026-01', '2026-02']);
    });
  });

  group('FinanceService.addTransaction', () {
    late Directory tempDir;
    late StorageService storage;
    late FinanceService service;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('human_status_finance_test_');
      Hive.init(tempDir.path);
      if (!Hive.isAdapterRegistered(3)) Hive.registerAdapter(GoalAdapter());
      if (!Hive.isAdapterRegistered(4)) Hive.registerAdapter(TransactionAdapter());

      storage = StorageService();
      final suffix = DateTime.now().microsecondsSinceEpoch;
      storage.goalsBox = await Hive.openBox<Goal>('goals_$suffix');
      storage.transactionsBox = await Hive.openBox<Transaction>('transactions_$suffix');
      service = FinanceService(storage: storage);
    });

    tearDown(() async {
      await storage.goalsBox.close();
      await storage.transactionsBox.close();
      await tempDir.delete(recursive: true);
    });

    Goal financialGoal({double target = 100, double current = 0}) => Goal(
          id: 'g1',
          title: 'save',
          description: '',
          statId: 'wealth',
          targetAmount: target,
          currentAmount: current,
          createdAt: DateTime.now(),
        );

    test('income adds to the linked financial goal amount', () async {
      final goal = financialGoal(current: 20);
      await storage.saveGoal(goal);

      final updated = await service.addTransaction(
        _tx(type: TransactionType.income, amount: 30, linkedGoalId: goal.id),
      );

      expect(updated, isNotNull);
      expect(updated!.currentAmount, 50);
      expect(storage.getGoal(goal.id)!.currentAmount, 50);
    });

    test('expense subtracts from the linked financial goal amount', () async {
      final goal = financialGoal(current: 50);
      await storage.saveGoal(goal);

      final updated = await service.addTransaction(
        _tx(type: TransactionType.expense, amount: 20, linkedGoalId: goal.id),
      );

      expect(updated!.currentAmount, 30);
    });

    test('returns null and touches no goal when unlinked', () async {
      final result = await service.addTransaction(
        _tx(type: TransactionType.income, amount: 10),
      );
      expect(result, isNull);
    });

    test('returns null when the linked goal is not a financial goal', () async {
      final goal = Goal(
        id: 'g2',
        title: 'non-financial',
        description: '',
        statId: 'health',
        createdAt: DateTime.now(),
      );
      await storage.saveGoal(goal);

      final result = await service.addTransaction(
        _tx(type: TransactionType.income, amount: 10, linkedGoalId: goal.id),
      );
      expect(result, isNull);
    });
  });
}
