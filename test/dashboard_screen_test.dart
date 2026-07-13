import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:human_status/models/quest.dart';
import 'package:human_status/screens/dashboard_screen.dart';
import 'package:human_status/screens/goal_form_screen.dart';

import 'helpers/test_app.dart';

void main() {
  testWidgets('첫 실행에는 CTA 카드가 뜨고 버튼이 목표 작성 화면으로 이동한다', (tester) async {
    final storage = await createTestStorage();
    await pumpApp(tester, storage, const DashboardScreen());

    expect(find.text('시작해볼까요?'), findsOneWidget);
    expect(find.text('종합 레벨'), findsOneWidget);

    await tester.tap(find.text('첫 목표 만들기'));
    await tester.pumpAndSettle();
    expect(find.byType(GoalFormScreen), findsOneWidget);
  });

  testWidgets('진행중 퀘스트가 있으면 CTA 대신 퀘스트 카드가 보이고 홈에서 바로 완료된다', (tester) async {
    // 스텟 카드 아래의 퀘스트 목록까지 스크롤 없이 화면에 들어오도록 세로를 늘린다.
    setScreenSize(tester, const Size(600, 1600));
    final storage = await createTestStorage();
    await storage.saveQuest(Quest(
      id: 'q1',
      title: '스트레칭',
      description: '',
      statRewards: {'health': 10},
      createdAt: DateTime(2026, 7, 1),
    ));

    await pumpApp(tester, storage, const DashboardScreen());

    expect(find.text('시작해볼까요?'), findsNothing);
    expect(find.text('스트레칭'), findsOneWidget);
    expect(find.text('1개'), findsOneWidget);

    await tester.tap(find.text('완료'));
    await tester.pumpAndSettle();

    expect(find.text('"스트레칭" 완료!'), findsOneWidget);
    expect(find.text('🏆 업적 달성!'), findsOneWidget);
    await tester.tap(find.text('확인'));
    await tester.pumpAndSettle();

    expect(find.text('0개'), findsOneWidget);
    expect(storage.getStat('health')!.currentXp, 10);
  });
}
