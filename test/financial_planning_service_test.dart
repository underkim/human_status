import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:human_status/models/financial_plan.dart';
import 'package:human_status/models/transaction.dart';
import 'package:human_status/services/financial_planning_service.dart';
import 'package:human_status/services/storage_service.dart';
import 'package:uuid/uuid.dart';

void main() {
  group('FinancialPlanningService.requiredRetirementFund', () {
    test('is 300x monthly living cost (the 4% rule / 25x annual expenses)', () {
      expect(FinancialPlanningService.requiredRetirementFund(1000), 300000);
    });
  });

  group('FinancialPlanningService.requiredMonthlySaving', () {
    test('falls back to simple division when the rate is 0', () {
      final result = FinancialPlanningService.requiredMonthlySaving(
        targetAmount: 12000,
        currentAmount: 2000,
        months: 10,
        annualReturnPercent: 0,
      );
      expect(result, (12000 - 2000) / 10);
    });

    test('returns the raw shortfall when months is not positive', () {
      final result = FinancialPlanningService.requiredMonthlySaving(
        targetAmount: 10000,
        currentAmount: 3000,
        months: 0,
        annualReturnPercent: 5,
      );
      expect(result, 7000);
    });

    test(
      'the computed monthly payment actually reaches the target when simulated forward',
      () {
        const targetAmount = 100000.0;
        const currentAmount = 10000.0;
        const months = 24;
        const annualReturnPercent = 6.0;

        final pmt = FinancialPlanningService.requiredMonthlySaving(
          targetAmount: targetAmount,
          currentAmount: currentAmount,
          months: months,
          annualReturnPercent: annualReturnPercent,
        );

        final monthlyRate = annualReturnPercent / 100 / 12;
        var balance = currentAmount;
        for (var i = 0; i < months; i++) {
          balance = balance * (1 + monthlyRate) + pmt;
        }

        expect(balance, closeTo(targetAmount, 0.01));
      },
    );

    test('never goes negative when the target is already reached', () {
      final overfunded = FinancialPlanningService.requiredMonthlySaving(
        targetAmount: 10000,
        currentAmount: 50000,
        months: 12,
        annualReturnPercent: 5,
      );
      expect(overfunded, 0);

      final overfundedNoHorizon =
          FinancialPlanningService.requiredMonthlySaving(
            targetAmount: 10000,
            currentAmount: 50000,
            months: 0,
            annualReturnPercent: 5,
          );
      expect(overfundedNoHorizon, 0);
    });

    test(
      'returns 0 instead of NaN when an extreme return rate overflows compounding to infinity',
      () {
        // monthlyRate ~= 833,333: (1+monthlyRate)^months overflows a double to
        // Infinity well before the sign check, and 0 * Infinity is NaN — a
        // user can reach this by typing an unrealistic return rate with the
        // "이미 모아둔 금액" field left at its default of 0.
        final result = FinancialPlanningService.requiredMonthlySaving(
          targetAmount: 100000,
          currentAmount: 0,
          months: 1000,
          annualReturnPercent: 999999999,
        );
        expect(result, 0);
        expect(result.isFinite, isTrue);
      },
    );

    test(
      'returns 0 instead of infinity when an extreme return rate overflows compounding with a nonzero current amount',
      () {
        final result = FinancialPlanningService.requiredMonthlySaving(
          targetAmount: 100000,
          currentAmount: 500,
          months: 1000,
          annualReturnPercent: 999999999,
        );
        expect(result, 0);
        expect(result.isFinite, isTrue);
      },
    );
  });

  group('FinancialPlanningService storage-backed methods', () {
    late Directory tempDir;
    late StorageService storage;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp(
        'human_status_planning_test_',
      );
      Hive.init(tempDir.path);
      if (!Hive.isAdapterRegistered(4)) {
        Hive.registerAdapter(TransactionAdapter());
      }

      storage = StorageService();
      storage.transactionsBox = await Hive.openBox<Transaction>(
        'tx_${DateTime.now().microsecondsSinceEpoch}',
      );
    });

    tearDown(() async {
      await storage.transactionsBox.close();
      await tempDir.delete(recursive: true);
    });

    Transaction tx({
      required TransactionType type,
      required double amount,
      required DateTime date,
    }) => Transaction(
      id: const Uuid().v4(),
      type: type,
      category: 'test',
      memo: '',
      amount: amount,
      date: date,
      createdAt: DateTime.now(),
    );

    test(
      'recentAverageMonthlySaving averages net income-expense over the last N months',
      () async {
        final now = DateTime.now();
        await storage.saveTransaction(
          tx(type: TransactionType.income, amount: 1000, date: now),
        );
        await storage.saveTransaction(
          tx(type: TransactionType.expense, amount: 400, date: now),
        );

        final lastMonth = DateTime(now.year, now.month - 1, 15);
        await storage.saveTransaction(
          tx(type: TransactionType.income, amount: 500, date: lastMonth),
        );
        await storage.saveTransaction(
          tx(type: TransactionType.expense, amount: 300, date: lastMonth),
        );

        final twoMonthsAgo = DateTime(now.year, now.month - 2, 15);
        await storage.saveTransaction(
          tx(type: TransactionType.expense, amount: 100, date: twoMonthsAgo),
        );

        final avg = FinancialPlanningService.recentAverageMonthlySaving(
          storage,
          months: 3,
        );

        expect(avg, closeTo((600 + 200 - 100) / 3, 0.001));
      },
    );

    test('buildRecommendations includes retirement when enabled', () {
      final plan = FinancialPlan(
        updatedAt: DateTime.now(),
        retirementEnabled: true,
        currentAge: 30,
        retirementAge: 40,
        monthlyLivingCostAfterRetirement: 1000,
      );

      final recs = FinancialPlanningService().buildRecommendations(
        plan,
        storage,
      );

      expect(recs, hasLength(1));
      expect(recs.first.goalTitle, '은퇴자금');
      expect(recs.first.requiredTargetAmount, 300000);
    });

    test('buildRecommendations includes both goals when both are enabled', () {
      final now = DateTime.now();
      final plan = FinancialPlan(
        updatedAt: now,
        retirementEnabled: true,
        currentAge: 30,
        retirementAge: 31,
        monthlyLivingCostAfterRetirement: 100,
        homePurchaseEnabled: true,
        homePurchaseTargetDate: DateTime(now.year + 2, now.month),
        homePurchaseTargetAmount: 50000,
      );

      final recs = FinancialPlanningService().buildRecommendations(
        plan,
        storage,
      );

      expect(recs, hasLength(2));
      expect(recs.map((r) => r.goalTitle), containsAll(['은퇴자금', '주택구입자금']));
    });

    test('buildRecommendations is empty when neither goal is enabled', () {
      final plan = FinancialPlan(updatedAt: DateTime.now());
      final recs = FinancialPlanningService().buildRecommendations(
        plan,
        storage,
      );
      expect(recs, isEmpty);
    });
  });

  group('FinancialPlan JSON round-trip (backup/restore)', () {
    test('preserves every field through toJson/fromJson', () {
      final plan = FinancialPlan(
        updatedAt: DateTime(2026, 7, 14, 10, 30),
        expectedAnnualReturnPercent: 4.5,
        retirementEnabled: true,
        currentAge: 30,
        retirementAge: 60,
        monthlyLivingCostAfterRetirement: 2500000,
        retirementCurrentSavings: 10000000,
        homePurchaseEnabled: true,
        homePurchaseTargetDate: DateTime(2030, 3, 1),
        homePurchaseTargetAmount: 500000000,
        homePurchaseCurrentSaved: 80000000,
      );

      final restored = FinancialPlan.fromJson(plan.toJson());

      expect(restored.updatedAt, plan.updatedAt);
      expect(
        restored.expectedAnnualReturnPercent,
        plan.expectedAnnualReturnPercent,
      );
      expect(restored.retirementEnabled, plan.retirementEnabled);
      expect(restored.currentAge, plan.currentAge);
      expect(restored.retirementAge, plan.retirementAge);
      expect(
        restored.monthlyLivingCostAfterRetirement,
        plan.monthlyLivingCostAfterRetirement,
      );
      expect(restored.retirementCurrentSavings, plan.retirementCurrentSavings);
      expect(restored.homePurchaseEnabled, plan.homePurchaseEnabled);
      expect(restored.homePurchaseTargetDate, plan.homePurchaseTargetDate);
      expect(restored.homePurchaseTargetAmount, plan.homePurchaseTargetAmount);
      expect(restored.homePurchaseCurrentSaved, plan.homePurchaseCurrentSaved);
    });

    test('round-trips null optionals on a default plan', () {
      final plan = FinancialPlan(updatedAt: DateTime(2026, 7, 14));
      final restored = FinancialPlan.fromJson(plan.toJson());
      expect(restored.currentAge, isNull);
      expect(restored.homePurchaseTargetDate, isNull);
      expect(restored.retirementEnabled, isFalse);
      expect(restored.homePurchaseCurrentSaved, 0);
    });
  });

  group('PlanRecommendation.isOnTrack', () {
    test('is true when current average saving meets the requirement', () {
      final rec = PlanRecommendation(
        goalTitle: 'x',
        statId: 'wealth',
        requiredTargetAmount: 1000,
        requiredMonthlySaving: 100,
        currentAverageMonthlySaving: 100,
        targetDate: DateTime(2030, 1, 1),
        currentAmount: 0,
      );
      expect(rec.isOnTrack, isTrue);
    });

    test('is false when behind the required pace', () {
      final rec = PlanRecommendation(
        goalTitle: 'x',
        statId: 'wealth',
        requiredTargetAmount: 1000,
        requiredMonthlySaving: 100,
        currentAverageMonthlySaving: 50,
        targetDate: DateTime(2030, 1, 1),
        currentAmount: 0,
      );
      expect(rec.isOnTrack, isFalse);
    });

    test(
      'is true when the target is already fully funded (required saving is 0) even if recent cashflow is negative',
      () {
        final rec = PlanRecommendation(
          goalTitle: 'x',
          statId: 'wealth',
          requiredTargetAmount: 1000,
          requiredMonthlySaving: 0,
          currentAverageMonthlySaving: -50,
          targetDate: DateTime(2030, 1, 1),
          currentAmount: 1000,
        );
        expect(rec.isOnTrack, isTrue);
      },
    );

    test(
      'is false when a positive required saving is compared against negative recent cashflow',
      () {
        final rec = PlanRecommendation(
          goalTitle: 'x',
          statId: 'wealth',
          requiredTargetAmount: 1000,
          requiredMonthlySaving: 100,
          currentAverageMonthlySaving: -50,
          targetDate: DateTime(2030, 1, 1),
          currentAmount: 0,
        );
        expect(rec.isOnTrack, isFalse);
      },
    );
  });
}
