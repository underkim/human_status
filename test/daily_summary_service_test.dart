import 'package:flutter_test/flutter_test.dart';
import 'package:human_status/models/quest.dart';
import 'package:human_status/services/daily_summary_service.dart';
import 'package:human_status/services/xp_service.dart';

Quest _quest({
  required String id,
  required QuestStatus status,
  DateTime? completedAt,
  String? goalId,
  Map<String, double> statRewards = const {'health': 10},
}) => Quest(
  id: id,
  title: id,
  description: '',
  statRewards: statRewards,
  status: status,
  createdAt: DateTime(2026, 1, 1),
  completedAt: completedAt,
  goalId: goalId,
);

void main() {
  group('computeTodaySummary', () {
    final now = DateTime(2026, 7, 16, 9, 30);

    test('returns zero for no quests', () {
      final summary = computeTodaySummary([], now: now);
      expect(summary.completedCount, 0);
      expect(summary.xp, 0);
    });

    test('counts quests completed today and sums effective XP', () {
      final today1 = _quest(
        id: 'q1',
        status: QuestStatus.completed,
        completedAt: DateTime(2026, 7, 16, 8),
      );
      final today2 = _quest(
        id: 'q2',
        status: QuestStatus.completed,
        completedAt: DateTime(2026, 7, 16, 23, 59),
        statRewards: const {'health': 20},
      );

      final summary = computeTodaySummary([today1, today2], now: now);

      expect(summary.completedCount, 2);
      expect(summary.xp, 30);
    });

    test('excludes quests completed yesterday', () {
      final yesterday = _quest(
        id: 'q1',
        status: QuestStatus.completed,
        completedAt: DateTime(2026, 7, 15, 23, 59),
      );

      final summary = computeTodaySummary([yesterday], now: now);
      expect(summary.completedCount, 0);
      expect(summary.xp, 0);
    });

    test('excludes quests completed in the future', () {
      final future = _quest(
        id: 'q1',
        status: QuestStatus.completed,
        completedAt: DateTime(2026, 7, 17),
      );

      final summary = computeTodaySummary([future], now: now);
      expect(summary.completedCount, 0);
      expect(summary.xp, 0);
    });

    test('excludes non-completed quests even with a completedAt-like date', () {
      final active = _quest(id: 'q1', status: QuestStatus.active);

      final summary = computeTodaySummary([active], now: now);
      expect(summary.completedCount, 0);
      expect(summary.xp, 0);
    });

    test('includes the goal-linked bonus via XpService.effectiveRewards', () {
      final goalQuest = _quest(
        id: 'q1',
        status: QuestStatus.completed,
        completedAt: DateTime(2026, 7, 16, 10),
        goalId: 'goal-1',
        statRewards: const {'health': 10},
      );

      final summary = computeTodaySummary([goalQuest], now: now);

      expect(summary.completedCount, 1);
      expect(summary.xp, 10 * XpService.goalQuestXpMultiplier);
    });

    test('day boundary is local calendar date, not a rolling 24h window', () {
      // Just after local midnight on the same date as `now` — under 10 hours
      // before `now`, but what matters is that year/month/day match.
      final earlyToday = _quest(
        id: 'q1',
        status: QuestStatus.completed,
        completedAt: DateTime(2026, 7, 16, 0, 1),
      );

      final summary = computeTodaySummary([earlyToday], now: now);
      expect(summary.completedCount, 1);
    });
  });
}
