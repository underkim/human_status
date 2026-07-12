import 'package:flutter_test/flutter_test.dart';
import 'package:human_status/models/quest.dart';
import 'package:human_status/services/stats_insights_service.dart';
import 'package:uuid/uuid.dart';

Quest _completedOn(DateTime day, {double xp = 10}) {
  return Quest(
    id: const Uuid().v4(),
    title: 'q',
    description: '',
    statRewards: {'health': xp},
    status: QuestStatus.completed,
    createdAt: day,
    completedAt: day,
  );
}

void main() {
  group('currentStreak', () {
    test('is 0 with no completed quests', () {
      expect(StatsInsightsService.currentStreak([]), 0);
    });

    test('counts today alone as a streak of 1', () {
      final today = DateTime.now();
      expect(StatsInsightsService.currentStreak([_completedOn(today)]), 1);
    });

    test('stays alive if yesterday had a completion but today does not yet', () {
      final yesterday = DateTime.now().subtract(const Duration(days: 1));
      expect(StatsInsightsService.currentStreak([_completedOn(yesterday)]), 1);
    });

    test('breaks when a day is skipped', () {
      final today = DateTime.now();
      final twoDaysAgo = today.subtract(const Duration(days: 2));
      final quests = [_completedOn(today), _completedOn(twoDaysAgo)];
      // yesterday is missing, so the streak only covers today.
      expect(StatsInsightsService.currentStreak(quests), 1);
    });

    test('counts consecutive days correctly', () {
      final today = DateTime.now();
      final quests = [
        _completedOn(today),
        _completedOn(today.subtract(const Duration(days: 1))),
        _completedOn(today.subtract(const Duration(days: 2))),
      ];
      expect(StatsInsightsService.currentStreak(quests), 3);
    });
  });

  group('xpByDay', () {
    test('sums xp per day and fills days with no completions with 0', () {
      final today = DateTime.now();
      final quests = [
        _completedOn(today, xp: 10),
        _completedOn(today, xp: 5),
      ];
      final result = StatsInsightsService.xpByDay(quests, days: 3);

      expect(result.length, 3);
      final todayKey = DateTime(today.year, today.month, today.day);
      expect(result[todayKey], 15);
      final yesterdayKey = todayKey.subtract(const Duration(days: 1));
      expect(result[yesterdayKey], 0);
    });
  });

  group('totalXpByStat', () {
    test('sums xp across stats and quests', () {
      final quests = [
        Quest(
          id: const Uuid().v4(),
          title: 'a',
          description: '',
          statRewards: const {'health': 10, 'mental': 5},
          status: QuestStatus.completed,
          createdAt: DateTime.now(),
          completedAt: DateTime.now(),
        ),
        Quest(
          id: const Uuid().v4(),
          title: 'b',
          description: '',
          statRewards: const {'health': 20},
          status: QuestStatus.completed,
          createdAt: DateTime.now(),
          completedAt: DateTime.now(),
        ),
      ];
      final result = StatsInsightsService.totalXpByStat(quests);
      expect(result['health'], 30);
      expect(result['mental'], 5);
    });
  });
}
