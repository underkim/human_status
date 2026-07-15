import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:human_status/models/goal.dart';
import 'package:human_status/models/quest.dart';
import 'package:human_status/models/stat.dart';
import 'package:human_status/services/goal_service.dart';
import 'package:human_status/services/storage_service.dart';
import 'package:uuid/uuid.dart';

import 'helpers/test_app.dart';

/// Always throws, simulating a timed-out or otherwise failed Claude request.
class _AlwaysFailsSource implements GoalDecompositionSource {
  @override
  Future<List<Quest>> decompose({
    required Goal goal,
    required List<Stat> stats,
    required List<Quest> existingQuests,
    int count = 4,
  }) {
    throw TimeoutException('simulated timeout');
  }
}

Goal _goal({
  double? targetAmount,
  double currentAmount = 0,
  GoalStatus status = GoalStatus.active,
}) {
  return Goal(
    id: 'g1',
    title: '테스트 목표',
    description: '',
    statId: 'wealth',
    targetAmount: targetAmount,
    currentAmount: currentAmount,
    status: status,
    createdAt: DateTime.now(),
  );
}

Quest _quest({
  required String goalId,
  QuestStatus status = QuestStatus.active,
}) {
  return Quest(
    id: const Uuid().v4(),
    title: 'q',
    description: '',
    statRewards: const {'wealth': 20},
    status: status,
    createdAt: DateTime.now(),
    goalId: goalId,
  );
}

void main() {
  group('LocalRuleGoalDecompositionSource', () {
    final source = LocalRuleGoalDecompositionSource(uuid: const Uuid());

    test('generates quests linked to the goal, matching its statId', () async {
      final goal = _goal();
      final quests = await source.decompose(
        goal: goal,
        stats: [],
        existingQuests: [],
        count: 3,
      );

      expect(quests, hasLength(3));
      for (final q in quests) {
        expect(q.goalId, goal.id);
        expect(q.statRewards.keys, contains(goal.statId));
        expect(q.status, QuestStatus.active);
      }
    });

    test(
      'always includes a kick-off quest referencing the goal title',
      () async {
        final goal = _goal();
        final quests = await source.decompose(
          goal: goal,
          stats: [],
          existingQuests: [],
          count: 1,
        );
        expect(quests.first.title, contains(goal.title));
      },
    );
  });

  group('GoalService.progress', () {
    final service = GoalService(storage: StorageService());

    test(
      'financial goal progress is currentAmount/targetAmount, clamped to 1',
      () {
        expect(
          service.progress(_goal(targetAmount: 100, currentAmount: 50), []),
          0.5,
        );
        expect(
          service.progress(_goal(targetAmount: 100, currentAmount: 200), []),
          1.0,
        );
      },
    );

    test(
      'financial goal with a zero target guards against division by zero',
      () {
        expect(
          service.progress(_goal(targetAmount: 0, currentAmount: 0), []),
          0.0,
        );
      },
    );

    test(
      'non-financial goal progress is the linked-quest completion ratio',
      () {
        final goal = _goal();
        final quests = [
          _quest(goalId: goal.id, status: QuestStatus.completed),
          _quest(goalId: goal.id, status: QuestStatus.active),
        ];
        expect(service.progress(goal, quests), 0.5);
      },
    );

    test('non-financial goal with no linked quests has 0 progress', () {
      expect(service.progress(_goal(), []), 0.0);
    });
  });

  group('GoalService.isAutoCompletable', () {
    final service = GoalService(storage: StorageService());

    test('false when there are no linked quests', () {
      expect(service.isAutoCompletable(_goal(), []), isFalse);
    });

    test('false when any linked quest is still active or suggested', () {
      final goal = _goal();
      final quests = [
        _quest(goalId: goal.id, status: QuestStatus.completed),
        _quest(goalId: goal.id, status: QuestStatus.active),
      ];
      expect(service.isAutoCompletable(goal, quests), isFalse);
    });

    test(
      'true when all linked quests are resolved and at least one completed',
      () {
        final goal = _goal();
        final quests = [
          _quest(goalId: goal.id, status: QuestStatus.completed),
          _quest(goalId: goal.id, status: QuestStatus.dismissed),
        ];
        expect(service.isAutoCompletable(goal, quests), isTrue);
      },
    );

    test('false for financial goals regardless of quest state', () {
      final goal = _goal(targetAmount: 100, currentAmount: 100);
      final quests = [_quest(goalId: goal.id, status: QuestStatus.completed)];
      expect(service.isAutoCompletable(goal, quests), isFalse);
    });

    test('false when the goal is not active', () {
      final goal = _goal(status: GoalStatus.completed);
      final quests = [_quest(goalId: goal.id, status: QuestStatus.completed)];
      expect(service.isAutoCompletable(goal, quests), isFalse);
    });
  });

  group('GoalService.decompose fallback', () {
    test(
      'a Claude timeout falls back to the local rule engine, still returning quests for the goal',
      () async {
        final storage = await createTestStorage();
        final service = GoalService(
          storage: storage,
          source: _AlwaysFailsSource(),
        );
        final goal = _goal();

        final quests = await service.decompose(goal, count: 2);

        expect(quests, isNotEmpty);
        expect(quests.every((q) => q.goalId == goal.id), isTrue);
      },
    );
  });
}
