import 'package:flutter_test/flutter_test.dart';
import 'package:human_status/models/quest.dart';
import 'package:human_status/services/recurring_quest_service.dart';

import 'helpers/test_app.dart';

final _now = DateTime(2026, 7, 14, 9); // 오늘 오전 9시
final _yesterday = DateTime(2026, 7, 13, 22);

Quest _recurringCompleted(String id, DateTime completedAt, {String? goalId}) => Quest(
      id: id,
      title: '아침 스트레칭',
      description: '10분',
      statRewards: {'health': 15},
      difficulty: QuestDifficulty.medium,
      isRecurring: true,
      status: QuestStatus.completed,
      source: QuestSource.manual,
      createdAt: DateTime(2026, 7, 10),
      completedAt: completedAt,
      goalId: goalId,
    );

void main() {
  test('어제 완료한 반복 퀘스트는 오늘 활성 퀘스트로 재생성된다', () async {
    final storage = await createTestStorage();
    await storage.saveQuest(_recurringCompleted('q1', _yesterday));

    final count = await RecurringQuestService(storage: storage).respawnDue(now: _now);

    expect(count, 1);
    final quests = storage.getQuests();
    expect(quests.length, 2);

    // 완료 기록은 그대로 남고 반복 플래그만 후속 퀘스트로 넘어간다.
    final original = quests.singleWhere((q) => q.id == 'q1');
    expect(original.status, QuestStatus.completed);
    expect(original.completedAt, _yesterday);
    expect(original.isRecurring, isFalse);

    final respawned = quests.singleWhere((q) => q.id != 'q1');
    expect(respawned.status, QuestStatus.active);
    expect(respawned.isRecurring, isTrue);
    expect(respawned.title, '아침 스트레칭');
    expect(respawned.description, '10분');
    expect(respawned.statRewards, {'health': 15});
    expect(respawned.difficulty, QuestDifficulty.medium);
    expect(respawned.completedAt, isNull);
    expect(respawned.createdAt, _now);
  });

  test('오늘 완료한 반복 퀘스트는 아직 재생성되지 않는다', () async {
    final storage = await createTestStorage();
    await storage.saveQuest(_recurringCompleted('q1', DateTime(2026, 7, 14, 8)));

    final count = await RecurringQuestService(storage: storage).respawnDue(now: _now);

    expect(count, 0);
    expect(storage.getQuests().length, 1);
  });

  test('여러 번 실행해도 후속 퀘스트는 하나만 생긴다', () async {
    final storage = await createTestStorage();
    await storage.saveQuest(_recurringCompleted('q1', _yesterday));
    final service = RecurringQuestService(storage: storage);

    await service.respawnDue(now: _now);
    final second = await service.respawnDue(now: _now);

    expect(second, 0);
    expect(storage.getQuests().length, 2);
    expect(storage.getQuests().where((q) => q.status == QuestStatus.active).length, 1);
  });

  test('반복이 아니거나 미완료인 퀘스트는 건드리지 않는다', () async {
    final storage = await createTestStorage();
    await storage.saveQuest(Quest(
      id: 'plain',
      title: '일반 완료 퀘스트',
      description: '',
      statRewards: {'health': 10},
      status: QuestStatus.completed,
      createdAt: DateTime(2026, 7, 10),
      completedAt: _yesterday,
    ));
    await storage.saveQuest(Quest(
      id: 'active',
      title: '진행중 반복 퀘스트',
      description: '',
      statRewards: {'health': 10},
      isRecurring: true,
      createdAt: DateTime(2026, 7, 10),
    ));

    final count = await RecurringQuestService(storage: storage).respawnDue(now: _now);

    expect(count, 0);
    expect(storage.getQuests().length, 2);
  });

  test('재생성본은 goalId를 승계하지 않는다', () async {
    final storage = await createTestStorage();
    await storage.saveQuest(_recurringCompleted('q1', _yesterday, goalId: 'g1'));

    await RecurringQuestService(storage: storage).respawnDue(now: _now);

    final respawned = storage.getQuests().singleWhere((q) => q.status == QuestStatus.active);
    expect(respawned.goalId, isNull);
  });
}
