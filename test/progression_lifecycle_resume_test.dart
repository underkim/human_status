import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:human_status/main.dart';
import 'package:human_status/models/quest.dart';
import 'package:human_status/providers/profile_provider.dart';
import 'package:human_status/providers/progression_provider.dart';
import 'package:human_status/services/daily_refresh_controller.dart';

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
}
