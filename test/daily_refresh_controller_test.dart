import 'package:flutter_test/flutter_test.dart';
import 'package:human_status/models/quest.dart';
import 'package:human_status/services/daily_refresh_controller.dart';

import 'helpers/test_app.dart';

void main() {
  group('DailyRefreshController', () {
    test('첫 호출은 항상 갱신을 실행하고 quest/advice 콜백을 모두 호출한다', () async {
      var respawnCalls = 0;
      var recommendationCalls = 0;
      var adviceCalls = 0;
      var questsChanged = 0;
      var adviceChanged = 0;

      final controller = DailyRefreshController(
        storage: await createTestStorage(),
        clock: () => DateTime(2026, 7, 16, 9),
        respawnRecurringQuests: (now) async => respawnCalls++,
        refreshRecommendations: () async => recommendationCalls++,
        refreshFinancialAdvice: () async => adviceCalls++,
        onQuestsChanged: () => questsChanged++,
        onAdviceChanged: () => adviceChanged++,
      );

      await controller.refreshIfDue();

      expect(respawnCalls, 1);
      expect(recommendationCalls, 1);
      expect(adviceCalls, 1);
      expect(
        questsChanged,
        2,
      ); // respawn + recommendation steps both touch quests
      expect(adviceChanged, 1);
    });

    test('같은 날짜에 반복 resume 해도 중복 갱신하지 않는다', () async {
      var runs = 0;
      var day = DateTime(2026, 7, 16, 9);

      final controller = DailyRefreshController(
        storage: await createTestStorage(),
        clock: () => day,
        respawnRecurringQuests: (now) async => runs++,
        refreshRecommendations: () async {},
        refreshFinancialAdvice: () async {},
      );

      await controller.refreshIfDue();
      day = DateTime(2026, 7, 16, 23, 59); // 같은 날짜, 늦은 시각에 다시 resume
      await controller.refreshIfDue();
      await controller.refreshIfDue();

      expect(runs, 1);
    });

    test('날짜가 바뀐 뒤 resume하면 다시 갱신하고, 전날 완료한 반복 퀘스트가 active로 재생성된다', () async {
      final storage = await createTestStorage();
      await storage.saveQuest(
        Quest(
          id: 'q1',
          title: '아침 스트레칭',
          description: '10분',
          statRewards: const {'health': 15},
          isRecurring: true,
          status: QuestStatus.completed,
          source: QuestSource.manual,
          createdAt: DateTime(2026, 7, 15),
          completedAt: DateTime(2026, 7, 15, 20),
        ),
      );

      var day = DateTime(2026, 7, 15, 23);
      var questsChanged = 0;

      final controller = DailyRefreshController(
        storage: storage,
        clock: () => day,
        refreshRecommendations: () async {},
        refreshFinancialAdvice: () async {},
        onQuestsChanged: () => questsChanged++,
      );

      await controller.refreshIfDue();
      // 아직 같은 날이므로 어제 완료 기록은 재생성 대상이 아니다.
      expect(storage.getQuests().length, 1);

      day = DateTime(2026, 7, 16, 9); // 자정을 넘겨 다음날 resume
      await controller.refreshIfDue();

      final quests = storage.getQuests();
      expect(quests.length, 2);
      expect(
        quests
            .where((q) => q.status == QuestStatus.active && q.isRecurring)
            .length,
        1,
      );
      expect(questsChanged, greaterThan(0));
    });

    test('동시에 들어온 resume 호출은 하나의 실행으로 병합된다', () async {
      var runs = 0;

      final controller = DailyRefreshController(
        storage: await createTestStorage(),
        clock: () => DateTime(2026, 7, 16, 9),
        respawnRecurringQuests: (now) async {
          runs++;
          await Future<void>.delayed(const Duration(milliseconds: 10));
        },
        refreshRecommendations: () async {},
        refreshFinancialAdvice: () async {},
      );

      final first = controller.refreshIfDue();
      final second = controller.refreshIfDue();

      expect(identical(first, second), isTrue);
      await first;
      await second;
      expect(runs, 1);
    });

    test('한 서비스가 실패해도 다른 단계는 계속 실행되고 예외가 밖으로 전파되지 않는다', () async {
      var recommendationCalls = 0;
      var adviceCalls = 0;

      final controller = DailyRefreshController(
        storage: await createTestStorage(),
        clock: () => DateTime(2026, 7, 16, 9),
        respawnRecurringQuests: (now) async => throw Exception('storage boom'),
        refreshRecommendations: () async => recommendationCalls++,
        refreshFinancialAdvice: () async => adviceCalls++,
      );

      await expectLater(controller.refreshIfDue(), completes);

      expect(recommendationCalls, 1);
      expect(adviceCalls, 1);
    });
  });
}
