import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:human_status/models/goal.dart';
import 'package:human_status/models/quest.dart';
import 'package:human_status/providers/goal_provider.dart';
import 'package:human_status/providers/profile_provider.dart';

import 'helpers/test_app.dart';

Quest _quest(String id, String goalId, QuestStatus status) => Quest(
      id: id,
      title: id,
      description: '',
      statRewards: {'health': 20},
      status: status,
      createdAt: DateTime(2026, 7, 1),
      completedAt: status == QuestStatus.completed ? DateTime(2026, 7, 2) : null,
      goalId: goalId,
    );

void main() {
  test('목표를 삭제하면 진행중/추천 연결 퀘스트는 언링크되고 완료 퀘스트는 링크를 유지한다', () async {
    final storage = await createTestStorage();
    await storage.saveGoal(Goal(
      id: 'g1',
      title: '목표',
      description: '',
      statId: 'health',
      createdAt: DateTime(2026, 7, 1),
    ));
    await storage.saveQuest(_quest('active', 'g1', QuestStatus.active));
    await storage.saveQuest(_quest('suggested', 'g1', QuestStatus.suggested));
    await storage.saveQuest(_quest('done', 'g1', QuestStatus.completed));
    await storage.saveQuest(_quest('other', 'g2', QuestStatus.active)); // 다른 목표

    final container = ProviderContainer(overrides: [
      storageServiceProvider.overrideWithValue(storage),
    ]);
    addTearDown(container.dispose);

    await container.read(goalsProvider.notifier).deleteGoal('g1');

    expect(storage.getGoal('g1'), isNull);
    // 진행중/추천은 goalId가 지워져 일반 퀘스트로 남는다.
    expect(storage.getQuests().firstWhere((q) => q.id == 'active').goalId, isNull);
    expect(storage.getQuests().firstWhere((q) => q.id == 'suggested').goalId, isNull);
    // 완료 퀘스트는 이력·보너스 XP 근거로 링크를 유지한다.
    expect(storage.getQuests().firstWhere((q) => q.id == 'done').goalId, 'g1');
    // 다른 목표의 퀘스트는 건드리지 않는다.
    expect(storage.getQuests().firstWhere((q) => q.id == 'other').goalId, 'g2');
    // 모든 퀘스트는 그대로 남는다(삭제되지 않음).
    expect(storage.getQuests().length, 4);
  });
}
