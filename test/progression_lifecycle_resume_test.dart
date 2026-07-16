import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:human_status/main.dart';
import 'package:human_status/models/quest.dart';
import 'package:human_status/providers/profile_provider.dart';
import 'package:human_status/providers/progression_provider.dart';
import 'package:human_status/providers/quest_provider.dart';
import 'package:human_status/services/daily_refresh_controller.dart';
import 'package:human_status/widgets/progression_journey_card.dart';

import 'helpers/test_app.dart';

void main() {
  testWidgets('resume가 nowProvider를 무효화해, 퀘스트 데이터가 그대로여도 자정을 넘긴 성장 여정이 반영된다', (
    tester,
  ) async {
    final storage = await createTestStorage();
    // 어제 완료한 퀘스트 하나 — 오늘 하루가 지나도 이 데이터 자체는 절대
    // 바뀌지 않는다. 화면이 갱신되려면 오직 nowProvider가 움직여야 한다.
    await storage.saveQuest(
      Quest(
        id: 'q1',
        title: '어제 완료한 퀘스트',
        description: '',
        statRewards: const {'health': 10},
        status: QuestStatus.completed,
        createdAt: DateTime(2026, 7, 15),
        completedAt: DateTime(2026, 7, 15, 20),
      ),
    );

    // main()의 startup 경로처럼 DailyRefreshController에도 같은 가변
    // clock을 물려, resume 한 번으로 "하루가 지난 뒤 재진입"을 그대로
    // 재현한다 — 실제 앱에서 nowProvider와 DailyRefreshController는 같은
    // 벽시계를 보고 있으므로.
    var day = DateTime(2026, 7, 16, 9); // 완료 다음날, 아직 오늘 완료 없음

    final container = ProviderContainer(
      overrides: [
        storageServiceProvider.overrideWithValue(storage),
        nowProvider.overrideWith((ref) => day),
      ],
    );
    addTearDown(container.dispose);

    final controller = DailyRefreshController(
      storage: storage,
      clock: () => day,
      refreshRecommendations: () async {},
      refreshFinancialAdvice: () async {},
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: HumanStatusApp(refreshController: controller),
      ),
    );
    await tester.pump();

    // Day 1(7/16): 어제 완료했지만 오늘은 아직 안 했으니 "이어져요" 문구.
    expect(find.text('퀘스트 하나만 완료하면 연속 기록이 오늘도 이어져요.'), findsOneWidget);
    expect(find.text('🔥 1일'), findsOneWidget);

    // 퀘스트 데이터는 손대지 않고 벽시계만 하루 더 전진시킨 뒤 resume.
    day = DateTime(2026, 7, 17, 9);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    // Day 2(7/17): 어제(7/16)도 오늘(7/17)도 완료가 없으니 연속 기록이
    // 끊긴 "다시 시작" 문구로 바뀌어야 한다 — 데이터가 그대로인데도
    // nowProvider가 갱신됐다는 뜻이다.
    expect(find.text('오늘부터 다시 시작해볼까요? 첫 걸음이 연속 기록의 시작이에요.'), findsOneWidget);
    expect(find.text('🔥 0일'), findsOneWidget);
  });

  testWidgets('앱이 resume 없이 자정을 넘겨 켜져 있는 상태에서 퀘스트를 완료해도, '
      '완료 시각과 성장 여정 카드가 새 날짜(day2) 기준으로 즉시 맞춰진다', (tester) async {
    final storage = await createTestStorage();
    await storage.saveQuest(
      Quest(
        id: 'q1',
        title: '진행중 퀘스트',
        description: '',
        statRewards: const {'health': 10},
        createdAt: DateTime(2026, 7, 15),
      ),
    );

    // day1에서 시작해, resume 이벤트 없이 day2로 넘어간다 — 실제 앱이
    // 백그라운드로 가지 않고 화면을 켜 둔 채 자정을 넘기는 상황과 같다.
    var day = DateTime(2026, 7, 16, 23, 59);
    var clockReadCount = 0;
    final container = ProviderContainer(
      overrides: [
        storageServiceProvider.overrideWithValue(storage),
        nowProvider.overrideWith((ref) {
          clockReadCount++;
          return day;
        }),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: ProgressionJourneyCard()),
          ),
        ),
      ),
    );
    await tester.pump();

    // day1: 아직 완료가 없으니 "다시 시작" 문구.
    expect(find.text('오늘부터 다시 시작해볼까요? 첫 걸음이 연속 기록의 시작이에요.'), findsOneWidget);

    // 위젯이 계속 마운트된 채로, resume 없이 자정을 넘겨 day2로 이동한다.
    day = DateTime(2026, 7, 17, 0, 5);
    final readsBeforeCompletion = clockReadCount;

    await container.read(questsProvider.notifier).completeQuest('q1');
    await tester.pump();

    // 완료 시각이 day2로 딱 잡혀야 한다 — 완료 시점의 실제 벽시계가
    // 캐시된 day1 인스턴스가 아니라 새로 무효화된 day2 값이어야 한다.
    final completed = storage.getQuests().single;
    expect(completed.completedAt, day);
    expect(completed.completedAt, isNot(DateTime(2026, 7, 16, 23, 59)));

    // 성장 여정 카드도 별도의 resume 없이 day2 기준(오늘 완료)으로
    // 즉시 갱신된다.
    expect(find.text('오늘의 몫을 지켰어요. 내일도 이어가볼까요?'), findsOneWidget);
    expect(find.text('🔥 1일'), findsOneWidget);

    // 완료 트랜잭션 하나가 시계를 정확히 한 번만 다시 읽는다(무효화 후
    // 첫 read가 재계산을 트리거하고, 같은 프레임의 나머지 watch/read는
    // 캐시된 값을 재사용한다).
    expect(clockReadCount - readsBeforeCompletion, 1);
  });
}
