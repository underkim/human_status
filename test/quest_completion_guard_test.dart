import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:human_status/models/quest.dart';
import 'package:human_status/providers/profile_provider.dart';
import 'package:human_status/providers/quest_provider.dart';

import 'helpers/test_app.dart';

void main() {
  test('완료를 두 번 호출해도 XP는 한 번만 지급된다', () async {
    final storage = await createTestStorage();
    await storage.saveQuest(Quest(
      id: 'q1',
      title: '물 마시기',
      description: '',
      statRewards: {'health': 30},
      createdAt: DateTime(2026, 7, 14),
    ));

    final container = ProviderContainer(overrides: [
      storageServiceProvider.overrideWithValue(storage),
    ]);
    addTearDown(container.dispose);
    final notifier = container.read(questsProvider.notifier);

    final first = await notifier.completeQuest('q1');
    expect(first.levelUps, isNotEmpty);

    // 리빌드 전에 버튼이 연타된 상황 — 같은 id로 재호출.
    final second = await notifier.completeQuest('q1');
    expect(second.levelUps, isEmpty);
    expect(second.newAchievements, isEmpty);

    expect(storage.getStat('health')!.currentXp, 30);
    expect(storage.getQuests().where((q) => q.status == QuestStatus.completed).length, 1);
  });

  test('존재하지 않는 id로 호출하면 예외 없이 빈 결과를 돌려준다', () async {
    final storage = await createTestStorage();
    final container = ProviderContainer(overrides: [
      storageServiceProvider.overrideWithValue(storage),
    ]);
    addTearDown(container.dispose);

    final result = await container.read(questsProvider.notifier).completeQuest('ghost');
    expect(result.levelUps, isEmpty);
    expect(storage.getStat('health')!.currentXp, 0);
  });

  test('진행중이 아닌(추천) 퀘스트를 완료 호출해도 XP를 지급하지 않는다', () async {
    final storage = await createTestStorage();
    await storage.saveQuest(Quest(
      id: 's1',
      title: '추천 퀘스트',
      description: '',
      statRewards: {'health': 30},
      status: QuestStatus.suggested,
      createdAt: DateTime(2026, 7, 14),
    ));

    final container = ProviderContainer(overrides: [
      storageServiceProvider.overrideWithValue(storage),
    ]);
    addTearDown(container.dispose);

    final result = await container.read(questsProvider.notifier).completeQuest('s1');
    expect(result.levelUps, isEmpty);
    expect(storage.getStat('health')!.currentXp, 0);
    // 추천 상태 그대로 — 완료로 바뀌지 않는다.
    expect(storage.getQuests().single.status, QuestStatus.suggested);
  });

  test('목표 연결 퀘스트는 1.5배 보너스 XP를 지급한다', () async {
    final storage = await createTestStorage();
    await storage.saveQuest(Quest(
      id: 'q1',
      title: '목표 퀘스트',
      description: '',
      statRewards: {'health': 20},
      goalId: 'g-none', // 목표 실체 없이도 보너스 규칙은 goalId 기준.
      createdAt: DateTime(2026, 7, 14),
    ));

    final container = ProviderContainer(overrides: [
      storageServiceProvider.overrideWithValue(storage),
    ]);
    addTearDown(container.dispose);

    await container.read(questsProvider.notifier).completeQuest('q1');
    expect(storage.getStat('health')!.currentXp, 30); // 20 * 1.5
  });
}
