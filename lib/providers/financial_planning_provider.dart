import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../models/financial_plan.dart';
import '../models/goal.dart';
import '../services/financial_planning_service.dart';
import '../services/storage_service.dart';
import 'finance_provider.dart';
import 'goal_provider.dart';
import 'profile_provider.dart';

final financialPlanProvider =
    StateNotifierProvider<FinancialPlanNotifier, FinancialPlan>((ref) {
      return FinancialPlanNotifier(ref.watch(storageServiceProvider), ref);
    });

/// recentAverageMonthlySaving reads storage.getTransactions() directly
/// rather than through transactionsProvider, so this must watch it
/// explicitly — otherwise an add/delete/import leaves recommendations
/// (and isOnTrack) stale until something else happens to touch
/// financialPlanProvider.
final planRecommendationsProvider = Provider<List<PlanRecommendation>>((ref) {
  final plan = ref.watch(financialPlanProvider);
  final storage = ref.watch(storageServiceProvider);
  ref.watch(transactionsProvider);
  return FinancialPlanningService().buildRecommendations(plan, storage);
});

class FinancialPlanNotifier extends StateNotifier<FinancialPlan> {
  final StorageService storage;
  final Ref ref;

  FinancialPlanNotifier(this.storage, this.ref)
    : super(storage.getFinancialPlan());

  /// 플랜은 단일 레코드라 hive가 항상 같은 인스턴스를 돌려준다 — 제자리에서
  /// 수정된 뒤 reload()하면 old/new가 identical이라 기본 구현은 리스너에
  /// 알리지 않으므로, 무조건 알리도록 바꾼다.
  @override
  bool updateShouldNotify(FinancialPlan old, FinancialPlan current) => true;

  void reload() => state = storage.getFinancialPlan();

  Future<void> savePlan(FinancialPlan plan) async {
    await storage.saveFinancialPlan(plan);
    reload();
  }

  /// Creates an actual financial Goal from [rec] — reuses
  /// GoalsNotifier.createGoal so quest auto-decomposition and progress
  /// tracking work exactly like any other financial goal.
  Future<void> createGoalFrom(PlanRecommendation rec) async {
    final goal = Goal(
      id: const Uuid().v4(),
      title: rec.goalTitle,
      description: '장기 재무계획에서 생성된 목표예요.',
      statId: rec.statId,
      targetAmount: rec.requiredTargetAmount,
      currentAmount: rec.currentAmount,
      targetDate: rec.targetDate,
      createdAt: DateTime.now(),
    );
    await ref.read(goalsProvider.notifier).createGoal(goal);
  }
}
