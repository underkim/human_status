import 'dart:math';

import '../models/financial_plan.dart';
import 'finance_service.dart';
import 'storage_service.dart';

class PlanRecommendation {
  final String goalTitle;
  final String statId;
  final double requiredTargetAmount;
  final double requiredMonthlySaving;
  final double currentAverageMonthlySaving;
  final DateTime targetDate;
  final double currentAmount;

  const PlanRecommendation({
    required this.goalTitle,
    required this.statId,
    required this.requiredTargetAmount,
    required this.requiredMonthlySaving,
    required this.currentAverageMonthlySaving,
    required this.targetDate,
    required this.currentAmount,
  });

  bool get isOnTrack => requiredMonthlySaving <= 0
      ? true
      : currentAverageMonthlySaving >= requiredMonthlySaving;
}

/// Turns a FinancialPlan's inputs into concrete monthly-saving
/// recommendations. Deliberately stays at the level of "how much to save
/// per month" arithmetic using the user's own assumed return rate — never
/// recommends specific investment products, which would cross into
/// regulated investment-advisory territory (same boundary already
/// established for FinancialAdvisorService).
class FinancialPlanningService {
  /// The commonly cited "4% rule": annual expenses x 25 is a widely-known
  /// rule of thumb for the nest egg needed to sustain that spending level
  /// indefinitely — not personalized advice.
  static double requiredRetirementFund(double monthlyLivingCost) =>
      monthlyLivingCost * 12 * 25;

  /// Required monthly saving to reach [targetAmount] in [months] months,
  /// starting from [currentAmount] and compounding monthly at
  /// [annualReturnPercent] (the user's own assumption). Uses the standard
  /// future-value-of-an-annuity formula solved for payment:
  ///   PMT = (FV - PV*(1+r)^n) / (((1+r)^n - 1) / r)
  /// Falls back to simple division when the rate is 0 (avoids /0), and
  /// uses the raw shortfall when [months] isn't positive. Never returns a
  /// negative number — 이미 목표를 넘겼으면 "월 -12,000원 필요" 대신 0원. Also never
  /// returns NaN/Infinity: an extreme (but user-enterable) rate/horizon
  /// combination can overflow the compounding math to a non-finite value
  /// well before the sign check below, which would otherwise reach the UI
  /// as a crash (formatWon() calls round(), which throws on NaN/Infinity).
  static double requiredMonthlySaving({
    required double targetAmount,
    required double currentAmount,
    required int months,
    required double annualReturnPercent,
  }) {
    final double raw;
    if (months <= 0) {
      raw = targetAmount - currentAmount;
    } else {
      final monthlyRate = annualReturnPercent / 100 / 12;
      if (monthlyRate == 0) {
        raw = (targetAmount - currentAmount) / months;
      } else {
        final growthFactor = pow(1 + monthlyRate, months).toDouble();
        final futureValueOfCurrent = currentAmount * growthFactor;
        final annuityFactor = (growthFactor - 1) / monthlyRate;
        raw = (targetAmount - futureValueOfCurrent) / annuityFactor;
      }
    }
    if (!raw.isFinite) return 0;
    return raw < 0 ? 0 : raw;
  }

  /// Average net (income - expense) over the last [months] calendar months,
  /// used as the "current pace" to compare a plan's required saving against.
  static double recentAverageMonthlySaving(
    StorageService storage, {
    int months = 3,
  }) {
    final transactions = storage.getTransactions();
    final now = DateTime.now();
    var total = 0.0;
    for (var i = 0; i < months; i++) {
      final monthDate = DateTime(now.year, now.month - i);
      total += FinanceService.summarize(
        transactions,
        monthKeyOf(monthDate),
      ).net;
    }
    return total / months;
  }

  static int _monthsBetween(DateTime from, DateTime to) =>
      (to.year - from.year) * 12 + (to.month - from.month);

  List<PlanRecommendation> buildRecommendations(
    FinancialPlan plan,
    StorageService storage,
  ) {
    final recommendations = <PlanRecommendation>[];
    final avgSaving = recentAverageMonthlySaving(storage);
    final now = DateTime.now();

    final currentAge = plan.currentAge;
    final retirementAge = plan.retirementAge;
    final livingCost = plan.monthlyLivingCostAfterRetirement;
    if (plan.retirementEnabled &&
        currentAge != null &&
        retirementAge != null &&
        livingCost != null) {
      final months = (retirementAge - currentAge) * 12;
      final requiredFund = requiredRetirementFund(livingCost);
      recommendations.add(
        PlanRecommendation(
          goalTitle: '은퇴자금',
          statId: 'wealth',
          requiredTargetAmount: requiredFund,
          requiredMonthlySaving: requiredMonthlySaving(
            targetAmount: requiredFund,
            currentAmount: plan.retirementCurrentSavings,
            months: months,
            annualReturnPercent: plan.expectedAnnualReturnPercent,
          ),
          currentAverageMonthlySaving: avgSaving,
          targetDate: DateTime(
            now.year + (retirementAge - currentAge),
            now.month,
            now.day,
          ),
          currentAmount: plan.retirementCurrentSavings,
        ),
      );
    }

    final homeTargetDate = plan.homePurchaseTargetDate;
    final homeTargetAmount = plan.homePurchaseTargetAmount;
    if (plan.homePurchaseEnabled &&
        homeTargetDate != null &&
        homeTargetAmount != null) {
      final months = _monthsBetween(now, homeTargetDate);
      recommendations.add(
        PlanRecommendation(
          goalTitle: '주택구입자금',
          statId: 'wealth',
          requiredTargetAmount: homeTargetAmount,
          requiredMonthlySaving: requiredMonthlySaving(
            targetAmount: homeTargetAmount,
            currentAmount: plan.homePurchaseCurrentSaved,
            months: months,
            annualReturnPercent: plan.expectedAnnualReturnPercent,
          ),
          currentAverageMonthlySaving: avgSaving,
          targetDate: homeTargetDate,
          currentAmount: plan.homePurchaseCurrentSaved,
        ),
      );
    }

    return recommendations;
  }
}
