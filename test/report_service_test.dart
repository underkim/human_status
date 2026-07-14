import 'package:flutter_test/flutter_test.dart';
import 'package:human_status/models/goal.dart';
import 'package:human_status/models/quest.dart';
import 'package:human_status/models/transaction.dart';
import 'package:human_status/services/report_service.dart';

Quest _completedQuest(String id, DateTime completedAt, Map<String, double> rewards) => Quest(
      id: id,
      title: id,
      description: '',
      statRewards: rewards,
      status: QuestStatus.completed,
      createdAt: completedAt,
      completedAt: completedAt,
    );

Transaction _tx(String id, TransactionType type, String category, double amount, DateTime date) =>
    Transaction(
      id: id,
      type: type,
      category: category,
      memo: '',
      amount: amount,
      date: date,
      createdAt: date,
    );

void main() {
  group('ReportService.periodRange', () {
    test('주간: 월요일 시작, 7일 뒤가 끝(배타)', () {
      // 2026-07-13은 월요일.
      final (start, end) = ReportService.periodRange(ReportPeriod.weekly, DateTime(2026, 7, 15, 14, 30));
      expect(start, DateTime(2026, 7, 13));
      expect(end, DateTime(2026, 7, 20));
    });

    test('주간: periodsAgo=1이면 지난주 월~일', () {
      final (start, end) =
          ReportService.periodRange(ReportPeriod.weekly, DateTime(2026, 7, 13), periodsAgo: 1);
      expect(start, DateTime(2026, 7, 6));
      expect(end, DateTime(2026, 7, 13));
    });

    test('주간: 연초를 걸치는 주도 달력 계산으로 이어진다', () {
      // 2026-01-01은 목요일 → 그 주의 월요일은 2025-12-29.
      final (start, end) = ReportService.periodRange(ReportPeriod.weekly, DateTime(2026, 1, 1));
      expect(start, DateTime(2025, 12, 29));
      expect(end, DateTime(2026, 1, 5));
    });

    test('월간: 1일 시작, 다음 달 1일이 끝', () {
      final (start, end) = ReportService.periodRange(ReportPeriod.monthly, DateTime(2026, 7, 13));
      expect(start, DateTime(2026, 7, 1));
      expect(end, DateTime(2026, 8, 1));
    });

    test('월간: periodsAgo가 1월을 지나면 전년도로 넘어간다', () {
      final (start, end) =
          ReportService.periodRange(ReportPeriod.monthly, DateTime(2026, 1, 15), periodsAgo: 2);
      expect(start, DateTime(2025, 11, 1));
      expect(end, DateTime(2025, 12, 1));
    });
  });

  group('ReportService.build', () {
    final start = DateTime(2026, 7, 6);
    final end = DateTime(2026, 7, 13);

    test('기간 안의 완료 퀘스트만 집계하고 스텟별 XP를 합산한다', () {
      final report = ReportService.build(
        quests: [
          _completedQuest('in1', DateTime(2026, 7, 6), {'health': 30}),
          _completedQuest('in2', DateTime(2026, 7, 12, 23, 59), {'health': 20, 'mental': 10}),
          _completedQuest('before', DateTime(2026, 7, 5, 23, 59), {'health': 99}),
          _completedQuest('after', DateTime(2026, 7, 13), {'health': 99}),
          // 미완료 퀘스트는 completedAt이 있어도 세지 않는다.
          Quest(
            id: 'active',
            title: 'active',
            description: '',
            statRewards: {'health': 50},
            createdAt: DateTime(2026, 7, 7),
          ),
        ],
        goals: [],
        transactions: [],
        start: start,
        end: end,
      );

      expect(report.questsCompleted, 2);
      expect(report.xpEarned, 60);
      expect(report.xpByStat, {'health': 50, 'mental': 10});
      expect(report.topStatId, 'health');
    });

    test('기간 안에 달성한 목표 제목을 모은다', () {
      final report = ReportService.build(
        quests: [],
        goals: [
          Goal(
            id: 'g1',
            title: '달성한 목표',
            description: '',
            statId: 'health',
            status: GoalStatus.completed,
            createdAt: DateTime(2026, 6, 1),
            completedAt: DateTime(2026, 7, 10),
          ),
          Goal(
            id: 'g2',
            title: '기간 밖 목표',
            description: '',
            statId: 'health',
            status: GoalStatus.completed,
            createdAt: DateTime(2026, 6, 1),
            completedAt: DateTime(2026, 7, 1),
          ),
          Goal(
            id: 'g3',
            title: '진행중 목표',
            description: '',
            statId: 'health',
            createdAt: DateTime(2026, 6, 1),
          ),
        ],
        transactions: [],
        start: start,
        end: end,
      );

      expect(report.goalsCompleted, 1);
      expect(report.completedGoalTitles, ['달성한 목표']);
    });

    test('수입/지출을 나눠 합산하고 최다 지출 카테고리를 찾는다', () {
      final report = ReportService.build(
        quests: [],
        goals: [],
        transactions: [
          _tx('t1', TransactionType.income, '급여', 3000000, DateTime(2026, 7, 10)),
          _tx('t2', TransactionType.expense, '식비', 50000, DateTime(2026, 7, 8)),
          _tx('t3', TransactionType.expense, '식비', 30000, DateTime(2026, 7, 9)),
          _tx('t4', TransactionType.expense, '교통', 60000, DateTime(2026, 7, 9)),
          _tx('out', TransactionType.expense, '식비', 999999, DateTime(2026, 7, 5)),
        ],
        start: start,
        end: end,
      );

      expect(report.income, 3000000);
      expect(report.expense, 140000);
      expect(report.net, 2860000);
      expect(report.topExpenseCategory, '식비');
      expect(report.topExpenseAmount, 80000);
    });

    test('아무 활동이 없으면 isEmpty', () {
      final report =
          ReportService.build(quests: [], goals: [], transactions: [], start: start, end: end);
      expect(report.isEmpty, isTrue);
      expect(report.topStatId, isNull);
      expect(report.topExpenseCategory, isNull);
    });
  });
}
