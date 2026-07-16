import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:human_status/models/goal.dart';
import 'package:human_status/models/quest.dart';
import 'package:human_status/providers/goal_provider.dart';
import 'package:human_status/providers/profile_provider.dart';
import 'package:human_status/services/storage_service.dart';

import 'helpers/test_app.dart';

Goal _goal(
  String id, {
  String title = '제목',
  String statId = 'health',
  double? targetAmount,
  double currentAmount = 0,
  GoalStatus status = GoalStatus.active,
}) => Goal(
  id: id,
  title: title,
  description: '',
  statId: statId,
  targetAmount: targetAmount,
  currentAmount: currentAmount,
  status: status,
  createdAt: DateTime(2026, 7, 1),
);

Quest _quest(String id, String goalId, QuestStatus status) => Quest(
  id: id,
  title: id,
  description: '',
  statRewards: const {'health': 20},
  status: status,
  createdAt: DateTime(2026, 7, 1),
  goalId: goalId,
);

/// A [StorageService] whose [saveGoal]/[saveQuest]/[deleteGoal] each throw
/// on exactly their configured Nth call (1-indexed, 0 = never) and otherwise
/// behave normally. Every call's argument is recorded as a detached
/// snapshot (`.copy()`) *before* the throw check, so assertions can confirm
/// a rollback actually issued a second, successful write — not merely that
/// a shared Hive-boxed instance happens to read back correctly (see
/// financial_transaction_atomicity_test.dart's `_ThrowsOnNthSaveGoalStorage`
/// for the same rationale).
class _FaultyGoalStorage extends StorageService {
  _FaultyGoalStorage({super.inMemory});

  int throwOnSaveGoalCall = 0;
  int throwOnSaveQuestCall = 0;
  int throwOnDeleteGoalCall = 0;

  final List<Goal> saveGoalCalls = [];
  final List<Quest> saveQuestCalls = [];
  int deleteGoalCalls = 0;

  @override
  Future<void> saveGoal(Goal goal) {
    saveGoalCalls.add(goal.copy());
    if (saveGoalCalls.length == throwOnSaveGoalCall) {
      throw StateError(
        'simulated goal save failure (call ${saveGoalCalls.length})',
      );
    }
    return super.saveGoal(goal);
  }

  @override
  Future<void> saveQuest(Quest quest) {
    saveQuestCalls.add(quest.copy());
    if (saveQuestCalls.length == throwOnSaveQuestCall) {
      throw StateError(
        'simulated quest save failure (call ${saveQuestCalls.length})',
      );
    }
    return super.saveQuest(quest);
  }

  @override
  Future<void> deleteGoal(String id) {
    deleteGoalCalls++;
    if (deleteGoalCalls == throwOnDeleteGoalCall) {
      throw StateError('simulated goal delete failure (call $deleteGoalCalls)');
    }
    return super.deleteGoal(id);
  }
}

Future<_FaultyGoalStorage> _faultyStorage() async {
  final storage = _FaultyGoalStorage(inMemory: true);
  await storage.init();
  addTearDown(Hive.close);
  return storage;
}

void main() {
  group('updateGoal — 원자성/롤백', () {
    test('편집 저장 자체가 실패하면 넘긴 proposed와 storage의 원본이 그대로 남고, 재시도는 한 번만 반영된다', () async {
      final storage = await _faultyStorage();
      final original = _goal('g1', title: '원래 제목');
      await storage.saveGoal(original);

      final container = ProviderContainer(
        overrides: [storageServiceProvider.overrideWithValue(storage)],
      );
      addTearDown(container.dispose);
      final notifier = container.read(goalsProvider.notifier);

      storage.saveGoalCalls.clear();
      storage.throwOnSaveGoalCall = 1; // the edit's own save fails.

      final proposed = original.copy()..title = '새 제목';
      await expectLater(
        notifier.updateGoal(proposed),
        throwsA(isA<StateError>()),
      );

      // The caller's detached proposed object is never touched by
      // updateGoal — it was never a live reference to begin with.
      expect(proposed.title, '새 제목');
      // The originally-fetched live object and storage are both untouched.
      expect(original.title, '원래 제목');
      expect(storage.getGoal('g1')!.title, '원래 제목');
      // The rollback's own restoring save actually executed a second write.
      expect(storage.saveGoalCalls.length, 2);
      expect(storage.saveGoalCalls[1].title, '원래 제목');

      // Retry succeeds exactly once the fault clears.
      storage.throwOnSaveGoalCall = 0;
      final stored = storage.getGoal('g1')!;
      final retry = stored.copy()..title = '새 제목';
      final completion = await notifier.updateGoal(retry);

      expect(completion, isNull);
      expect(storage.getGoal('g1')!.title, '새 제목');
      expect(storage.getGoals(), hasLength(1));
    });

    test('편집이 재무 목표를 완료 지점까지 낮췄는데 완료 처리 도중 실패하면 편집·보상 상태가 모두 롤백된다', () async {
      final storage = await _faultyStorage();
      final original = _goal(
        'g1',
        title: '비상금',
        statId: 'wealth',
        targetAmount: 1000000,
        currentAmount: 300000,
      );
      await storage.saveGoal(original);

      final container = ProviderContainer(
        overrides: [storageServiceProvider.overrideWithValue(storage)],
      );
      addTearDown(container.dispose);
      final notifier = container.read(goalsProvider.notifier);

      // Call #1 = the edit's own save (succeeds); call #2 = the completion's
      // goal save inside completeGoalLocked (fails).
      storage.saveGoalCalls.clear();
      storage.throwOnSaveGoalCall = 2;

      final proposed = original.copy()..targetAmount = 200000; // 300000 already clears this.
      await expectLater(
        notifier.updateGoal(proposed),
        throwsA(isA<StateError>()),
      );

      final restored = storage.getGoal('g1')!;
      expect(restored.title, '비상금');
      expect(restored.targetAmount, 1000000); // edit itself rolled back too.
      expect(restored.currentAmount, 300000);
      expect(restored.status, GoalStatus.active);
      expect(restored.completedAt, isNull);
      expect(restored.completionRewardClaimed, isFalse);
      expect(storage.getStat('wealth')!.currentXp, 0);
      // Multiple real writes occurred during forward + rollback, not just
      // one aliased in-memory mutation.
      expect(storage.saveGoalCalls.length, greaterThanOrEqualTo(4));
    });

    test('존재하지 않는 목표를 수정하려 하면 GoalNotFoundException을 던지고 아무것도 쓰지 않는다', () async {
      final storage = await createTestStorage();
      final container = ProviderContainer(
        overrides: [storageServiceProvider.overrideWithValue(storage)],
      );
      addTearDown(container.dispose);

      final ghost = _goal('ghost', title: '유령');
      await expectLater(
        container.read(goalsProvider.notifier).updateGoal(ghost),
        throwsA(isA<GoalNotFoundException>()),
      );
      expect(storage.getGoals(), isEmpty);
    });
  });

  group('deleteGoal — 원자성/롤백', () {
    test('퀘스트 언링크 도중 실패하면 이미 언링크된 퀘스트를 포함해 모든 연결과 목표가 그대로 복원된다', () async {
      final storage = await _faultyStorage();
      await storage.saveGoal(_goal('g1', title: '목표'));
      await storage.saveQuest(_quest('q1', 'g1', QuestStatus.active));
      await storage.saveQuest(_quest('q2', 'g1', QuestStatus.active));
      await storage.saveQuest(_quest('q3', 'g1', QuestStatus.suggested));

      final container = ProviderContainer(
        overrides: [storageServiceProvider.overrideWithValue(storage)],
      );
      addTearDown(container.dispose);
      final notifier = container.read(goalsProvider.notifier);

      storage.saveQuestCalls.clear();
      storage.throwOnSaveQuestCall = 2; // fails unlinking the second quest.

      await expectLater(
        notifier.deleteGoal('g1'),
        throwsA(isA<StateError>()),
      );

      expect(storage.getGoal('g1'), isNotNull);
      expect(storage.getGoal('g1')!.title, '목표');
      expect(storage.getQuests().firstWhere((q) => q.id == 'q1').goalId, 'g1');
      expect(storage.getQuests().firstWhere((q) => q.id == 'q2').goalId, 'g1');
      expect(storage.getQuests().firstWhere((q) => q.id == 'q3').goalId, 'g1');
      // q1's unlink, q2's failed unlink, then q2's and q1's rollback
      // restores — real writes on both sides, not aliasing.
      expect(storage.saveQuestCalls.length, 4);
      expect(storage.saveQuestCalls[2].goalId, 'g1');
      expect(storage.saveQuestCalls[3].goalId, 'g1');
    });

    test('목표 삭제 자체가 실패하면 이미 언링크됐던 퀘스트까지 원래 링크로 복원된다', () async {
      final storage = await _faultyStorage();
      await storage.saveGoal(_goal('g1', title: '목표'));
      await storage.saveQuest(_quest('q1', 'g1', QuestStatus.active));
      await storage.saveQuest(_quest('done', 'g1', QuestStatus.completed));

      final container = ProviderContainer(
        overrides: [storageServiceProvider.overrideWithValue(storage)],
      );
      addTearDown(container.dispose);
      final notifier = container.read(goalsProvider.notifier);

      storage.throwOnDeleteGoalCall = 1;

      await expectLater(
        notifier.deleteGoal('g1'),
        throwsA(isA<StateError>()),
      );

      expect(storage.getGoal('g1'), isNotNull);
      expect(storage.getQuests().firstWhere((q) => q.id == 'q1').goalId, 'g1');
      expect(storage.getQuests().firstWhere((q) => q.id == 'done').goalId, 'g1');
    });

    test('실패 후 재시도하면 이번엔 정확히 한 번 삭제되고 부분 상태가 남지 않는다', () async {
      final storage = await _faultyStorage();
      await storage.saveGoal(_goal('g1', title: '목표'));
      await storage.saveQuest(_quest('q1', 'g1', QuestStatus.active));

      final container = ProviderContainer(
        overrides: [storageServiceProvider.overrideWithValue(storage)],
      );
      addTearDown(container.dispose);
      final notifier = container.read(goalsProvider.notifier);

      storage.throwOnDeleteGoalCall = 1;
      await expectLater(
        notifier.deleteGoal('g1'),
        throwsA(isA<StateError>()),
      );

      storage.throwOnDeleteGoalCall = 0;
      await notifier.deleteGoal('g1');

      expect(storage.getGoal('g1'), isNull);
      expect(storage.getQuests().single.goalId, isNull);
    });

    test('동시에 두 번 삭제를 호출해도 한 번만 실제로 삭제되고 예외 없이 안전하게 끝난다', () async {
      final storage = await createTestStorage();
      await storage.saveGoal(_goal('g1', title: '목표'));
      await storage.saveQuest(_quest('q1', 'g1', QuestStatus.active));

      final container = ProviderContainer(
        overrides: [storageServiceProvider.overrideWithValue(storage)],
      );
      addTearDown(container.dispose);
      final notifier = container.read(goalsProvider.notifier);

      await Future.wait([
        notifier.deleteGoal('g1'),
        notifier.deleteGoal('g1'),
      ]);

      expect(storage.getGoal('g1'), isNull);
      expect(storage.getQuests().single.goalId, isNull);
      // Both calls resolved successfully — no exception surfaced.
      await notifier.deleteGoal('g1'); // a third, later duplicate is also a no-op.
      expect(storage.getGoal('g1'), isNull);
    });
  });
}
