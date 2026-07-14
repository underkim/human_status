import 'package:uuid/uuid.dart';

import '../models/quest.dart';
import 'storage_service.dart';

/// Makes the '매일 반복' flag actually recur: a recurring quest completed on a
/// previous day respawns as a fresh active quest, once per day.
class RecurringQuestService {
  final StorageService storage;

  RecurringQuestService({required this.storage});

  /// Respawns recurring quests whose completion is before today (local
  /// midnight). The completed instance keeps its record — stats, streaks and
  /// reports all read completedAt — but hands the recurring flag to the
  /// successor so it spawns exactly one copy no matter how often this runs.
  /// Returns how many quests were respawned.
  Future<int> respawnDue({DateTime? now}) async {
    final current = now ?? DateTime.now();
    final today = DateTime(current.year, current.month, current.day);

    var respawned = 0;
    for (final q in storage.getQuests()) {
      if (!q.isRecurring || q.status != QuestStatus.completed) continue;
      final completedAt = q.completedAt;
      // 오늘 완료한 건 내일 아침에 다시 나타나야 한다.
      if (completedAt == null || !completedAt.isBefore(today)) continue;

      q.isRecurring = false;
      await storage.saveQuest(q);
      await storage.saveQuest(Quest(
        id: const Uuid().v4(),
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
      ));
      respawned++;
    }
    return respawned;
  }
}
