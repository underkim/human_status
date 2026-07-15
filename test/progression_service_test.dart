import 'package:flutter_test/flutter_test.dart';
import 'package:human_status/models/quest.dart';
import 'package:human_status/services/progression_service.dart';
import 'package:uuid/uuid.dart';

Quest _quest({
  required QuestStatus status,
  DateTime? completedAt,
  DateTime? createdAt,
}) {
  return Quest(
    id: const Uuid().v4(),
    title: 'q',
    description: '',
    statRewards: const {'health': 10},
    status: status,
    createdAt: createdAt ?? completedAt ?? DateTime(2026, 1, 1),
    completedAt: completedAt,
  );
}

Quest _completedOn(DateTime day) =>
    _quest(status: QuestStatus.completed, completedAt: day);

void main() {
  group('computeProgressionSnapshot — empty data', () {
    test('returns all-zero, not-alive snapshot for no quests', () {
      final snapshot = computeProgressionSnapshot(
        [],
        now: DateTime(2026, 7, 16),
      );
      expect(snapshot.currentStreak, 0);
      expect(snapshot.longestStreak, 0);
      expect(snapshot.activeDaysThisWeek, 0);
      expect(snapshot.completedToday, isFalse);
    });
  });

  group('currentStreak', () {
    test('is alive and 1 when only today has a completion', () {
      final now = DateTime(2026, 7, 16, 9);
      final snapshot = computeProgressionSnapshot([
        _completedOn(DateTime(2026, 7, 16, 8)),
      ], now: now);
      expect(snapshot.currentStreak, 1);
      expect(snapshot.completedToday, isTrue);
    });

    test('is alive through yesterday when today has no completion yet', () {
      final now = DateTime(2026, 7, 16, 9);
      final snapshot = computeProgressionSnapshot([
        _completedOn(DateTime(2026, 7, 15)),
      ], now: now);
      expect(snapshot.currentStreak, 1);
      expect(snapshot.completedToday, isFalse);
    });

    test('is zero (stale) once both today and yesterday are missed', () {
      final now = DateTime(2026, 7, 16, 9);
      final snapshot = computeProgressionSnapshot([
        _completedOn(DateTime(2026, 7, 13)),
      ], now: now);
      expect(snapshot.currentStreak, 0);
      expect(snapshot.completedToday, isFalse);
    });

    test('duplicate completions on the same day count as a single day', () {
      final now = DateTime(2026, 7, 16, 20);
      final snapshot = computeProgressionSnapshot([
        _completedOn(DateTime(2026, 7, 16, 8)),
        _completedOn(DateTime(2026, 7, 16, 9)),
        _completedOn(DateTime(2026, 7, 16, 19)),
      ], now: now);
      expect(snapshot.currentStreak, 1);
    });

    test('crosses a month boundary without gaps', () {
      final now = DateTime(2026, 8, 1, 9);
      final snapshot = computeProgressionSnapshot([
        _completedOn(DateTime(2026, 7, 30)),
        _completedOn(DateTime(2026, 7, 31)),
        _completedOn(DateTime(2026, 8, 1)),
      ], now: now);
      expect(snapshot.currentStreak, 3);
    });

    test('crosses a year boundary without gaps', () {
      final now = DateTime(2027, 1, 1, 9);
      final snapshot = computeProgressionSnapshot([
        _completedOn(DateTime(2026, 12, 31)),
        _completedOn(DateTime(2027, 1, 1)),
      ], now: now);
      expect(snapshot.currentStreak, 2);
    });

    test('excludes non-completed statuses even with a completedAt set', () {
      final now = DateTime(2026, 7, 16, 9);
      final snapshot = computeProgressionSnapshot([
        _quest(status: QuestStatus.active, completedAt: DateTime(2026, 7, 16)),
        _quest(
          status: QuestStatus.suggested,
          completedAt: DateTime(2026, 7, 16),
        ),
        _quest(
          status: QuestStatus.dismissed,
          completedAt: DateTime(2026, 7, 16),
        ),
      ], now: now);
      expect(snapshot.currentStreak, 0);
      expect(snapshot.completedToday, isFalse);
    });

    test('excludes a completedAt timestamp after now', () {
      final now = DateTime(2026, 7, 16, 9);
      final snapshot = computeProgressionSnapshot([
        _completedOn(DateTime(2026, 7, 16, 23)),
      ], now: now);
      expect(snapshot.currentStreak, 0);
      expect(snapshot.completedToday, isFalse);
    });

    test('excludes a quest with null completedAt', () {
      final now = DateTime(2026, 7, 16, 9);
      final snapshot = computeProgressionSnapshot([
        _quest(status: QuestStatus.completed, completedAt: null),
      ], now: now);
      expect(snapshot.currentStreak, 0);
    });
  });

  group('longestStreak', () {
    test('is the all-time max run, even after the current streak breaks', () {
      final now = DateTime(2026, 7, 20, 9);
      final snapshot = computeProgressionSnapshot([
        _completedOn(DateTime(2026, 7, 1)),
        _completedOn(DateTime(2026, 7, 2)),
        _completedOn(DateTime(2026, 7, 3)),
        _completedOn(DateTime(2026, 7, 4)),
        _completedOn(DateTime(2026, 7, 10)),
        _completedOn(DateTime(2026, 7, 11)),
      ], now: now);
      expect(snapshot.longestStreak, 4);
      expect(snapshot.currentStreak, 0);
    });

    test('is 0 for no completions and 1 for a single isolated day', () {
      expect(computeProgressionSnapshot([]).longestStreak, 0);
      final now = DateTime(2026, 7, 16, 9);
      final snapshot = computeProgressionSnapshot([
        _completedOn(DateTime(2026, 7, 10)),
      ], now: now);
      expect(snapshot.longestStreak, 1);
    });
  });

  group('activeDaysThisWeek', () {
    test('counts unique active days from Monday through now, inclusive', () {
      // 2026-07-16 is a Thursday; that week's Monday is 2026-07-13.
      final now = DateTime(2026, 7, 16, 10);
      final snapshot = computeProgressionSnapshot([
        _completedOn(DateTime(2026, 7, 13)), // Mon
        _completedOn(DateTime(2026, 7, 14)), // Tue
        _completedOn(DateTime(2026, 7, 14, 22)), // Tue dup, different time
        _completedOn(DateTime(2026, 7, 16, 9)), // Thu (today)
      ], now: now);
      expect(snapshot.activeDaysThisWeek, 3);
    });

    test(
      'excludes days from the previous week and future days in this week',
      () {
        final now = DateTime(2026, 7, 16, 10); // Thursday
        final snapshot = computeProgressionSnapshot([
          _completedOn(DateTime(2026, 7, 12)), // previous Sunday
          _completedOn(DateTime(2026, 7, 18)), // this Saturday (future)
        ], now: now);
        expect(snapshot.activeDaysThisWeek, 0);
      },
    );

    test('is 0..7, capping at a full Mon-through-today window', () {
      // Monday itself: only "today" can count.
      final monday = DateTime(2026, 7, 13, 10);
      final snapshot = computeProgressionSnapshot([
        _completedOn(monday),
      ], now: monday);
      expect(snapshot.activeDaysThisWeek, 1);
    });

    test('reaches 7 when every day this week through Sunday is active', () {
      final sunday = DateTime(2026, 7, 19, 10);
      final quests = [
        for (var d = 13; d <= 19; d++) _completedOn(DateTime(2026, 7, d)),
      ];
      final snapshot = computeProgressionSnapshot(quests, now: sunday);
      expect(snapshot.activeDaysThisWeek, 7);
    });
  });

  group('completedToday', () {
    test('is true only when today itself has a valid completion', () {
      final now = DateTime(2026, 7, 16, 12);
      expect(
        computeProgressionSnapshot([
          _completedOn(DateTime(2026, 7, 16, 8)),
        ], now: now).completedToday,
        isTrue,
      );
      expect(
        computeProgressionSnapshot([
          _completedOn(DateTime(2026, 7, 15)),
        ], now: now).completedToday,
        isFalse,
      );
    });
  });

  group('injected now', () {
    test('produces deterministic results independent of the wall clock', () {
      final fixedNow = DateTime(2026, 3, 1, 12);
      final snapshot = computeProgressionSnapshot([
        _completedOn(DateTime(2026, 3, 1)),
      ], now: fixedNow);
      expect(snapshot.currentStreak, 1);
      expect(snapshot.completedToday, isTrue);
    });
  });
}
