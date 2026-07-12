import 'package:flutter_test/flutter_test.dart';
import 'package:human_status/models/quest.dart';

void main() {
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
