import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:human_status/models/financial_plan.dart';
import 'package:human_status/models/transaction.dart';
import 'package:human_status/providers/finance_provider.dart';
import 'package:human_status/providers/financial_planning_provider.dart';
import 'package:human_status/providers/profile_provider.dart';

import 'helpers/test_app.dart';

Transaction _tx(String id, TransactionType type, double amount, DateTime date) {
  return Transaction(
    id: id,
    type: type,
    category: '저축',
    memo: '',
    amount: amount,
    date: date,
    createdAt: date,
  );
}

void main() {
  test(
    'planRecommendationsProvider recomputes after a transaction is added, without resaving the plan',
    () async {
      final storage = await createTestStorage();
      final now = DateTime.now();
      await storage.saveFinancialPlan(
        FinancialPlan(
          updatedAt: now,
          homePurchaseEnabled: true,
          homePurchaseTargetDate: DateTime(now.year + 2, now.month),
          homePurchaseTargetAmount: 1000000,
        ),
      );

      final container = ProviderContainer(
        overrides: [storageServiceProvider.overrideWithValue(storage)],
      );
      addTearDown(container.dispose);

      final before = container.read(planRecommendationsProvider).single;
      expect(before.currentAverageMonthlySaving, 0);

      await container
          .read(transactionsProvider.notifier)
          .addTransaction(_tx('t1', TransactionType.income, 300000, now));

      final after = container.read(planRecommendationsProvider).single;
      expect(after.currentAverageMonthlySaving, greaterThan(0));
    },
  );

  test(
    'planRecommendationsProvider.isOnTrack flips after a saving transaction is deleted',
    () async {
      final storage = await createTestStorage();
      final now = DateTime.now();
      await storage.saveFinancialPlan(
        FinancialPlan(
          updatedAt: now,
          homePurchaseEnabled: true,
          homePurchaseTargetDate: DateTime(now.year + 5, now.month),
          homePurchaseTargetAmount: 120000,
        ),
      );

      final container = ProviderContainer(
        overrides: [storageServiceProvider.overrideWithValue(storage)],
      );
      addTearDown(container.dispose);

      final notifier = container.read(transactionsProvider.notifier);
      await notifier.addTransaction(
        _tx('t1', TransactionType.income, 500000, now),
      );

      final onTrack = container.read(planRecommendationsProvider).single;
      expect(onTrack.isOnTrack, isTrue);

      await notifier.deleteTransaction('t1');

      final offTrack = container.read(planRecommendationsProvider).single;
      expect(offTrack.isOnTrack, isFalse);
    },
  );

  test(
    'planRecommendationsProvider recomputes after a bulk transaction import',
    () async {
      final storage = await createTestStorage();
      final now = DateTime.now();
      await storage.saveFinancialPlan(
        FinancialPlan(
          updatedAt: now,
          homePurchaseEnabled: true,
          homePurchaseTargetDate: DateTime(now.year + 2, now.month),
          homePurchaseTargetAmount: 1000000,
        ),
      );

      final container = ProviderContainer(
        overrides: [storageServiceProvider.overrideWithValue(storage)],
      );
      addTearDown(container.dispose);

      final before = container.read(planRecommendationsProvider).single;
      expect(before.currentAverageMonthlySaving, 0);

      await container.read(transactionsProvider.notifier).importTransactions([
        _tx('t1', TransactionType.income, 400000, now),
      ]);

      final after = container.read(planRecommendationsProvider).single;
      expect(after.currentAverageMonthlySaving, greaterThan(0));
    },
  );
}
