import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:human_status/models/transaction.dart';
import 'package:human_status/providers/finance_provider.dart';
import 'package:human_status/providers/profile_provider.dart';
import 'package:human_status/services/notification_service.dart';

import 'helpers/test_app.dart';

class _FakeNotificationService extends NotificationService {
  final calls = <({double spent, double budget})>[];

  @override
  Future<void> showBudgetExceeded({required double spent, required double budget}) async {
    calls.add((spent: spent, budget: budget));
  }
}

Transaction _expense(String id, double amount) {
  final now = DateTime.now();
  return Transaction(
    id: id,
    type: TransactionType.expense,
    category: '식비',
    memo: '',
    amount: amount,
    date: now,
    createdAt: now,
  );
}

void main() {
  test('이번 달 지출이 예산을 처음 넘는 순간 한 번만 알림이 간다', () async {
    final storage = await createTestStorage();
    final plan = storage.getFinancialPlan();
    plan.monthlyBudget = 100000;
    await storage.saveFinancialPlan(plan);

    final fake = _FakeNotificationService();
    final container = ProviderContainer(overrides: [
      storageServiceProvider.overrideWithValue(storage),
      notificationServiceProvider.overrideWithValue(fake),
    ]);
    addTearDown(container.dispose);
    final notifier = container.read(transactionsProvider.notifier);

    // 예산 안: 알림 없음.
    await notifier.addTransaction(_expense('t1', 60000));
    expect(fake.calls, isEmpty);

    // 예산을 넘는 순간: 알림 1회.
    await notifier.addTransaction(_expense('t2', 50000));
    expect(fake.calls.length, 1);
    expect(fake.calls.single.spent, 110000);
    expect(fake.calls.single.budget, 100000);

    // 이미 초과 상태의 추가 지출: 반복 알림 없음.
    await notifier.addTransaction(_expense('t3', 10000));
    expect(fake.calls.length, 1);
  });

  test('가져오기(임포트)로 예산을 넘어도 알림이 간다', () async {
    final storage = await createTestStorage();
    final plan = storage.getFinancialPlan();
    plan.monthlyBudget = 100000;
    await storage.saveFinancialPlan(plan);

    final fake = _FakeNotificationService();
    final container = ProviderContainer(overrides: [
      storageServiceProvider.overrideWithValue(storage),
      notificationServiceProvider.overrideWithValue(fake),
    ]);
    addTearDown(container.dispose);

    await container.read(transactionsProvider.notifier).importTransactions([
      _expense('t1', 70000),
      _expense('t2', 80000),
    ]);

    expect(fake.calls.length, 1);
    expect(fake.calls.single.spent, 150000);
  });

  test('예산이 없으면 아무리 써도 알림이 없다', () async {
    final storage = await createTestStorage();
    final fake = _FakeNotificationService();
    final container = ProviderContainer(overrides: [
      storageServiceProvider.overrideWithValue(storage),
      notificationServiceProvider.overrideWithValue(fake),
    ]);
    addTearDown(container.dispose);

    await container.read(transactionsProvider.notifier).addTransaction(_expense('t1', 999999));
    expect(fake.calls, isEmpty);
  });
}
