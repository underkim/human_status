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

  group('completionCountByDay', () {
    test('covers full Monday→Sunday weeks and counts completions per day', () {
      // 2026-07-14는 화요일 → 이번 주 일요일은 7/19, 4주면 시작은 6/22(월).
      final now = DateTime(2026, 7, 14, 10);
      final quests = [
        _completedOn(DateTime(2026, 7, 14, 9)),
        _completedOn(DateTime(2026, 7, 14, 20)), // 같은 날 2건
        _completedOn(DateTime(2026, 6, 22, 8)), // 창 시작일
        _completedOn(DateTime(2026, 6, 1)), // 창 밖
      ];

      final result = StatsInsightsService.completionCountByDay(quests, now: now, weeks: 4);

      expect(result.length, 28); // 4주 * 7일
      expect(result.keys.first, DateTime(2026, 6, 22)); // 월요일 시작
      expect(result.keys.last, DateTime(2026, 7, 19)); // 일요일 끝
      expect(result[DateTime(2026, 7, 14)], 2);
      expect(result[DateTime(2026, 6, 22)], 1);
      expect(result[DateTime(2026, 6, 1)], isNull); // 창 밖은 포함 안 됨
      expect(result[DateTime(2026, 7, 13)], 0); // 완료 없는 날은 0
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

    test('counts the 1.5x bonus of goal-linked quests, matching what was awarded', () {
      final quest = Quest(
        id: const Uuid().v4(),
        title: 'linked',
        description: '',
        statRewards: const {'health': 20},
        status: QuestStatus.completed,
        goalId: 'g1',
        createdAt: DateTime.now(),
        completedAt: DateTime.now(),
      );

      expect(StatsInsightsService.totalXpByStat([quest])['health'], 30);
      final today = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
      expect(StatsInsightsService.xpByDay([quest], days: 1)[today], 30);
    });
  });
}
