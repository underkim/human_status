import 'package:flutter_test/flutter_test.dart';
import 'package:human_status/models/goal.dart';

void main() {
  group('Goal.copy', () {
    test('모든 필드를 detached 값으로 복제한다', () {
      final original = Goal(
        id: 'g1',
        title: '제목',
        description: '설명',
        statId: 'wealth',
        targetDate: DateTime(2026, 12, 31),
        targetAmount: 1000000,
        currentAmount: 250000,
        status: GoalStatus.completed,
        createdAt: DateTime(2026, 1, 1),
        completedAt: DateTime(2026, 6, 1),
        completionRewardClaimed: true,
      );

      final copy = original.copy();

      expect(copy.id, original.id);
      expect(copy.title, original.title);
      expect(copy.description, original.description);
      expect(copy.statId, original.statId);
      expect(copy.targetDate, original.targetDate);
      expect(copy.targetAmount, original.targetAmount);
      expect(copy.currentAmount, original.currentAmount);
      expect(copy.status, original.status);
      expect(copy.createdAt, original.createdAt);
      expect(copy.completedAt, original.completedAt);
      expect(copy.completionRewardClaimed, original.completionRewardClaimed);

      // detached — mutating the copy never touches the original.
      copy.title = '바뀐 제목';
      copy.description = '바뀐 설명';
      copy.targetDate = DateTime(2027, 1, 1);
      copy.targetAmount = 2000000;
      copy.currentAmount = 500000;
      copy.status = GoalStatus.active;
      copy.completedAt = null;
      copy.completionRewardClaimed = false;

      expect(original.title, '제목');
      expect(original.description, '설명');
      expect(original.targetDate, DateTime(2026, 12, 31));
      expect(original.targetAmount, 1000000);
      expect(original.currentAmount, 250000);
      expect(original.status, GoalStatus.completed);
      expect(original.completedAt, DateTime(2026, 6, 1));
      expect(original.completionRewardClaimed, isTrue);
    });

    test('null 가능 필드가 비어있을 때도 정확히 복제한다', () {
      final original = Goal(
        id: 'g2',
        title: '제목',
        description: '',
        statId: 'health',
        createdAt: DateTime(2026, 1, 1),
      );

      final copy = original.copy();

      expect(copy.targetDate, isNull);
      expect(copy.targetAmount, isNull);
      expect(copy.completedAt, isNull);
      expect(copy.completionRewardClaimed, isFalse);
    });
  });
}
