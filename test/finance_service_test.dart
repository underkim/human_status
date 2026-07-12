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
}) {
  return Transaction(
    id: const Uuid().v4(),
    type: type,
    category: 'test',
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
