import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:human_status/data/achievement_definitions.dart';
import 'package:human_status/models/goal.dart';
import 'package:human_status/models/transaction.dart';
import 'package:human_status/providers/finance_provider.dart';
import 'package:human_status/providers/profile_provider.dart';
import 'package:human_status/providers/quest_provider.dart';
import 'package:human_status/services/achievement_service.dart';
import 'package:human_status/services/storage_service.dart';

import 'helpers/test_app.dart';

Transaction _tx(
  String id,
  TransactionType type,
  double amount, {
  String? goalId,
  DateTime? date,
}) {
  final d = date ?? DateTime(2026, 7, 10);
  return Transaction(
    id: id,
    type: type,
    category: '저축',
    memo: '',
    amount: amount,
    date: d,
    linkedGoalId: goalId,
    createdAt: d,
  );
}

Goal _financialGoal(
  String id, {
  double target = 100000,
  double current = 0,
  String statId = 'wealth',
}) => Goal(
  id: id,
  title: '목표 $id',
  description: '',
  statId: statId,
  targetAmount: target,
  currentAmount: current,
  createdAt: DateTime(2026, 7, 1),
);

/// A [StorageService] whose [saveGoal] can be switched to throw on demand —
/// used to force a failure partway through addTransaction/deleteTransaction,
/// after the transaction write (or delete) has already landed but before the
/// paired goal-amount write commits.
class _ThrowsOnSaveGoalStorage extends StorageService {
  _ThrowsOnSaveGoalStorage({super.inMemory});

  bool throwOnSaveGoal = false;

  @override
  Future<void> saveGoal(Goal goal) {
    if (throwOnSaveGoal) {
      throw StateError('simulated goal write failure');
    }
    return super.saveGoal(goal);
  }
}

/// An AchievementService whose [checkAndUnlock] persists a fake achievement
/// id and then throws — reproduces the same fault-injection shape as
/// completion_reward_integrity_test.dart's `_UnlocksThenThrowsAchievementService`,
/// applied to the transaction->goal-completion path.
class _UnlocksThenThrowsAchievementService extends AchievementService {
  _UnlocksThenThrowsAchievementService(StorageService storage)
    : super(storage: storage);

  @override
  Future<List<AchievementDefinition>> checkAndUnlock(
    AchievementContext context,
  ) async {
    await storage.unlockAchievement(
      'test_fake_achievement',
      DateTime(2026, 7, 15),
    );
    throw StateError('simulated achievement check failure');
  }
}

void main() {
  group('addTransaction — 원자성/롤백', () {
    test('목표 저장 도중 실패하면 이미 쓰여진 거래도 함께 롤백된다', () async {
      final storage = _ThrowsOnSaveGoalStorage(inMemory: true);
      await storage.init();
      addTearDown(Hive.close);
      await storage.saveGoal(_financialGoal('g1', current: 10000));

      final container = ProviderContainer(
        overrides: [storageServiceProvider.overrideWithValue(storage)],
      );
      addTearDown(container.dispose);
      final notifier = container.read(transactionsProvider.notifier);

      storage.throwOnSaveGoal = true;
      await expectLater(
        notifier.addTransaction(
          _tx('t1', TransactionType.income, 5000, goalId: 'g1'),
        ),
        throwsA(isA<StateError>()),
      );

      // The transaction write that happened before the failing goal write
      // must be undone — no partial state left behind.
      expect(storage.getTransactions(), isEmpty);
      expect(storage.getGoal('g1')!.currentAmount, 10000);
    });

    test('목표를 완료로 밀어넣는 첫 보너스 지급 중 업적 체크가 실패하면 거래·목표·스탯·업적이 모두 롤백된다', () async {
      final storage = await createTestStorage();
      await storage.unlockAchievement(
        'prior_achievement',
        DateTime(2026, 1, 1),
      );
      await storage.saveGoal(
        _financialGoal('g1', target: 100000, current: 90000),
      );

      final container = ProviderContainer(
        overrides: [
          storageServiceProvider.overrideWithValue(storage),
          achievementServiceProvider.overrideWith(
            (ref) => _UnlocksThenThrowsAchievementService(
              ref.watch(storageServiceProvider),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      final notifier = container.read(transactionsProvider.notifier);

      await expectLater(
        notifier.addTransaction(
          _tx('t1', TransactionType.income, 20000, goalId: 'g1'),
        ),
        throwsA(isA<StateError>()),
      );

      expect(storage.getTransactions(), isEmpty);
      final goal = storage.getGoal('g1')!;
      expect(goal.currentAmount, 90000);
      expect(goal.status, GoalStatus.active);
      expect(goal.completionRewardClaimed, isFalse);
      expect(storage.getStat('wealth')!.currentXp, 0);
      expect(
        storage.getUnlockedAchievements().keys,
        isNot(contains('test_fake_achievement')),
      );
      expect(
        storage.getUnlockedAchievements().keys,
        contains('prior_achievement'),
      );
    });

    test('정확히 같은 id/내용으로 동시에 두 번 추가해도 목표 금액은 한 번만 반영된다', () async {
      final storage = await createTestStorage();
      await storage.saveGoal(_financialGoal('g1', current: 0));

      final container = ProviderContainer(
        overrides: [storageServiceProvider.overrideWithValue(storage)],
      );
      addTearDown(container.dispose);
      final notifier = container.read(transactionsProvider.notifier);

      final tx = _tx('t1', TransactionType.income, 30000, goalId: 'g1');
      await Future.wait([
        notifier.addTransaction(tx),
        notifier.addTransaction(tx),
      ]);

      expect(storage.getTransactions().length, 1);
      expect(storage.getGoal('g1')!.currentAmount, 30000);
    });

    test('실패 후 정확히 같은 내용으로 재시도하면 멱등하게 성공하고 목표는 한 번만 반영된다', () async {
      final storage = await createTestStorage();
      await storage.saveGoal(_financialGoal('g1', current: 0));

      final container = ProviderContainer(
        overrides: [storageServiceProvider.overrideWithValue(storage)],
      );
      addTearDown(container.dispose);
      final notifier = container.read(transactionsProvider.notifier);

      final tx = _tx('t1', TransactionType.income, 30000, goalId: 'g1');
      await notifier.addTransaction(tx);
      expect(storage.getGoal('g1')!.currentAmount, 30000);

      // A retry with the exact same fields (e.g. a UI resend after a lost
      // response) must no-op instead of adjusting the goal a second time.
      await notifier.addTransaction(tx);
      expect(storage.getTransactions().length, 1);
      expect(storage.getGoal('g1')!.currentAmount, 30000);
    });

    test('같은 id에 다른 내용이 들어오면 아무것도 바꾸지 않고 예외를 던진다', () async {
      final storage = await createTestStorage();
      await storage.saveGoal(_financialGoal('g1', current: 0));

      final container = ProviderContainer(
        overrides: [storageServiceProvider.overrideWithValue(storage)],
      );
      addTearDown(container.dispose);
      final notifier = container.read(transactionsProvider.notifier);

      await notifier.addTransaction(
        _tx('t1', TransactionType.income, 30000, goalId: 'g1'),
      );
      expect(storage.getGoal('g1')!.currentAmount, 30000);

      await expectLater(
        notifier.addTransaction(
          _tx('t1', TransactionType.income, 99999, goalId: 'g1'),
        ),
        throwsA(isA<DuplicateTransactionException>()),
      );

      // Original transaction and goal amount are untouched by the rejected
      // collision.
      expect(storage.getTransactions().single.amount, 30000);
      expect(storage.getGoal('g1')!.currentAmount, 30000);
    });
  });

  group('deleteTransaction — 원자성/롤백', () {
    test('목표 되돌리기 저장 도중 실패하면 삭제됐던 거래가 복원된다', () async {
      final storage = _ThrowsOnSaveGoalStorage(inMemory: true);
      await storage.init();
      addTearDown(Hive.close);
      final goal = _financialGoal('g1', current: 30000);
      await storage.saveGoal(goal);
      final tx = _tx('t1', TransactionType.income, 30000, goalId: 'g1');
      await storage.saveTransaction(tx);

      final container = ProviderContainer(
        overrides: [storageServiceProvider.overrideWithValue(storage)],
      );
      addTearDown(container.dispose);
      final notifier = container.read(transactionsProvider.notifier);

      storage.throwOnSaveGoal = true;
      await expectLater(
        notifier.deleteTransaction('t1'),
        throwsA(isA<StateError>()),
      );

      final restored = storage.getTransactions().single;
      expect(restored.id, 't1');
      expect(restored.amount, 30000);
      expect(storage.getGoal('g1')!.currentAmount, 30000);
    });

    test('존재하지 않는 id를 삭제하면(재시도) 아무 것도 바꾸지 않고 조용히 성공한다', () async {
      final storage = await createTestStorage();
      await storage.saveGoal(_financialGoal('g1', current: 30000));

      final container = ProviderContainer(
        overrides: [storageServiceProvider.overrideWithValue(storage)],
      );
      addTearDown(container.dispose);
      final notifier = container.read(transactionsProvider.notifier);

      await notifier.deleteTransaction('never-existed');

      expect(storage.getTransactions(), isEmpty);
      expect(storage.getGoal('g1')!.currentAmount, 30000);
    });
  });

  group('완료→삭제→재완료: 보너스는 평생 한 번만', () {
    test('목표를 완료시킨 거래를 삭제해 재오픈해도, 다시 채우는 거래는 두 번째 보너스 XP를 주지 않는다', () async {
      final storage = await createTestStorage();
      await storage.saveGoal(_financialGoal('g1', target: 100000, current: 0));

      final container = ProviderContainer(
        overrides: [storageServiceProvider.overrideWithValue(storage)],
      );
      addTearDown(container.dispose);
      final notifier = container.read(transactionsProvider.notifier);

      // First contribution completes the goal and pays the one-time bonus.
      await notifier.addTransaction(
        _tx('t1', TransactionType.income, 100000, goalId: 'g1'),
      );
      var goal = storage.getGoal('g1')!;
      expect(goal.status, GoalStatus.completed);
      expect(goal.completionRewardClaimed, isTrue);
      final xpAfterFirstCompletion = storage.getStat('wealth')!.currentXp;
      final levelAfterFirstCompletion = storage.getStat('wealth')!.level;

      // Deleting the completing transaction reopens the goal but must not
      // refund the bonus already paid.
      await notifier.deleteTransaction('t1');
      goal = storage.getGoal('g1')!;
      expect(goal.status, GoalStatus.active);
      expect(goal.currentAmount, 0);
      expect(goal.completionRewardClaimed, isTrue);
      expect(storage.getStat('wealth')!.currentXp, xpAfterFirstCompletion);
      expect(storage.getStat('wealth')!.level, levelAfterFirstCompletion);

      // Re-adding a contribution that completes the goal again must
      // transition status back to completed but award no second bonus.
      await notifier.addTransaction(
        _tx('t2', TransactionType.income, 100000, goalId: 'g1'),
      );
      goal = storage.getGoal('g1')!;
      expect(goal.status, GoalStatus.completed);
      expect(goal.completionRewardClaimed, isTrue);
      expect(storage.getStat('wealth')!.currentXp, xpAfterFirstCompletion);
      expect(storage.getStat('wealth')!.level, levelAfterFirstCompletion);
    });
  });
}
