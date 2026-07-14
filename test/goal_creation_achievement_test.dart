import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:human_status/models/goal.dart';
import 'package:human_status/providers/goal_provider.dart';
import 'package:human_status/providers/profile_provider.dart';

import 'helpers/test_app.dart';

void main() {
  test('첫 목표를 만들면 목표 설정 업적이 그 자리에서 해금된다', () async {
    final storage = await createTestStorage();
    final container = ProviderContainer(overrides: [
      storageServiceProvider.overrideWithValue(storage),
    ]);
    addTearDown(container.dispose);

    final result = await container.read(goalsProvider.notifier).createGoal(Goal(
          id: 'g1',
          title: '책 12권 읽기',
          description: '',
          statId: 'intelligence',
          createdAt: DateTime(2026, 7, 14),
        ));

    expect(result.newAchievements.map((a) => a.id), contains('first_goal_set'));
    expect(storage.getUnlockedAchievements().keys, contains('first_goal_set'));
    // 로컬 규칙 분해로 퀘스트도 함께 생성된다.
    expect(result.quests, isNotEmpty);
  });

  test('두 번째 목표부터는 같은 업적이 다시 나오지 않는다', () async {
    final storage = await createTestStorage();
    final container = ProviderContainer(overrides: [
      storageServiceProvider.overrideWithValue(storage),
    ]);
    addTearDown(container.dispose);
    final notifier = container.read(goalsProvider.notifier);

    Goal goal(String id) => Goal(
          id: id,
          title: '목표 $id',
          description: '',
          statId: 'health',
          createdAt: DateTime(2026, 7, 14),
        );

    await notifier.createGoal(goal('g1'));
    final second = await notifier.createGoal(goal('g2'));

    expect(second.newAchievements.where((a) => a.id == 'first_goal_set'), isEmpty);
  });
}
