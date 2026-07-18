import '../models/quest.dart';
import 'reward_transaction.dart';
import 'storage_service.dart';

/// Makes the '매일 반복' flag actually recur: a recurring quest completed on a
/// previous day respawns as a fresh active quest, once per day.
class RecurringQuestService {
  static final Expando<AsyncLock> _locks = Expando<AsyncLock>();
  final StorageService storage;

  RecurringQuestService({required this.storage});

  /// Respawns recurring quests whose completion is before today (local
  /// midnight). The completed instance keeps its record — stats, streaks and
  /// reports all read completedAt — but hands the recurring flag to the
  /// successor so it spawns exactly one copy no matter how often this runs.
  /// Returns how many quests were respawned.
  Future<int> respawnDue({DateTime? now}) => (_locks[storage] ??= AsyncLock())
      .synchronized(() => _respawnDue(now: now));

  Future<int> _respawnDue({DateTime? now}) async {
    final current = now ?? DateTime.now();
    final today = DateTime(current.year, current.month, current.day);

    var respawned = 0;
    for (final q in storage.getQuests()) {
      if (!q.isRecurring || q.status != QuestStatus.completed) continue;
      final completedAt = q.completedAt;
      // 오늘 완료한 건 내일 아침에 다시 나타나야 한다.
      if (completedAt == null || !completedAt.isBefore(today)) continue;

      final successor = Quest(
        // Deterministic for this source/day: after an unexpected process
        // exit, retrying overwrites the same successor instead of duplicating it.
        id: 'recurring-${q.id}-${today.millisecondsSinceEpoch}',
        title: q.title,
        description: q.description,
        statRewards: Map.of(q.statRewards),
        difficulty: q.difficulty,
        isRecurring: true,
        status: QuestStatus.active,
        source: q.source,
        createdAt: current,
        // goalId는 승계하지 않는다 — 원본이 속했던 목표는 이미 완료됐을 수
        // 있고, 재생성본이 목표 자동완료/보너스 XP 로직을 다시 건드리면 안 된다.
      );
      final existingSuccessor = storage.getQuest(successor.id);
      if (existingSuccessor != null &&
          !_isSameSuccessor(existingSuccessor, successor)) {
        throw StateError(
          'Recurring quest successor id collides with an existing quest',
        );
      }
      final completed = q.copy()..isRecurring = false;
      try {
        if (existingSuccessor == null) {
          await storage.saveQuest(successor);
        }
        await storage.saveQuest(completed);
      } catch (error, stackTrace) {
        final rollbackErrors = <Object>[];
        try {
          await storage.saveQuest(q.copy());
        } catch (rollbackError) {
          rollbackErrors.add(rollbackError);
        }
        if (existingSuccessor == null) {
          try {
            await storage.deleteQuest(successor.id);
          } catch (rollbackError) {
            rollbackErrors.add(rollbackError);
          }
        }
        if (rollbackErrors.isNotEmpty) {
          Error.throwWithStackTrace(
            TransactionRollbackException(
              error: error,
              stackTrace: stackTrace,
              rollbackErrors: List.unmodifiable(rollbackErrors),
            ),
            stackTrace,
          );
        }
        Error.throwWithStackTrace(error, stackTrace);
      }
      respawned++;
    }
    return respawned;
  }

  bool _isSameSuccessor(Quest existing, Quest expected) =>
      existing.title == expected.title &&
      existing.description == expected.description &&
      existing.status == QuestStatus.active &&
      existing.isRecurring &&
      existing.completedAt == null &&
      existing.goalId == null &&
      existing.difficulty == expected.difficulty &&
      existing.source == expected.source &&
      _sameRewards(existing.statRewards, expected.statRewards);

  bool _sameRewards(Map<String, double> left, Map<String, double> right) {
    if (left.length != right.length) return false;
    for (final entry in left.entries) {
      if (right[entry.key] != entry.value) return false;
    }
    return true;
  }
}
