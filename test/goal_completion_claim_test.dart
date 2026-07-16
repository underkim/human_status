import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
// Hive's binary reader/writer implementations aren't exported from the
// public `hive.dart` barrel — this is the only way to drive
// GoalAdapter.read/write through the real Hive binary format instead of
// constructing a Goal object directly and asserting on its constructor
// defaults (see user_profile_adapter_test.dart for the same pattern).
import 'package:hive/src/binary/binary_reader_impl.dart';
import 'package:hive/src/binary/binary_writer_impl.dart';
import 'package:human_status/models/goal.dart';
import 'package:human_status/providers/goal_provider.dart';
import 'package:human_status/providers/profile_provider.dart';
import 'package:human_status/services/xp_service.dart';

import 'helpers/test_app.dart';

/// A StatsNotifier whose [applyXp] always throws — used to force a failure
/// right after completeGoalLocked commits status/completedAt/claimed but
/// before the stat XP write lands, so the rollback of all three can be
/// checked together.
class _ThrowsOnApplyXpNotifier extends StatsNotifier {
  _ThrowsOnApplyXpNotifier(super.storage);

  @override
  Future<LevelUpResult> applyXp(String statId, double xp) async {
    throw StateError('simulated stat write failure');
  }
}

void main() {
  group('GoalAdapter — 실제 Hive 바이너리 왕복 (completionRewardClaimed)', () {
    test('필드 10이 없는 legacy 완료 목표는 completionRewardClaimed=true로 읽힌다', () {
      final writer = BinaryWriterImpl(Hive);
      writer
        ..writeByte(10)
        ..writeByte(0)
        ..write('g1')
        ..writeByte(1)
        ..write('제목')
        ..writeByte(2)
        ..write('설명')
        ..writeByte(3)
        ..write('wealth')
        ..writeByte(4)
        ..write(null) // targetDate
        ..writeByte(5)
        ..write(100000.0) // targetAmount
        ..writeByte(6)
        ..write(100000.0) // currentAmount
        ..writeByte(7)
        ..write(GoalStatus.completed.index)
        ..writeByte(8)
        ..write(DateTime(2026, 6, 1)) // createdAt
        ..writeByte(9)
        ..write(DateTime(2026, 6, 2)); // completedAt
      final bytes = writer.toBytes();

      final reader = BinaryReaderImpl(bytes, Hive);
      final goal = GoalAdapter().read(reader);

      expect(goal.status, GoalStatus.completed);
      expect(goal.completionRewardClaimed, isTrue);
      // 다른 필드는 정상적으로 읽혀야 한다 — 필드 인덱스가 밀리지 않았는지 확인.
      expect(goal.id, 'g1');
      expect(goal.targetAmount, 100000.0);
    });

    test('필드 10이 없는 legacy 진행중 목표는 completionRewardClaimed=false로 읽힌다', () {
      final writer = BinaryWriterImpl(Hive);
      writer
        ..writeByte(10)
        ..writeByte(0)
        ..write('g2')
        ..writeByte(1)
        ..write('제목')
        ..writeByte(2)
        ..write('설명')
        ..writeByte(3)
        ..write('wealth')
        ..writeByte(4)
        ..write(null)
        ..writeByte(5)
        ..write(100000.0)
        ..writeByte(6)
        ..write(20000.0)
        ..writeByte(7)
        ..write(GoalStatus.active.index)
        ..writeByte(8)
        ..write(DateTime(2026, 6, 1))
        ..writeByte(9)
        ..write(null);
      final bytes = writer.toBytes();

      final reader = BinaryReaderImpl(bytes, Hive);
      final goal = GoalAdapter().read(reader);

      expect(goal.status, GoalStatus.active);
      expect(goal.completionRewardClaimed, isFalse);
    });

    test('새 필드(completionRewardClaimed)는 실제로 쓰고 읽으면 그대로 왕복한다', () {
      final adapter = GoalAdapter();
      final original = Goal(
        id: 'g3',
        title: '목표',
        description: '',
        statId: 'wealth',
        targetAmount: 50000,
        currentAmount: 50000,
        status: GoalStatus.completed,
        createdAt: DateTime(2026, 7, 1),
        completedAt: DateTime(2026, 7, 2),
        completionRewardClaimed: true,
      );

      final writer = BinaryWriterImpl(Hive);
      adapter.write(writer, original);
      final bytes = writer.toBytes();

      final reader = BinaryReaderImpl(bytes, Hive);
      final roundTripped = adapter.read(reader);

      expect(roundTripped.completionRewardClaimed, isTrue);
      expect(roundTripped.status, GoalStatus.completed);
    });

    test('completionRewardClaimed=false인 완료 목표(재완료 후 재삭제)도 왕복 시 값이 유지된다', () {
      final adapter = GoalAdapter();
      // 방어적으로: 생성자 기본값 추론과 무관하게, 명시적으로 false가 지정된
      // completed 상태도 필드 값 그대로 저장/복원돼야 한다.
      final original = Goal(
        id: 'g4',
        title: '목표',
        description: '',
        statId: 'wealth',
        status: GoalStatus.active,
        createdAt: DateTime(2026, 7, 1),
        completionRewardClaimed: false,
      );

      final writer = BinaryWriterImpl(Hive);
      adapter.write(writer, original);
      final bytes = writer.toBytes();

      final reader = BinaryReaderImpl(bytes, Hive);
      final roundTripped = adapter.read(reader);

      expect(roundTripped.completionRewardClaimed, isFalse);
    });
  });

  group('Goal.toJson/fromJson — completionRewardClaimed', () {
    test('구버전 백업(키 없음, 완료 상태)은 claimed=true로 복원된다', () {
      final json = {
        'id': 'g1',
        'title': '제목',
        'description': '',
        'statId': 'wealth',
        'targetDate': null,
        'targetAmount': 100000.0,
        'currentAmount': 100000.0,
        'status': GoalStatus.completed.index,
        'createdAt': DateTime(2026, 6, 1).toIso8601String(),
        'completedAt': DateTime(2026, 6, 2).toIso8601String(),
      };

      final goal = Goal.fromJson(json);

      expect(goal.completionRewardClaimed, isTrue);
    });

    test('구버전 백업(키 없음, 진행중 상태)은 claimed=false로 복원된다', () {
      final json = {
        'id': 'g2',
        'title': '제목',
        'description': '',
        'statId': 'wealth',
        'targetDate': null,
        'targetAmount': 100000.0,
        'currentAmount': 10000.0,
        'status': GoalStatus.active.index,
        'createdAt': DateTime(2026, 6, 1).toIso8601String(),
        'completedAt': null,
      };

      final goal = Goal.fromJson(json);

      expect(goal.completionRewardClaimed, isFalse);
    });

    test('신규 필드는 JSON 왕복에서 그대로 보존된다', () {
      final original = Goal(
        id: 'g3',
        title: '목표',
        description: '',
        statId: 'wealth',
        status: GoalStatus.active,
        createdAt: DateTime(2026, 7, 1),
        completionRewardClaimed: true,
      );

      final roundTripped = Goal.fromJson(original.toJson());

      expect(roundTripped.completionRewardClaimed, isTrue);
      expect(roundTripped.status, GoalStatus.active);
    });
  });

  group('GoalsNotifier.completeGoalLocked — 평생 1회 보너스', () {
    test('첫 완료는 XP를 지급하고 completionRewardClaimed를 true로 남긴다', () async {
      final storage = await createTestStorage();
      await storage.saveGoal(
        Goal(
          id: 'g1',
          title: '목표',
          description: '',
          statId: 'wealth',
          createdAt: DateTime(2026, 7, 1),
        ),
      );
      final container = ProviderContainer(
        overrides: [storageServiceProvider.overrideWithValue(storage)],
      );
      addTearDown(container.dispose);

      final result = await container
          .read(goalsProvider.notifier)
          .completeGoal('g1');

      // goalCompletionBonusXp (100) exactly equals the level-1 threshold, so
      // a single award leaves the stat at level 2 with 0 leftover XP.
      expect(result.levelUp.levelsGained, 1);
      final goal = storage.getGoal('g1')!;
      expect(goal.status, GoalStatus.completed);
      expect(goal.completionRewardClaimed, isTrue);
      expect(storage.getStat('wealth')!.level, 2);
      expect(storage.getStat('wealth')!.currentXp, 0);
    });

    test('이미 claimed된 목표를 다시 완료하면 상태만 바뀌고 XP는 지급되지 않는다', () async {
      final storage = await createTestStorage();
      // 이미 한 번 완료돼 보너스를 받은 뒤 재오픈된(예: 기여 거래 삭제) 상태를
      // 직접 재현한다: claimed=true인 채로 active.
      await storage.saveGoal(
        Goal(
          id: 'g1',
          title: '목표',
          description: '',
          statId: 'wealth',
          status: GoalStatus.active,
          createdAt: DateTime(2026, 7, 1),
          completionRewardClaimed: true,
        ),
      );
      final wealthBefore = storage.getStat('wealth')!;
      wealthBefore.level = 3;
      wealthBefore.currentXp = 40;
      await storage.saveStat(wealthBefore);

      final container = ProviderContainer(
        overrides: [storageServiceProvider.overrideWithValue(storage)],
      );
      addTearDown(container.dispose);

      final result = await container
          .read(goalsProvider.notifier)
          .completeGoal('g1');

      expect(result.levelUp.levelsGained, 0);
      expect(result.newAchievements, isEmpty);
      final goal = storage.getGoal('g1')!;
      expect(goal.status, GoalStatus.completed);
      expect(goal.completionRewardClaimed, isTrue);
      // XP는 완전히 그대로 — 두 번째 보너스가 지급되지 않았다.
      expect(storage.getStat('wealth')!.level, 3);
      expect(storage.getStat('wealth')!.currentXp, 40);
    });

    test(
      '완료 도중(스탯 지급 실패) completionRewardClaimed도 status/completedAt과 함께 롤백된다',
      () async {
        final storage = await createTestStorage();
        await storage.saveGoal(
          Goal(
            id: 'g1',
            title: '목표',
            description: '',
            statId: 'wealth',
            createdAt: DateTime(2026, 7, 1),
          ),
        );

        final container = ProviderContainer(
          overrides: [
            storageServiceProvider.overrideWithValue(storage),
            statsProvider.overrideWith(
              (ref) =>
                  _ThrowsOnApplyXpNotifier(ref.watch(storageServiceProvider)),
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
        expect(goal.completionRewardClaimed, isFalse);
        expect(storage.getStat('wealth')!.currentXp, 0);
      },
    );
  });
}
