import 'package:flutter_test/flutter_test.dart';
import 'package:human_status/models/quest.dart';

void main() {
  group('Quest.copy', () {
    test('모든 필드를 detached 값으로 복제한다', () {
      final original = Quest(
        id: 'q1',
        title: '제목',
        description: '설명',
        statRewards: {'health': 20, 'wealth': 10},
        difficulty: QuestDifficulty.hard,
        isRecurring: true,
        status: QuestStatus.completed,
        source: QuestSource.suggested,
        createdAt: DateTime(2026, 1, 1),
        completedAt: DateTime(2026, 6, 1),
        goalId: 'g1',
      );

      final copy = original.copy();

      expect(copy.id, original.id);
      expect(copy.title, original.title);
      expect(copy.description, original.description);
      expect(copy.statRewards, original.statRewards);
      expect(copy.difficulty, original.difficulty);
      expect(copy.isRecurring, original.isRecurring);
      expect(copy.status, original.status);
      expect(copy.source, original.source);
      expect(copy.createdAt, original.createdAt);
      expect(copy.completedAt, original.completedAt);
      expect(copy.goalId, original.goalId);

      // detached — mutating the copy (including its statRewards map, which
      // is itself a distinct instance) never touches the original.
      copy.title = '바뀐 제목';
      copy.description = '바뀐 설명';
      copy.statRewards['health'] = 999;
      copy.statRewards['new_stat'] = 5;
      copy.difficulty = QuestDifficulty.easy;
      copy.isRecurring = false;
      copy.status = QuestStatus.active;
      copy.source = QuestSource.manual;
      copy.completedAt = null;
      copy.goalId = null;

      expect(original.title, '제목');
      expect(original.description, '설명');
      expect(original.statRewards, {'health': 20, 'wealth': 10});
      expect(original.difficulty, QuestDifficulty.hard);
      expect(original.isRecurring, isTrue);
      expect(original.status, QuestStatus.completed);
      expect(original.source, QuestSource.suggested);
      expect(original.completedAt, DateTime(2026, 6, 1));
      expect(original.goalId, 'g1');
    });

    test('null 가능 필드가 비어있을 때도 정확히 복제한다', () {
      final original = Quest(
        id: 'q2',
        title: '제목',
        description: '',
        statRewards: const {'health': 10},
        createdAt: DateTime(2026, 1, 1),
      );

      final copy = original.copy();

      expect(copy.completedAt, isNull);
      expect(copy.goalId, isNull);
      expect(copy.difficulty, QuestDifficulty.easy);
      expect(copy.isRecurring, isFalse);
      expect(copy.status, QuestStatus.active);
      expect(copy.source, QuestSource.manual);
    });
  });

  group('Quest.toJson/fromJson', () {
    test('round-trips goalId when set', () {
      final quest = Quest(
        id: 'q1',
        title: 't',
        description: 'd',
        statRewards: const {'health': 10},
        createdAt: DateTime(2026, 1, 1),
        goalId: 'g1',
      );

      final restored = Quest.fromJson(quest.toJson());
      expect(restored.goalId, 'g1');
    });

    test('round-trips a null goalId', () {
      final quest = Quest(
        id: 'q1',
        title: 't',
        description: 'd',
        statRewards: const {'health': 10},
        createdAt: DateTime(2026, 1, 1),
      );

      final restored = Quest.fromJson(quest.toJson());
      expect(restored.goalId, isNull);
    });
  });
}
