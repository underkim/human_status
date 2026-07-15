import 'package:flutter_test/flutter_test.dart';
import 'package:human_status/models/quest.dart';
import 'package:human_status/services/quest_priority_service.dart';

Quest _quest({
  required String id,
  bool goalLinked = false,
  bool recurring = false,
  QuestDifficulty difficulty = QuestDifficulty.easy,
  DateTime? createdAt,
}) => Quest(
  id: id,
  title: id,
  description: '',
  statRewards: const {'health': 10},
  difficulty: difficulty,
  isRecurring: recurring,
  createdAt: createdAt ?? DateTime(2026, 1, 1),
  goalId: goalLinked ? 'goal-1' : null,
);

void main() {
  group('selectNextQuest', () {
    test('returns null for an empty list', () {
      expect(selectNextQuest([]), isNull);
    });

    test('prefers a goal-linked quest over recurring and plain quests', () {
      final goalLinked = _quest(
        id: 'goal',
        goalLinked: true,
        difficulty: QuestDifficulty.hard,
      );
      final recurring = _quest(
        id: 'recurring',
        recurring: true,
        difficulty: QuestDifficulty.easy,
      );
      final plain = _quest(id: 'plain', difficulty: QuestDifficulty.easy);

      expect(selectNextQuest([plain, recurring, goalLinked])!.id, 'goal');
    });

    test(
      'prefers a recurring quest over a plain quest when no goal-linked quest exists',
      () {
        final recurring = _quest(
          id: 'recurring',
          recurring: true,
          difficulty: QuestDifficulty.hard,
        );
        final plain = _quest(id: 'plain', difficulty: QuestDifficulty.easy);

        expect(selectNextQuest([plain, recurring])!.id, 'recurring');
      },
    );

    test('within the same class, prefers easier difficulty', () {
      final hard = _quest(id: 'hard', difficulty: QuestDifficulty.hard);
      final easy = _quest(id: 'easy', difficulty: QuestDifficulty.easy);
      final medium = _quest(id: 'medium', difficulty: QuestDifficulty.medium);

      expect(selectNextQuest([hard, easy, medium])!.id, 'easy');
    });

    test('ties on difficulty break by older createdAt', () {
      final newer = _quest(id: 'newer', createdAt: DateTime(2026, 2, 1));
      final older = _quest(id: 'older', createdAt: DateTime(2026, 1, 1));

      expect(selectNextQuest([newer, older])!.id, 'older');
    });

    test('ties on difficulty and createdAt break by id', () {
      final createdAt = DateTime(2026, 1, 1);
      final b = _quest(id: 'b', createdAt: createdAt);
      final a = _quest(id: 'a', createdAt: createdAt);

      expect(selectNextQuest([b, a])!.id, 'a');
    });

    test('is deterministic regardless of input order', () {
      final quests = [
        _quest(id: 'plain-2', createdAt: DateTime(2026, 1, 2)),
        _quest(id: 'recurring', recurring: true),
        _quest(id: 'goal', goalLinked: true, difficulty: QuestDifficulty.hard),
        _quest(id: 'plain-1', createdAt: DateTime(2026, 1, 1)),
      ];

      final forward = selectNextQuest(quests)!.id;
      final reversed = selectNextQuest(quests.reversed.toList())!.id;

      expect(forward, 'goal');
      expect(reversed, 'goal');
    });
  });
}
