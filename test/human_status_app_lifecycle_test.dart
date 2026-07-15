import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:human_status/main.dart';
import 'package:human_status/models/quest.dart';
import 'package:human_status/providers/financial_advisor_provider.dart';
import 'package:human_status/providers/profile_provider.dart';
import 'package:human_status/providers/quest_provider.dart';
import 'package:human_status/services/daily_refresh_controller.dart';

import 'helpers/test_app.dart';

void main() {
  testWidgets('resume 라이프사이클 이벤트가 DailyRefreshController.refreshIfDue를 호출한다', (
    tester,
  ) async {
    final storage = await createTestStorage();
    var refreshCalls = 0;

    final controller = DailyRefreshController(
      storage: storage,
      respawnRecurringQuests: (now) async => refreshCalls++,
      refreshRecommendations: () async {},
      refreshFinancialAdvice: () async {},
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [storageServiceProvider.overrideWithValue(storage)],
        child: HumanStatusApp(refreshController: controller),
      ),
    );
    await tester.pump();

    // 최초 pump 자체는 controller.refreshIfDue()를 자동으로 호출하지 않는다 —
    // main()에서 별도로 한 번 트리거하는 startup 경로와 분리되어 있다.
    expect(refreshCalls, 0);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    expect(refreshCalls, 1);

    // 같은 날 다시 resume해도 중복 호출되지 않는다.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    expect(refreshCalls, 1);
  });

  testWidgets(
    '날짜가 바뀐 뒤 resume하면 어제 완료한 반복 퀘스트가 questsProvider와 화면에 active로 나타난다',
    (tester) async {
      setScreenSize(tester, const Size(400, 800));
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
      final container = ProviderContainer(
        overrides: [storageServiceProvider.overrideWithValue(storage)],
      );
      addTearDown(container.dispose);

      final controller = DailyRefreshController(
        storage: storage,
        clock: () => day,
        refreshRecommendations: () async {},
        refreshFinancialAdvice: () async {},
        onQuestsChanged: () => container.read(questsProvider.notifier).reload(),
        onAdviceChanged: () =>
            container.read(financialAdviceProvider.notifier).reload(),
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: HumanStatusApp(refreshController: controller),
        ),
      );
      await tester.pump();

      // 아직 같은 날이므로 홈 화면 진입 시점엔 반복 퀘스트가 재생성되지 않는다.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(
        container
            .read(questsProvider)
            .where((q) => q.status == QuestStatus.active)
            .length,
        0,
      );

      // 자정을 넘긴 뒤 resume: provider가 새 active 퀘스트를 갖는다.
      day = DateTime(2026, 7, 16, 9);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();

      final activeQuests = container
          .read(questsProvider)
          .where((q) => q.status == QuestStatus.active && q.isRecurring)
          .toList();
      expect(activeQuests, hasLength(1));
      expect(activeQuests.single.title, '아침 스트레칭');

      // 퀘스트 탭으로 이동해 화면에도 반영됐는지 확인한다.
      final navIcon = find.descendant(
        of: find.byType(NavigationBar),
        matching: find.byIcon(Icons.checklist_outlined),
      );
      await tester.tap(navIcon);
      await tester.pumpAndSettle();

      expect(find.text('진행중 (1)'), findsOneWidget);
      expect(find.text('아침 스트레칭'), findsOneWidget);
    },
  );
}
