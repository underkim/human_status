import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:human_status/data/achievement_definitions.dart';
import 'package:human_status/models/goal.dart';
import 'package:human_status/models/quest.dart';
import 'package:human_status/providers/goal_provider.dart';
import 'package:human_status/providers/profile_provider.dart';
import 'package:human_status/providers/quest_provider.dart';
import 'package:human_status/services/achievement_service.dart';
import 'package:human_status/services/storage_service.dart';
import 'package:human_status/services/xp_service.dart';

import 'helpers/test_app.dart';

Quest _quest(
  String id, {
  Map<String, double> statRewards = const {'health': 20},
  String? goalId,
}) => Quest(
  id: id,
  title: '퀘스트 $id',
  description: '',
  statRewards: statRewards,
  goalId: goalId,
  createdAt: DateTime(2026, 7, 14),
);

Goal _goal(String id, {String statId = 'health'}) => Goal(
  id: id,
  title: '목표 $id',
  description: '',
  statId: statId,
  createdAt: DateTime(2026, 7, 14),
);

/// A StatsNotifier whose [applyXp] throws a [StateError] on the Nth call
/// (1-indexed) across the whole container, so a test can force a failure
/// after some number of stat writes have already committed — simulating a
/// stat write (or the Hive box behind it) failing partway through a
/// multi-stat reward.
class _ThrowsOnNthApplyXpNotifier extends StatsNotifier {
  _ThrowsOnNthApplyXpNotifier(super.storage, this._throwOnCall);

  final int _throwOnCall;
  int _calls = 0;

  @override
  Future<LevelUpResult> applyXp(String statId, double xp) async {
    _calls++;
    if (_calls == _throwOnCall) {
      throw StateError('simulated stat write failure (call $_calls)');
    }
    return super.applyXp(statId, xp);
  }
}

/// An AchievementService whose [checkAndUnlock] persists a fake achievement
/// id and then throws, every time it's called — reproduces the scenario from
/// goal_creation_atomicity_test.dart's `_UnlocksThenThrowsAchievementService`
/// (achievement already written to storage before the failure), applied to
/// quest/goal completion instead of goal creation.
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

/// An AchievementService whose [checkAndUnlock] behaves normally except on
/// the Nth call (1-indexed), where it persists a fake achievement id and
/// then throws.
/// Lets a test force exactly one of two concurrently-dispatched completions
/// to fail at the achievement-check step while the other succeeds normally.
class _ThrowsOnNthCheckAchievementService extends AchievementService {
  _ThrowsOnNthCheckAchievementService(StorageService storage, this._throwOnCall)
    : super(storage: storage);

  final int _throwOnCall;
  int _calls = 0;

  @override
  Future<List<AchievementDefinition>> checkAndUnlock(
    AchievementContext context,
  ) async {
    _calls++;
    if (_calls == _throwOnCall) {
      await storage.unlockAchievement(
        'test_fake_achievement',
        DateTime(2026, 7, 15),
      );
      throw StateError('simulated achievement check failure (call $_calls)');
    }
    return super.checkAndUnlock(context);
  }
}

void main() {
  group('completion reward integrity', () {
    test('같은 퀘스트를 동시에 두 번 완료해도 XP는 한 번만 지급된다', () async {
      final storage = await createTestStorage();
      await storage.saveQuest(_quest('q1'));
      final container = ProviderContainer(
        overrides: [storageServiceProvider.overrideWithValue(storage)],
      );
      addTearDown(container.dispose);
      final notifier = container.read(questsProvider.notifier);

      final results = await Future.wait([
        notifier.completeQuest('q1'),
        notifier.completeQuest('q1'),
      ]);

      final awarded = results.where((r) => r.levelUps.isNotEmpty).length;
      expect(awarded, 1);
      expect(storage.getStat('health')!.currentXp, 20);
      expect(
        storage
            .getQuests()
            .where((q) => q.status == QuestStatus.completed)
            .length,
        1,
      );
    });

    test('같은 목표를 동시에 두 번 완료해도 보너스 XP는 한 번만 지급된다', () async {
      final storage = await createTestStorage();
      await storage.saveGoal(_goal('g1'));
      final container = ProviderContainer(
        overrides: [storageServiceProvider.overrideWithValue(storage)],
      );
      addTearDown(container.dispose);
      final notifier = container.read(goalsProvider.notifier);

      final results = await Future.wait([
        notifier.completeGoal('g1'),
        notifier.completeGoal('g1'),
      ]);

      final awarded = results.where((r) => r.levelUp.newLevel > 0).length;
      expect(awarded, 1);
      // goalCompletionBonusXp (100) exactly equals the level-1 threshold, so
      // a single award leaves the stat at level 2 with 0 leftover XP; a
      // double award would leave 100 XP left over into level 2 instead.
      expect(storage.getStat('health')!.level, 2);
      expect(storage.getStat('health')!.currentXp, 0);
      expect(
        storage
            .getGoals()
            .where((g) => g.status == GoalStatus.completed)
            .length,
        1,
      );
    });

    test('같은 스탯을 보상하는 서로 다른 두 퀘스트를 동시에 완료하면 둘 다 정확히 한 번씩 반영된다', () async {
      final storage = await createTestStorage();
      await storage.saveQuest(_quest('q1', statRewards: {'health': 20}));
      await storage.saveQuest(_quest('q2', statRewards: {'health': 15}));
      final container = ProviderContainer(
        overrides: [storageServiceProvider.overrideWithValue(storage)],
      );
      addTearDown(container.dispose);
      final notifier = container.read(questsProvider.notifier);

      await Future.wait([
        notifier.completeQuest('q1'),
        notifier.completeQuest('q2'),
      ]);

      // No lost update: both rewards landed, none overwritten by the other.
      expect(storage.getStat('health')!.currentXp, 35);
      expect(
        storage
            .getQuests()
            .where((q) => q.status == QuestStatus.completed)
            .length,
        2,
      );
    });

    test(
      '여러 스탯을 보상하는 퀘스트가 두 번째 스탯 기록 도중 실패하면 첫 스탯 XP도 롤백되고 퀘스트는 active로 남는다',
      () async {
        final storage = await createTestStorage();
        await storage.saveQuest(
          _quest('q1', statRewards: {'health': 20, 'intelligence': 10}),
        );
        final container = ProviderContainer(
          overrides: [
            storageServiceProvider.overrideWithValue(storage),
            statsProvider.overrideWith(
              (ref) => _ThrowsOnNthApplyXpNotifier(
                ref.watch(storageServiceProvider),
                2,
              ),
            ),
          ],
        );
        addTearDown(container.dispose);

        await expectLater(
          container.read(questsProvider.notifier).completeQuest('q1'),
          throwsA(isA<StateError>()),
        );

        expect(storage.getStat('health')!.currentXp, 0);
        expect(storage.getStat('intelligence')!.currentXp, 0);
        final quest = storage.getQuests().single;
        expect(quest.status, QuestStatus.active);
        expect(quest.completedAt, isNull);
      },
    );

    test(
      '업적 체크가 새 업적을 저장한 뒤 던지면(퀘스트 완료) 스탯·퀘스트·새 업적이 모두 롤백되고 기존 업적은 남는다',
      () async {
        final storage = await createTestStorage();
        await storage.unlockAchievement(
          'prior_achievement',
          DateTime(2026, 1, 1),
        );
        await storage.saveQuest(_quest('q1'));
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

        await expectLater(
          container.read(questsProvider.notifier).completeQuest('q1'),
          throwsA(isA<StateError>()),
        );

        expect(storage.getStat('health')!.currentXp, 0);
        expect(storage.getQuests().single.status, QuestStatus.active);
        expect(
          storage.getUnlockedAchievements().keys,
          isNot(contains('test_fake_achievement')),
        );
        expect(
          storage.getUnlockedAchievements().keys,
          contains('prior_achievement'),
        );
      },
    );

    test('연결된 목표 자동완료가 실패하면 퀘스트·목표·둘의 스탯XP가 모두 롤백된다', () async {
      final storage = await createTestStorage();
      await storage.saveGoal(_goal('g1', statId: 'wealth'));
      await storage.saveQuest(
        _quest('q1', statRewards: {'health': 20}, goalId: 'g1'),
      );
      final container = ProviderContainer(
        overrides: [
          storageServiceProvider.overrideWithValue(storage),
          // 1st applyXp call = quest's own 'health' reward (succeeds).
          // 2nd applyXp call = the auto-completed goal's bonus XP on
          // 'wealth' — force that one to fail.
          statsProvider.overrideWith(
            (ref) => _ThrowsOnNthApplyXpNotifier(
              ref.watch(storageServiceProvider),
              2,
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      await expectLater(
        container.read(questsProvider.notifier).completeQuest('q1'),
        throwsA(isA<StateError>()),
      );

      expect(storage.getStat('health')!.currentXp, 0);
      expect(storage.getStat('wealth')!.currentXp, 0);
      final quest = storage.getQuests().single;
      expect(quest.status, QuestStatus.active);
      expect(quest.completedAt, isNull);
      final goal = storage.getGoal('g1')!;
      expect(goal.status, GoalStatus.active);
      expect(goal.completedAt, isNull);
    });

    test('목표 완료가 상태 변경 직후(스탯 지급 전) 실패하면 목표 상태가 롤백되고 스탯은 건드려지지 않는다', () async {
      final storage = await createTestStorage();
      await storage.saveGoal(_goal('g1'));
      final container = ProviderContainer(
        overrides: [
          storageServiceProvider.overrideWithValue(storage),
          statsProvider.overrideWith(
            (ref) => _ThrowsOnNthApplyXpNotifier(
              ref.watch(storageServiceProvider),
              1,
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      await expectLater(
        container.read(goalsProvider.notifier).completeGoal('g1'),
        throwsA(isA<StateError>()),
      );

      final goal = storage.getGoal('g1')!;
      expect(goal.status, GoalStatus.active);
      expect(goal.completedAt, isNull);
      expect(storage.getStat('health')!.currentXp, 0);
    });

    test('목표 완료가 스탯 지급 후(업적 체크 도중) 실패하면 목표 상태·스탯XP·새 업적이 모두 롤백된다', () async {
      final storage = await createTestStorage();
      await storage.unlockAchievement(
        'prior_achievement',
        DateTime(2026, 1, 1),
      );
      await storage.saveGoal(_goal('g1'));
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

      await expectLater(
        container.read(goalsProvider.notifier).completeGoal('g1'),
        throwsA(isA<StateError>()),
      );

      final goal = storage.getGoal('g1')!;
      expect(goal.status, GoalStatus.active);
      expect(goal.completedAt, isNull);
      expect(storage.getStat('health')!.currentXp, 0);
      expect(
        storage.getUnlockedAchievements().keys,
        isNot(contains('test_fake_achievement')),
      );
      expect(
        storage.getUnlockedAchievements().keys,
        contains('prior_achievement'),
      );
    });

    test('실패 후 재시도하면 정확히 한 번만 XP가 지급된다', () async {
      final storage = await createTestStorage();
      await storage.saveQuest(_quest('q1'));
      final failingContainer = ProviderContainer(
        overrides: [
          storageServiceProvider.overrideWithValue(storage),
          statsProvider.overrideWith(
            (ref) => _ThrowsOnNthApplyXpNotifier(
              ref.watch(storageServiceProvider),
              1,
            ),
          ),
        ],
      );
      addTearDown(failingContainer.dispose);

      await expectLater(
        failingContainer.read(questsProvider.notifier).completeQuest('q1'),
        throwsA(isA<StateError>()),
      );
      expect(storage.getStat('health')!.currentXp, 0);
      expect(storage.getQuests().single.status, QuestStatus.active);

      failingContainer.dispose();
      final retryContainer = ProviderContainer(
        overrides: [storageServiceProvider.overrideWithValue(storage)],
      );
      addTearDown(retryContainer.dispose);

      final result = await retryContainer
          .read(questsProvider.notifier)
          .completeQuest('q1');
      expect(result.levelUps, isNotEmpty);
      expect(storage.getStat('health')!.currentXp, 20);
      expect(storage.getQuests().single.status, QuestStatus.completed);
    });

    test('실패한 완료와 동시에 진행된 다른 퀘스트의 성공은 롤백에 의해 지워지지 않는다', () async {
      final storage = await createTestStorage();
      // q1 dispatched first: the global lock runs it to completion (success)
      // before q2 (dispatched second) starts, so q1's XP is committed by the
      // time q2's failure/rollback happens.
      await storage.saveQuest(_quest('q1', statRewards: {'health': 20}));
      await storage.saveQuest(_quest('q2', statRewards: {'health': 15}));
      final container = ProviderContainer(
        overrides: [
          storageServiceProvider.overrideWithValue(storage),
          // 1st checkAndUnlock call belongs to q1 (succeeds normally). 2nd
          // belongs to q2 (writes a fake achievement, then throws).
          achievementServiceProvider.overrideWith(
            (ref) => _ThrowsOnNthCheckAchievementService(
              ref.watch(storageServiceProvider),
              2,
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      final notifier = container.read(questsProvider.notifier);

      final q1Future = notifier.completeQuest('q1');
      final q2Future = notifier.completeQuest('q2');

      final q1Result = await q1Future;
      await expectLater(q2Future, throwsA(isA<StateError>()));

      expect(q1Result.levelUps, isNotEmpty);
      // q1's XP survives q2's rollback — not erased, not double-applied.
      expect(storage.getStat('health')!.currentXp, 20);
      expect(
        storage.getQuests().firstWhere((q) => q.id == 'q1').status,
        QuestStatus.completed,
      );
      expect(
        storage.getQuests().firstWhere((q) => q.id == 'q2').status,
        QuestStatus.active,
      );
      expect(
        storage.getUnlockedAchievements().keys,
        isNot(contains('test_fake_achievement')),
      );
    });

    test('수동 목표 완료와 퀘스트 자동완료가 경쟁해도 목표 보너스는 한 번만 지급된다', () async {
      final storage = await createTestStorage();
      await storage.saveGoal(_goal('g1'));
      await storage.saveQuest(
        _quest('q1', statRewards: {'intelligence': 10}, goalId: 'g1'),
      );
      final container = ProviderContainer(
        overrides: [storageServiceProvider.overrideWithValue(storage)],
      );
      addTearDown(container.dispose);

      final questResult = container
          .read(questsProvider.notifier)
          .completeQuest('q1');
      final goalResult = container
          .read(goalsProvider.notifier)
          .completeGoal('g1');

      await Future.wait([questResult, goalResult]);

      // goalCompletionBonusXp (100) exactly equals the level-1 threshold, so
      // a single award leaves the stat at level 2 with 0 leftover XP; a
      // double award would leave 100 XP left over into level 2 instead.
      expect(storage.getStat('health')!.level, 2);
      expect(storage.getStat('health')!.currentXp, 0);
      expect(
        storage
            .getGoals()
            .where((g) => g.status == GoalStatus.completed)
            .length,
        1,
      );
    });
  });
}
