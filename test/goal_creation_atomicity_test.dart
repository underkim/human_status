import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:human_status/data/achievement_definitions.dart';
import 'package:human_status/models/goal.dart';
import 'package:human_status/models/quest.dart';
import 'package:human_status/providers/goal_provider.dart';
import 'package:human_status/providers/profile_provider.dart';
import 'package:human_status/providers/quest_provider.dart';
import 'package:human_status/services/achievement_service.dart';
import 'package:human_status/services/goal_service.dart';
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

/// N번째 addQuest 호출에서 던지는 QuestsNotifier — 목표는 이미 저장된 뒤,
/// 퀘스트를 하나씩 추가하는 도중 예외가 나는 상황을 재현한다.
class _ThrowsOnNthAddQuestNotifier extends QuestsNotifier {
  _ThrowsOnNthAddQuestNotifier(super.storage, super.ref, this._throwOnCall);

  final int _throwOnCall;
  int _calls = 0;

  @override
  Future<void> addQuest(Quest quest) async {
    _calls++;
    if (_calls == _throwOnCall) {
      throw StateError('simulated quest save failure');
    }
    await super.addQuest(quest);
  }
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
      final storage = await createTestStorage();
      final container = ProviderContainer(
        overrides: [
          storageServiceProvider.overrideWithValue(storage),
          // 로컬 규칙 분해는 kickoff 퀘스트를 포함해 여러 개를 만든다 —
          // 두 번째 addQuest 호출에서 실패하도록 해 "일부만 저장된" 상태를
          // 재현한다.
          questsProvider.overrideWith(
            (ref) => _ThrowsOnNthAddQuestNotifier(
              ref.watch(storageServiceProvider),
              ref,
              2,
            ),
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

      // goal도, 첫 번째로 저장됐던 quest도 남아 있지 않다 — 부분 상태가 없다.
      expect(storage.getGoals(), isEmpty);
      expect(storage.getQuests(), isEmpty);
      // 이 호출로 새로 해금됐을 'first_goal_set' 업적도 되돌려진다.
      expect(storage.getUnlockedAchievements(), isEmpty);
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
}
