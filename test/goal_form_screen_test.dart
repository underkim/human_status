import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:human_status/screens/goal_form_screen.dart';

import 'helpers/test_app.dart';

void main() {
  testWidgets('첫 실행에는 약한 스텟(건강) 기준 추천 목표 칩이 뜨고 탭하면 제목이 채워진다', (tester) async {
    setScreenSize(tester, const Size(600, 1600));
    final storage = await createTestStorage();
    await pumpApp(tester, storage, const GoalFormScreen());

    // 모든 스텟이 Lv.1이라 가장 약한 스텟은 첫 번째(건강) — 건강 관련 아이디어 노출.
    expect(find.text('추천 목표 (약한 스텟 기준)'), findsOneWidget);
    expect(find.widgetWithText(ActionChip, '체중 5kg 감량하기'), findsOneWidget);

    await tester.tap(find.widgetWithText(ActionChip, '체중 5kg 감량하기'));
    await tester.pumpAndSettle();

    expect(
      find.widgetWithText(TextFormField, '체중 5kg 감량하기'),
      findsOneWidget,
    );
  });

  testWidgets('재무 목표 토글을 켜면 금액 입력과 기한 칩이 나타난다', (tester) async {
    setScreenSize(tester, const Size(600, 1600));
    final storage = await createTestStorage();
    await pumpApp(tester, storage, const GoalFormScreen());

    expect(find.widgetWithText(TextFormField, '목표 금액'), findsNothing);

    await tester.tap(find.text('재무 목표예요'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextFormField, '목표 금액'), findsOneWidget);
    expect(find.widgetWithText(ActionChip, '6개월 후'), findsOneWidget);
    expect(find.widgetWithText(ActionChip, '1년 후'), findsOneWidget);
    expect(find.widgetWithText(ActionChip, '3년 후'), findsOneWidget);
  });

  testWidgets('목표를 저장하면 퀘스트로 분해되고 목표 설정 업적 다이얼로그가 뜬다', (tester) async {
    setScreenSize(tester, const Size(600, 1600));
    final storage = await createTestStorage();
    await pumpApp(tester, storage, const GoalFormScreen());

    await tester.enterText(find.widgetWithText(TextFormField, '목표'), '아침형 인간 되기');
    await tester.tap(find.text('추가하기'));
    // 제출 스피너가 다이얼로그 뒤에서 계속 도는 동안엔 pumpAndSettle이 멈추지
    // 않으므로 수동으로 프레임을 진행시킨다.
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }

    // 첫 목표라 '목표 설정'(first_goal_set) 업적이 그 자리에서 해금된다.
    expect(find.text('🏆 업적 달성!'), findsOneWidget);
    expect(find.text('목표 설정'), findsOneWidget);
    await tester.tap(find.text('확인'));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }

    final goals = storage.getGoals();
    expect(goals.length, 1);
    expect(goals.single.title, '아침형 인간 되기');
    // 로컬 규칙 분해로 목표에 연결된 퀘스트가 생성된다.
    final linked = storage.getQuests().where((q) => q.goalId == goals.single.id);
    expect(linked, isNotEmpty);
    expect(storage.getUnlockedAchievements().keys, contains('first_goal_set'));
  });

  testWidgets('재무 목표는 금액이 없으면 검증 오류로 저장되지 않는다', (tester) async {
    setScreenSize(tester, const Size(600, 1600));
    final storage = await createTestStorage();
    await pumpApp(tester, storage, const GoalFormScreen());

    await tester.enterText(find.widgetWithText(TextFormField, '목표'), '비상금 모으기');
    await tester.tap(find.text('재무 목표예요'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('추가하기'));
    await tester.pumpAndSettle();

    expect(find.text('올바른 금액을 입력해주세요'), findsOneWidget);
    expect(storage.getGoals(), isEmpty);
  });
}
