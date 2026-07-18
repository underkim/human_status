import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:human_status/models/goal.dart';
import 'package:human_status/models/quest.dart';
import 'package:human_status/screens/dashboard_screen.dart';
import 'package:human_status/screens/goal_form_screen.dart';
import 'package:human_status/screens/onboarding_screen.dart';
import 'package:human_status/screens/quest_form_screen.dart';
import 'package:human_status/screens/quests_screen.dart';
import 'package:human_status/widgets/action_hub_card.dart';

import 'helpers/test_app.dart';

/// 홈 화면을 스크롤 없이 볼 수 있는 컴팩트 폰 크기.
const _compactPhone = Size(400, 800);

void main() {
  testWidgets('첫 실행에는 AI 설계 CTA와 직접 목표 작성 경로가 함께 보인다', (tester) async {
    final storage = await createTestStorage();
    await pumpApp(tester, storage, const DashboardScreen());

    expect(find.text('오늘, 무엇을 바꿔볼까요?'), findsOneWidget);
    expect(find.text('종합 레벨'), findsOneWidget);
    expect(find.text('오늘의 행동'), findsNothing);

    await tester.tap(find.text('AI로 첫 퀘스트 설계하기'));
    await tester.pumpAndSettle();
    expect(find.byType(OnboardingScreen), findsOneWidget);
    expect(find.text('AI 퀘스트 설계'), findsOneWidget);
  });

  testWidgets('진행중 퀘스트가 있으면 오늘의 행동 허브에 강조 퀘스트와 완료 버튼이 스크롤 없이 보인다', (
    tester,
  ) async {
    setScreenSize(tester, _compactPhone);
    final storage = await createTestStorage();
    await storage.saveQuest(
      Quest(
        id: 'q1',
        title: '스트레칭',
        description: '',
        statRewards: {'health': 10},
        createdAt: DateTime(2026, 7, 1),
      ),
    );

    await pumpApp(tester, storage, const DashboardScreen());

    expect(find.text('시작해볼까요?'), findsNothing);
    expect(find.text('오늘의 행동'), findsOneWidget);
    expect(find.text('다음 퀘스트'), findsOneWidget);
    expect(find.text('스트레칭'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '완료'), findsOneWidget);
    expect(find.text('오늘 완료 0개 · +0 XP'), findsOneWidget);

    // 스크롤/ensureVisible 없이 강조 퀘스트의 완료 버튼 실제 사각형이 초기
    // 뷰포트(앱바 아래 화면) 안에 온전히 들어와야 한다 — 위젯이 트리에
    // 있다는 것만으로는 실제로 스크롤 없이 보인다는 걸 보장하지 않는다.
    final completeButtonRect = tester.getRect(
      find.widgetWithText(FilledButton, '완료'),
    );
    expect(completeButtonRect.top, greaterThanOrEqualTo(0));
    expect(completeButtonRect.bottom, lessThanOrEqualTo(_compactPhone.height));

    await tester.tap(find.text('완료'));
    await tester.pumpAndSettle();

    expect(find.text('"스트레칭" 완료!'), findsOneWidget);
    expect(find.text('🏆 업적 달성!'), findsOneWidget);
    await tester.tap(find.text('확인'));
    await tester.pumpAndSettle();

    // 완료 후 진행중 퀘스트가 남지 않았으니 허브는 "퀘스트 추가" 대체 CTA로 바뀐다.
    expect(find.text('다음 퀘스트'), findsNothing);
    expect(find.text('오늘 완료 1개 · +10 XP'), findsOneWidget);
    expect(storage.getStat('health')!.currentXp, 10);
  });

  testWidgets('여러 진행중 퀘스트 중 우선순위 규칙으로 정확히 하나만 강조되고 아래 목록에 중복되지 않는다', (
    tester,
  ) async {
    setScreenSize(tester, const Size(600, 1600));
    final storage = await createTestStorage();
    // 목표 연결 퀘스트가 최우선이어야 한다 — 나머지가 더 쉬워도 밀린다.
    await storage.saveQuest(
      Quest(
        id: 'plain',
        title: '물 마시기',
        description: '',
        statRewards: {'health': 5},
        difficulty: QuestDifficulty.easy,
        createdAt: DateTime(2026, 7, 1),
      ),
    );
    await storage.saveQuest(
      Quest(
        id: 'goal-linked',
        title: '운동 30분',
        description: '',
        statRewards: {'health': 20},
        difficulty: QuestDifficulty.hard,
        createdAt: DateTime(2026, 7, 2),
        goalId: 'some-goal',
      ),
    );

    await pumpApp(tester, storage, const DashboardScreen());

    // 강조 카드에 정확히 한 번, 아래 "진행중인 퀘스트" 목록에는 나타나지 않는다.
    expect(find.text('운동 30분'), findsOneWidget);
    expect(find.text('물 마시기'), findsOneWidget);
    expect(find.text('다음 퀘스트'), findsOneWidget);

    // 허브 안의 완료 버튼만 골라 누른다 — 아래 목록의 남은 퀘스트도 각자
    // 완료 버튼을 갖고 있으므로 텍스트만으로는 구분되지 않는다.
    final hubCompleteButton = find.descendant(
      of: find.byType(ActionHubCard),
      matching: find.widgetWithText(FilledButton, '완료'),
    );
    await tester.tap(hubCompleteButton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('"운동 30분" 완료!'), findsOneWidget);
    // 첫 완료라면 업적 다이얼로그가 뜰 수 있으니, 있으면 닫아준다.
    final confirmButton = find.text('확인');
    if (confirmButton.evaluate().isNotEmpty) {
      await tester.tap(confirmButton);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }

    // 목표 연결 퀘스트가 완료됐으니 남은 하나(물 마시기)가 다음 강조 퀘스트가
    // 되고, 아래 목록에서는 사라진다.
    expect(find.text('다음 퀘스트'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(ActionHubCard),
        matching: find.text('물 마시기'),
      ),
      findsOneWidget,
    );
    expect(find.text('운동 30분'), findsNothing);

    // 오늘 요약도 갱신된다: health 20 XP 기본값에 목표 연결 1.5배 보너스.
    expect(find.text('오늘 완료 1개 · +30 XP'), findsOneWidget);
  });

  testWidgets('진행중 퀘스트가 없고 추천 퀘스트가 있으면 허브가 채택 CTA를 보여주고 채택하면 강조 퀘스트로 전환된다', (
    tester,
  ) async {
    setScreenSize(tester, const Size(600, 1600));
    final storage = await createTestStorage();
    await storage.saveQuest(
      Quest(
        id: 's1',
        title: '독서 10분',
        description: '',
        statRewards: {'intelligence': 10},
        status: QuestStatus.suggested,
        createdAt: DateTime(2026, 7, 1),
      ),
    );

    await pumpApp(tester, storage, const DashboardScreen());

    expect(find.text('추천 퀘스트'), findsOneWidget);
    expect(find.text('독서 10분'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '채택하고 시작'), findsOneWidget);

    await tester.tap(find.text('채택하고 시작'));
    await tester.pumpAndSettle();

    expect(find.text('다음 퀘스트'), findsOneWidget);
    expect(find.text('추천 퀘스트'), findsNothing);
    expect(find.widgetWithText(FilledButton, '완료'), findsOneWidget);
  });

  testWidgets('진행중·추천 퀘스트가 모두 없지만 목표가 있으면 퀘스트 추가 CTA를 보여준다', (tester) async {
    setScreenSize(tester, const Size(600, 1600));
    final storage = await createTestStorage();
    await storage.saveGoal(
      Goal(
        id: 'g1',
        title: '건강해지기',
        description: '',
        statId: 'health',
        createdAt: DateTime(2026, 7, 1),
      ),
    );

    await pumpApp(tester, storage, const DashboardScreen());

    expect(find.text('시작해볼까요?'), findsNothing);
    expect(find.text('오늘의 행동'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '퀘스트 추가'), findsOneWidget);

    await tester.tap(find.text('퀘스트 추가'));
    await tester.pumpAndSettle();
    expect(find.byType(QuestFormScreen), findsOneWidget);
  });

  testWidgets('독립 실행에서 전체 퀘스트 보기를 누르면 안전한 대체 라우트로 퀘스트 화면을 새로 연다', (
    tester,
  ) async {
    setScreenSize(tester, const Size(600, 1600));
    final storage = await createTestStorage();
    await storage.saveQuest(
      Quest(
        id: 'q1',
        title: '스트레칭',
        description: '',
        statRewards: {'health': 10},
        createdAt: DateTime(2026, 7, 1),
      ),
    );

    await pumpApp(tester, storage, const DashboardScreen());

    await tester.tap(find.text('전체 퀘스트 보기'));
    await tester.pumpAndSettle();

    expect(find.byType(QuestsScreen), findsOneWidget);
  });
}
