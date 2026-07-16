import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:human_status/data/achievement_definitions.dart';
import 'package:human_status/models/goal.dart';
import 'package:human_status/models/quest.dart';
import 'package:human_status/providers/goal_provider.dart';
import 'package:human_status/providers/profile_provider.dart';
import 'package:human_status/providers/quest_provider.dart';
import 'package:human_status/services/achievement_service.dart';
import 'package:human_status/services/goal_service.dart';
import 'package:human_status/services/reward_transaction.dart';
import 'package:human_status/services/storage_service.dart';

import 'helpers/test_app.dart';

Goal _goal(String id, {String statId = 'health'}) => Goal(
  id: id,
  title: '목표 $id',
  description: '',
  statId: statId,
  createdAt: DateTime(2026, 7, 14),
);

/// decompose가 항상 빈 리스트를 돌려주는 가짜 GoalService — requireQuests의
/// "퀘스트가 하나도 안 나오면 실패" 경로를 결정적으로 재현한다.
class _NoQuestGoalService extends GoalService {
  _NoQuestGoalService(StorageService storage) : super(storage: storage);

  @override
  Future<List<Quest>> decompose(Goal goal, {int count = 4}) async => [];
}

/// decompose가 항상 [goal.id]에서 결정적으로 유도한 id를 가진 퀘스트 딱 하나를
/// 돌려주는 가짜 GoalService — 완료 큐잉 테스트에서 어떤 퀘스트가 생겼는지
/// 미리 알아야 하므로, 로컬 규칙 소스의 uuid 기반 랜덤 id 대신 이걸 쓴다.
class _SingleFixedQuestGoalService extends GoalService {
  _SingleFixedQuestGoalService(StorageService storage)
    : super(storage: storage);

  @override
  Future<List<Quest>> decompose(Goal goal, {int count = 4}) async => [
    Quest(
      id: '${goal.id}-quest',
      title: '${goal.title}의 첫 걸음',
      description: '',
      statRewards: {goal.statId: 20},
      status: QuestStatus.active,
      source: QuestSource.manual,
      createdAt: DateTime(2026, 7, 14),
      goalId: goal.id,
    ),
  ];
}

/// checkAndUnlock이 업적을 실제로 저장한 *뒤에* 던지는 가짜
/// AchievementService — "goal/quest는 이미 저장됐고 업적 체크만 도중에
/// 실패한" 상황을 재현한다. 진짜 checkAndUnlock처럼 storage에 직접 쓰기
/// 때문에, createGoal의 catch 블록이 achievements 롤백을 unlockedBefore와의
/// 차집합으로 정확히 계산하는지(그리고 이 호출 이전부터 있던 업적은 건드리지
/// 않는지) 검증할 수 있다.
class _UnlocksThenThrowsAchievementService extends AchievementService {
  _UnlocksThenThrowsAchievementService(StorageService storage)
    : super(storage: storage);

  @override
  Future<List<AchievementDefinition>> checkAndUnlock(
    AchievementContext context,
  ) async {
    await storage.unlockAchievement('first_goal_set', DateTime(2026, 7, 15));
    throw StateError('simulated achievement check failure');
  }
}

/// Blocks the first call to [checkAndUnlock] until released — createGoal's
/// achievement check is its last transactional step, so this is the point at
/// which the whole create transaction (goal + every generated quest already
/// physically saved) is furthest along while still holding the shared
/// [rewardLockProvider]. Lets a test dispatch a second reward operation (a
/// quest completion, or a second createGoal) that must queue behind this one
/// on the lock, then observe it run only after this call finishes — either
/// by completing normally (see the `succeeds` flag) or, if `throwAfter` is
/// set, by writing a fake achievement and then throwing (reproducing the
/// failed-create-then-queued-completion scenario).
class _GatedAchievementService extends AchievementService {
  _GatedAchievementService(
    StorageService storage, {
    required this.entered,
    required this.release,
    this.throwAfterRelease = false,
  }) : super(storage: storage);

  final Completer<void> entered;
  final Completer<void> release;
  final bool throwAfterRelease;
  int _calls = 0;

  @override
  Future<List<AchievementDefinition>> checkAndUnlock(
    AchievementContext context,
  ) async {
    _calls++;
    if (_calls == 1) {
      entered.complete();
      await release.future;
      if (throwAfterRelease) {
        await storage.unlockAchievement(
          'test_fake_achievement',
          DateTime(2026, 7, 15),
        );
        throw StateError('simulated achievement check failure (held)');
      }
    }
    return super.checkAndUnlock(context);
  }
}

/// Blocks the first call to [decompose] until released, so a test can force
/// a specific ordering between two concurrent [GoalsNotifier.createGoal]
/// calls for the *same* goal id without relying on incidental microtask
/// scheduling — decomposition runs before the shared lock is acquired, so
/// gating it lets the second (non-gated) call reach the lock, create the
/// goal, and finish first; the first call resumes afterwards and must then
/// observe the collision.
class _GatedDecomposeGoalService extends GoalService {
  _GatedDecomposeGoalService(
    StorageService storage, {
    required this.entered,
    required this.release,
  }) : super(storage: storage);

  final Completer<void> entered;
  final Completer<void> release;
  int _calls = 0;

  @override
  Future<List<Quest>> decompose(Goal goal, {int count = 4}) async {
    _calls++;
    if (_calls == 1) {
      entered.complete();
      await release.future;
    }
    return super.decompose(goal, count: count);
  }
}

/// A [StorageService] whose [saveGoal]/[saveQuest] each perform the real
/// write *then* throw on their configured Nth call (1-indexed, 0 = never) —
/// reproducing a failure detected only after the underlying Hive write
/// already landed (e.g. a follow-up integrity check), not merely a guard
/// that stops an unperformed write. This is the harder case for rollback: it
/// must remove a record that's genuinely present in storage via a real
/// delete call, not just skip a write that never happened. Every delete is
/// counted so a test can assert an exact number of real rollback deletes,
/// not merely the end state (which aliasing could satisfy accidentally).
class _FaultyCreateStorage extends StorageService {
  _FaultyCreateStorage({super.inMemory});

  int throwOnSaveGoalCall = 0;
  int throwOnSaveQuestCall = 0;

  int saveGoalCalls = 0;
  int saveQuestCalls = 0;
  int deleteGoalCalls = 0;
  int deleteQuestCalls = 0;

  @override
  Future<void> saveGoal(Goal goal) async {
    saveGoalCalls++;
    final shouldThrow = saveGoalCalls == throwOnSaveGoalCall;
    await super.saveGoal(goal);
    if (shouldThrow) {
      throw StateError('simulated goal save failure (call $saveGoalCalls)');
    }
  }

  @override
  Future<void> saveQuest(Quest quest) async {
    saveQuestCalls++;
    final shouldThrow = saveQuestCalls == throwOnSaveQuestCall;
    await super.saveQuest(quest);
    if (shouldThrow) {
      throw StateError('simulated quest save failure (call $saveQuestCalls)');
    }
  }

  @override
  Future<void> deleteGoal(String id) async {
    deleteGoalCalls++;
    await super.deleteGoal(id);
  }

  @override
  Future<void> deleteQuest(String id) async {
    deleteQuestCalls++;
    await super.deleteQuest(id);
  }
}

Future<_FaultyCreateStorage> _faultyCreateStorage() async {
  final storage = _FaultyCreateStorage(inMemory: true);
  await storage.init();
  addTearDown(Hive.close);
  return storage;
}

void main() {
  group('createGoal(requireQuests: true) — 온보딩 스타터 목표 경로', () {
    test('분해 결과가 비어 있으면 아무것도 저장하지 않고 예외를 던진다', () async {
      final storage = await createTestStorage();
      final container = ProviderContainer(
        overrides: [
          storageServiceProvider.overrideWithValue(storage),
          goalServiceProvider.overrideWithValue(_NoQuestGoalService(storage)),
        ],
      );
      addTearDown(container.dispose);

      await expectLater(
        container
            .read(goalsProvider.notifier)
            .createGoal(_goal('g1'), requireQuests: true),
        throwsA(isA<GoalRequiresQuestsException>()),
      );

      expect(storage.getGoals(), isEmpty);
      expect(storage.getQuests(), isEmpty);
      expect(storage.getUnlockedAchievements(), isEmpty);
      expect(storage.getProfile().onboardingCompleted, isFalse);
    });

    test('실패 후 재시도하면(분해가 정상으로 돌아오면) 목표가 정확히 하나만 생긴다', () async {
      final storage = await createTestStorage();
      final container = ProviderContainer(
        overrides: [
          storageServiceProvider.overrideWithValue(storage),
          goalServiceProvider.overrideWithValue(_NoQuestGoalService(storage)),
        ],
      );
      addTearDown(container.dispose);

      final goal = _goal('g1');
      await expectLater(
        container
            .read(goalsProvider.notifier)
            .createGoal(goal, requireQuests: true),
        throwsA(isA<GoalRequiresQuestsException>()),
      );

      // 재시도: 이번엔 정상 GoalService(로컬 규칙 폴백)로 같은 id의 goal을 다시 만든다.
      container.dispose();
      final retryContainer = ProviderContainer(
        overrides: [storageServiceProvider.overrideWithValue(storage)],
      );
      addTearDown(retryContainer.dispose);
      final result = await retryContainer
          .read(goalsProvider.notifier)
          .createGoal(_goal('g1'), requireQuests: true);

      expect(result.quests, isNotEmpty);
      expect(storage.getGoals(), hasLength(1));
      final linkedActive = storage.getQuests().where(
        (q) => q.goalId == goal.id && q.status == QuestStatus.active,
      );
      expect(linkedActive, isNotEmpty);
    });

    test('실패 롤백은 이 호출 이전에 이미 해금돼 있던 업적은 건드리지 않는다', () async {
      final storage = await createTestStorage();
      // 이 호출 이전에 이미 해금된 업적을 시뮬레이션한다 — 롤백이
      // unlockedBefore/After의 차집합만 지우는지(전체를 비우지 않는지)를
      // 검증한다.
      await storage.unlockAchievement(
        'some_prior_achievement',
        DateTime(2026, 1, 1),
      );

      final container = ProviderContainer(
        overrides: [
          storageServiceProvider.overrideWithValue(storage),
          goalServiceProvider.overrideWithValue(_NoQuestGoalService(storage)),
        ],
      );
      addTearDown(container.dispose);

      await expectLater(
        container
            .read(goalsProvider.notifier)
            .createGoal(_goal('g1'), requireQuests: true),
        throwsA(isA<GoalRequiresQuestsException>()),
      );

      expect(storage.getGoals(), isEmpty);
      expect(
        storage.getUnlockedAchievements().keys,
        contains('some_prior_achievement'),
      );
    });

    test('업적 저장 도중(이미 새 업적을 기록한 뒤) 예외가 나면 goal·quest·새 업적이 모두 '
        '롤백되고 이전부터 있던 업적은 남는다', () async {
      final storage = await createTestStorage();
      // 이 호출 이전에 이미 해금된 업적 — 롤백이 unlockedBefore/After의
      // 차집합만 지우는지(새로 생긴 first_goal_set만 지우고 이건
      // 건드리지 않는지) 검증한다.
      await storage.unlockAchievement(
        'some_prior_achievement',
        DateTime(2026, 1, 1),
      );

      final container = ProviderContainer(
        overrides: [
          storageServiceProvider.overrideWithValue(storage),
          // GoalService는 오버라이드하지 않는다 — 로컬 규칙 폴백이
          // kickoff 퀘스트를 포함해 정상적으로 여러 개를 만들어내는
          // "정상 decomposition" 경로를 그대로 쓴다. 실패는 그 다음
          // 단계인 achievement 체크에서만 발생시킨다.
          achievementServiceProvider.overrideWithValue(
            _UnlocksThenThrowsAchievementService(storage),
          ),
        ],
      );
      addTearDown(container.dispose);

      final goal = _goal('g1');
      await expectLater(
        container
            .read(goalsProvider.notifier)
            .createGoal(goal, requireQuests: true),
        throwsA(isA<StateError>()),
      );

      // goal도, 정상 분해로 만들어졌던 quest들도 남아 있지 않다.
      expect(storage.getGoals(), isEmpty);
      expect(storage.getQuests(), isEmpty);
      // 이 호출 도중 새로 쓰여진 업적은 롤백된다...
      expect(
        storage.getUnlockedAchievements().keys,
        isNot(contains('first_goal_set')),
      );
      // ...하지만 이 호출 이전부터 있던 업적은 그대로 남는다.
      expect(
        storage.getUnlockedAchievements().keys,
        contains('some_prior_achievement'),
      );
      expect(storage.getProfile().onboardingCompleted, isFalse);
    });

    test('퀘스트 저장 도중 예외가 나면 goal과 이미 추가된 quest, 새로 해금된 업적까지 모두 롤백된다', () async {
      final storage = await _faultyCreateStorage();
      // 로컬 규칙 분해는 kickoff 퀘스트를 포함해 여러 개를 만든다 —
      // 두 번째 quest 저장에서 실패하도록 해 "일부만 저장된" 상태를
      // 재현한다.
      storage.throwOnSaveQuestCall = 2;
      final container = ProviderContainer(
        overrides: [storageServiceProvider.overrideWithValue(storage)],
      );
      addTearDown(container.dispose);

      final goal = _goal('g1');
      await expectLater(
        container
            .read(goalsProvider.notifier)
            .createGoal(goal, requireQuests: true),
        throwsA(isA<StateError>()),
      );

      // goal도, 첫 번째로 저장됐던 quest도 남아 있지 않다 — 부분 상태가 없다.
      expect(storage.getGoals(), isEmpty);
      expect(storage.getQuests(), isEmpty);
      // 이 호출로 새로 해금됐을 'first_goal_set' 업적도 되돌려진다.
      expect(storage.getUnlockedAchievements(), isEmpty);
      // 실제로 착지했던 quest 2개(kickoff + 2번째)와 goal 1개가 진짜
      // delete로 되돌려졌다 — 단순 aliasing이 아니라 실 롤백 write.
      expect(storage.deleteQuestCalls, 2);
      expect(storage.deleteGoalCalls, 1);
    });

    test(
      '일반 GoalFormScreen 경로(requireQuests 기본값 false)는 빈 분해에서도 여전히 성공한다',
      () async {
        final storage = await createTestStorage();
        final container = ProviderContainer(
          overrides: [
            storageServiceProvider.overrideWithValue(storage),
            goalServiceProvider.overrideWithValue(_NoQuestGoalService(storage)),
          ],
        );
        addTearDown(container.dispose);

        final result = await container
            .read(goalsProvider.notifier)
            .createGoal(_goal('g1'));

        expect(result.quests, isEmpty);
        expect(storage.getGoals(), hasLength(1));
        // 목표가 저장됐으니 '목표 설정' 업적은 정상적으로 해금된다.
        expect(
          storage.getUnlockedAchievements().keys,
          contains('first_goal_set'),
        );
      },
    );
  });

  group('createGoal — 원자성/롤백 (일반 트랜잭션)', () {
    test('goal 저장 자체가 실제로 착지한 뒤 실패하면, 롤백이 진짜 deleteGoal 호출로 되돌린다', () async {
      final storage = await _faultyCreateStorage();
      // 퀘스트가 하나도 없으면 실패 지점은 goal 저장 그 자체뿐이다.
      storage.throwOnSaveGoalCall = 1;
      final container = ProviderContainer(
        overrides: [
          storageServiceProvider.overrideWithValue(storage),
          goalServiceProvider.overrideWithValue(_NoQuestGoalService(storage)),
        ],
      );
      addTearDown(container.dispose);

      await expectLater(
        container.read(goalsProvider.notifier).createGoal(_goal('g1')),
        throwsA(isA<StateError>()),
      );

      expect(storage.getGoal('g1'), isNull);
      expect(storage.getGoals(), isEmpty);
      // saveGoal actually landed once, and rollback issued one real delete
      // — not merely a guard that skipped an unperformed write.
      expect(storage.saveGoalCalls, 1);
      expect(storage.deleteGoalCalls, 1);
    });

    test(
      '동시에 같은 id로 목표를 만들면 하나만 성공하고 나머지는 충돌을 보고하며, 중복 퀘스트도 생기지 않는다',
      () async {
        final storage = await createTestStorage();
        final entered = Completer<void>();
        final release = Completer<void>();
        final container = ProviderContainer(
          overrides: [
            storageServiceProvider.overrideWithValue(storage),
            goalServiceProvider.overrideWith(
              (ref) => _GatedDecomposeGoalService(
                storage,
                entered: entered,
                release: release,
              ),
            ),
          ],
        );
        addTearDown(container.dispose);
        final notifier = container.read(goalsProvider.notifier);

        // First call's decomposition is gated — it starts, but doesn't reach
        // the shared lock until released.
        final firstFuture = notifier.createGoal(_goal('dup'));
        await entered.future;

        // Second call for the *same* goal id decomposes immediately (this
        // service only gates its first call), reaches the lock first, and
        // creates the goal successfully.
        final secondFuture = notifier.createGoal(_goal('dup'));
        final secondResult = await secondFuture;

        // Release the first call: its decomposition finishes, it reaches the
        // lock, and must now observe the goal id already taken.
        release.complete();
        await expectLater(
          firstFuture,
          throwsA(isA<GoalAlreadyExistsException>()),
        );

        expect(storage.getGoals(), hasLength(1));
        final linkedQuests = storage
            .getQuests()
            .where((q) => q.goalId == 'dup')
            .toList();
        expect(linkedQuests.length, secondResult.quests.length);
        // No quest from the losing (first) call's decomposition survives.
        for (final q in secondResult.quests) {
          expect(storage.getQuest(q.id), isNotNull);
        }
      },
    );
  });

  group('createGoal — 퀘스트 완료 큐잉과의 상호작용', () {
    test('성공한 생성 뒤에 큐잉된 완료는 커밋된 퀘스트를 관찰하고 정확히 한 번만 완료되며, 목표도 자동완료된다', () async {
      final storage = await createTestStorage();
      final entered = Completer<void>();
      final release = Completer<void>();
      final container = ProviderContainer(
        overrides: [
          storageServiceProvider.overrideWithValue(storage),
          goalServiceProvider.overrideWithValue(
            _SingleFixedQuestGoalService(storage),
          ),
          achievementServiceProvider.overrideWith(
            (ref) => _GatedAchievementService(
              ref.watch(storageServiceProvider),
              entered: entered,
              release: release,
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      final goal = _goal('g1');
      final createFuture = container
          .read(goalsProvider.notifier)
          .createGoal(goal);
      // createGoal is now blocked inside its achievement check — goal and
      // quest are already physically saved, but nothing has been reloaded
      // into providers yet, and the lock is still held.
      await entered.future;

      // A completion for the not-yet-published quest queues behind the
      // still-held lock.
      final completeFuture = container
          .read(questsProvider.notifier)
          .completeQuest('${goal.id}-quest');

      // Let createGoal finish its (successful) achievement check.
      release.complete();

      final createResult = await createFuture;
      expect(createResult.quests, hasLength(1));

      final completeResult = await completeFuture;
      // The queued completion observed the committed quest (not a missing
      // one) and was awarded exactly once.
      expect(completeResult.levelUps, isNotEmpty);
      final quest = storage.getQuests().single;
      expect(quest.status, QuestStatus.completed);
      // It was this quest's only linked quest, so completing it auto-
      // completed the goal too — the completion bonus adds on top of the
      // quest's own reward (goal-linked quests earn a 1.5x multiplier: 20 *
      // 1.5 = 30), so total XP reflects both, not a partial or double
      // award: 30 + goalCompletionBonusXp (100) = 130, which rolls the
      // level-1 threshold (100) over into level 2 with 30 XP left.
      final goalAfter = storage.getGoal(goal.id)!;
      expect(goalAfter.status, GoalStatus.completed);
      expect(storage.getStat('health')!.level, 2);
      expect(storage.getStat('health')!.currentXp, 30);
    });

    test('실패한 생성 뒤에 큐잉된 완료는 퀘스트를 전혀 보지 못하고 XP도 0이다', () async {
      final storage = await createTestStorage();
      final entered = Completer<void>();
      final release = Completer<void>();
      final container = ProviderContainer(
        overrides: [
          storageServiceProvider.overrideWithValue(storage),
          goalServiceProvider.overrideWithValue(
            _SingleFixedQuestGoalService(storage),
          ),
          achievementServiceProvider.overrideWith(
            (ref) => _GatedAchievementService(
              ref.watch(storageServiceProvider),
              entered: entered,
              release: release,
              throwAfterRelease: true,
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      final goal = _goal('g1');
      final createFuture = container
          .read(goalsProvider.notifier)
          .createGoal(goal);
      await entered.future;

      // Dispatched while the (doomed) create still holds the lock.
      final completeFuture = container
          .read(questsProvider.notifier)
          .completeQuest('${goal.id}-quest');

      release.complete();
      await expectLater(createFuture, throwsA(isA<StateError>()));

      final completeResult = await completeFuture;
      // The quest never existed by the time this completion actually ran
      // (create rolled it back before handing off the lock) — a safe no-op,
      // not an error, and definitely not an XP award. ('health' still has
      // its seeded default Stat record — only its XP/level must stay
      // untouched.)
      expect(completeResult.levelUps, isEmpty);
      expect(storage.getStat('health')!.currentXp, 0);
      expect(storage.getStat('health')!.level, 1);
      expect(storage.getQuests(), isEmpty);
      expect(storage.getGoals(), isEmpty);
    });

    test(
      '두 번째 quest 저장이 게이트에 걸려 대기하는 동안, provider에는 부분 상태가 전혀 보이지 않는다',
      () async {
        final storage = await createTestStorage();
        final gate = Completer<void>();
        final resumed = Completer<void>();
        final container = ProviderContainer(
          overrides: [
            storageServiceProvider.overrideWithValue(storage),
            goalServiceProvider.overrideWithValue(
              _TwoFixedQuestGoalService(storage),
            ),
            questsProvider.overrideWith(
              (ref) => _GatedSecondAddQuestNotifier(
                ref.watch(storageServiceProvider),
                ref,
                gate: gate,
                resumed: resumed,
              ),
            ),
          ],
        );
        addTearDown(container.dispose);

        final goal = _goal('g1');
        final createFuture = container
            .read(goalsProvider.notifier)
            .createGoal(goal);

        await resumed.future;
        // The first quest has already physically landed in storage, but
        // createGoal hasn't reloaded/published anything yet (it only does so
        // once, at the very end) — so the provider's published list, and any
        // fresh read of it, must still show nothing.
        expect(container.read(questsProvider), isEmpty);
        expect(container.read(goalsProvider), isEmpty);

        gate.complete();
        final result = await createFuture;

        expect(result.quests, hasLength(2));
        expect(container.read(questsProvider), hasLength(2));
        expect(container.read(goalsProvider), hasLength(1));
      },
    );
  });
}

/// Always returns exactly two quests linked to [goal.id], with stable,
/// predictable ids — used by the partial-state-visibility test so the
/// second (gated) quest can be identified deterministically.
class _TwoFixedQuestGoalService extends GoalService {
  _TwoFixedQuestGoalService(StorageService storage) : super(storage: storage);

  @override
  Future<List<Quest>> decompose(Goal goal, {int count = 4}) async => [
    Quest(
      id: '${goal.id}-quest-1',
      title: '${goal.title} 1',
      description: '',
      statRewards: {goal.statId: 20},
      status: QuestStatus.active,
      source: QuestSource.manual,
      createdAt: DateTime(2026, 7, 14),
      goalId: goal.id,
    ),
    Quest(
      id: '${goal.id}-quest-2',
      title: '${goal.title} 2',
      description: '',
      statRewards: {goal.statId: 10},
      status: QuestStatus.active,
      source: QuestSource.manual,
      createdAt: DateTime(2026, 7, 14),
      goalId: goal.id,
    ),
  ];
}

/// A QuestsNotifier whose [addQuestLocked] blocks *before* saving the second
/// quest it's asked to add, until [gate] completes — signalling [resumed]
/// right after the first quest has been saved for real. Lets a test observe
/// provider state while createGoal's transaction is genuinely mid-flight
/// (one quest physically landed, one pending), without any timing-based
/// sleep.
class _GatedSecondAddQuestNotifier extends QuestsNotifier {
  _GatedSecondAddQuestNotifier(
    super.storage,
    super.ref, {
    required this.gate,
    required this.resumed,
  });

  final Completer<void> gate;
  final Completer<void> resumed;
  int _calls = 0;

  @override
  Future<void> addQuestLocked(Quest quest, RollbackScope rollback) async {
    _calls++;
    if (_calls == 2) {
      resumed.complete();
      await gate.future;
    }
    return super.addQuestLocked(quest, rollback);
  }
}
