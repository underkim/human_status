import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:human_status/models/goal.dart';
import 'package:human_status/models/transaction.dart';
import 'package:human_status/providers/finance_provider.dart';
import 'package:human_status/providers/profile_provider.dart';

import 'helpers/test_app.dart';

Transaction _tx(String id, TransactionType type, double amount, {String? goalId}) {
  final now = DateTime.now();
  return Transaction(
    id: id,
    type: type,
    category: '저축',
    memo: '',
    amount: amount,
    date: now,
    linkedGoalId: goalId,
    createdAt: now,
  );
}

void main() {
  test('목표 연결 거래를 삭제하면 기여한 금액이 되돌아간다', () async {
    final storage = await createTestStorage();
    await storage.saveGoal(Goal(
      id: 'g1',
      title: '비상금 모으기',
      description: '',
      statId: 'wealth',
      targetAmount: 1000000,
      createdAt: DateTime(2026, 7, 1),
    ));

    final container = ProviderContainer(overrides: [
      storageServiceProvider.overrideWithValue(storage),
    ]);
    addTearDown(container.dispose);
    final notifier = container.read(transactionsProvider.notifier);

    await notifier.addTransaction(_tx('t1', TransactionType.income, 50000, goalId: 'g1'));
    expect(storage.getGoal('g1')!.currentAmount, 50000);

    await notifier.deleteTransaction('t1');
    expect(storage.getGoal('g1')!.currentAmount, 0);
    expect(storage.getTransactions(), isEmpty);
  });

  test('지출 거래 삭제는 차감했던 금액을 다시 더한다', () async {
    final storage = await createTestStorage();
    await storage.saveGoal(Goal(
      id: 'g1',
      title: '비상금 모으기',
      description: '',
      statId: 'wealth',
      targetAmount: 1000000,
      currentAmount: 300000,
      createdAt: DateTime(2026, 7, 1),
    ));

    final container = ProviderContainer(overrides: [
      storageServiceProvider.overrideWithValue(storage),
    ]);
    addTearDown(container.dispose);
    final notifier = container.read(transactionsProvider.notifier);

    await notifier.addTransaction(_tx('t1', TransactionType.expense, 100000, goalId: 'g1'));
    expect(storage.getGoal('g1')!.currentAmount, 200000);

    await notifier.deleteTransaction('t1');
    expect(storage.getGoal('g1')!.currentAmount, 300000);
  });

  test('완료된 재무 목표를 목표 아래로 떨어뜨리는 거래 삭제는 목표를 다시 진행중으로 되돌린다', () async {
    final storage = await createTestStorage();
    await storage.saveGoal(Goal(
      id: 'g1',
      title: '비상금 모으기',
      description: '',
      statId: 'wealth',
      targetAmount: 100000,
      currentAmount: 60000,
      createdAt: DateTime(2026, 7, 1),
    ));

    final container = ProviderContainer(overrides: [
      storageServiceProvider.overrideWithValue(storage),
    ]);
    addTearDown(container.dispose);
    final notifier = container.read(transactionsProvider.notifier);

    // 이 입금이 목표(10만)를 채워 자동 완료시킨다: 60,000 + 50,000 = 110,000.
    await notifier.addTransaction(_tx('t1', TransactionType.income, 50000, goalId: 'g1'));
    expect(storage.getGoal('g1')!.status, GoalStatus.completed);

    // 그 거래를 삭제하면 금액이 목표 아래(60,000)로 떨어지고 목표가 다시 진행중이 된다.
    await notifier.deleteTransaction('t1');
    final goal = storage.getGoal('g1')!;
    expect(goal.currentAmount, 60000);
    expect(goal.status, GoalStatus.active);
    expect(goal.completedAt, isNull);
  });

  test('목표에 연결되지 않은 거래 삭제는 목표를 건드리지 않는다', () async {
    final storage = await createTestStorage();
    await storage.saveGoal(Goal(
      id: 'g1',
      title: '비상금 모으기',
      description: '',
      statId: 'wealth',
      targetAmount: 1000000,
      currentAmount: 500000,
      createdAt: DateTime(2026, 7, 1),
    ));

    final container = ProviderContainer(overrides: [
      storageServiceProvider.overrideWithValue(storage),
    ]);
    addTearDown(container.dispose);
    final notifier = container.read(transactionsProvider.notifier);

    await notifier.addTransaction(_tx('t1', TransactionType.expense, 10000));
    await notifier.deleteTransaction('t1');

    expect(storage.getGoal('g1')!.currentAmount, 500000);
  });
}
