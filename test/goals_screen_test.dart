import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:human_status/models/goal.dart';
import 'package:human_status/screens/goals_screen.dart';

import 'helpers/test_app.dart';

Goal _goal(
  String id,
  String title, {
  GoalStatus status = GoalStatus.active,
  double? targetAmount,
  double currentAmount = 0,
}) =>
    Goal(
      id: id,
      title: title,
      description: '',
      statId: 'health',
      status: status,
      targetAmount: targetAmount,
      currentAmount: currentAmount,
      createdAt: DateTime(2026, 7, 1),
      completedAt: status == GoalStatus.completed ? DateTime(2026, 7, 2) : null,
    );

void main() {
  testWidgets('목표가 없으면 빈 상태 안내가 나온다', (tester) async {
    final storage = await createTestStorage();
    await pumpApp(tester, storage, const GoalsScreen());

    expect(find.textContaining('아직 설정한 목표가 없어요'), findsOneWidget);
  });

  testWidgets('진행중·달성 목표가 각 섹션으로 나뉘어 표시된다', (tester) async {
    setScreenSize(tester, const Size(600, 1600));
    final storage = await createTestStorage();
    await storage.saveGoal(_goal('g1', '진행중 목표'));
    await storage.saveGoal(_goal('g2', '끝낸 목표', status: GoalStatus.completed));

    await pumpApp(tester, storage, const GoalsScreen());

    expect(find.text('진행중인 목표'), findsOneWidget);
    expect(find.text('달성한 목표'), findsOneWidget);
    expect(find.text('진행중 목표'), findsOneWidget);
    expect(find.text('끝낸 목표'), findsOneWidget);
  });

  testWidgets('비재무 목표는 직접 완료 버튼으로 달성 처리되고 보너스 XP를 준다', (tester) async {
    setScreenSize(tester, const Size(600, 1600));
    final storage = await createTestStorage();
    await storage.saveGoal(_goal('g1', '직접 완료 목표'));

    await pumpApp(tester, storage, const GoalsScreen());

    await tester.tap(find.text('목표 달성'));
    await tester.pumpAndSettle();

    expect(find.text('"직접 완료 목표" 목표를 달성했어요!'), findsOneWidget);
    // 보너스 XP 100으로 레벨업이 일어나 레벨업·업적 다이얼로그가 연달아 뜬다 —
    // 확인 버튼이 남아있는 동안 모두 닫는다.
    while (find.text('확인').evaluate().isNotEmpty) {
      await tester.tap(find.text('확인').first);
      await tester.pumpAndSettle();
    }

    expect(storage.getGoal('g1')!.status, GoalStatus.completed);
    // 목표 완료 보너스 XP 100은 정확히 Lv.1→Lv.2 임계치라 레벨업하고 잔여 XP는 0.
    final health = storage.getStat('health')!;
    expect(health.level, 2);
    expect(health.currentXp, 0);
  });

  testWidgets('목표 메뉴에서 삭제하면 확인 후 목록에서 사라진다', (tester) async {
    setScreenSize(tester, const Size(600, 1600));
    final storage = await createTestStorage();
    await storage.saveGoal(_goal('g1', '지울 목표'));

    await pumpApp(tester, storage, const GoalsScreen());

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('삭제'));
    await tester.pumpAndSettle();

    expect(find.textContaining('삭제할까요'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '삭제'));
    await tester.pumpAndSettle();

    expect(storage.getGoals(), isEmpty);
  });

  testWidgets('목표 메뉴의 수정은 편집 화면으로 이동한다', (tester) async {
    setScreenSize(tester, const Size(600, 1600));
    final storage = await createTestStorage();
    await storage.saveGoal(_goal('g1', '수정할 목표'));

    await pumpApp(tester, storage, const GoalsScreen());

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('수정'));
    await tester.pumpAndSettle();

    expect(find.text('목표 수정'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, '수정할 목표'), findsOneWidget);
  });

  testWidgets('재무 목표는 직접 완료 버튼 없이 금액 진행률만 보여준다', (tester) async {
    setScreenSize(tester, const Size(600, 1600));
    final storage = await createTestStorage();
    await storage.saveGoal(_goal('g1', '비상금', targetAmount: 1000000, currentAmount: 400000));

    await pumpApp(tester, storage, const GoalsScreen());

    expect(find.text('400,000원 / 1,000,000원'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '목표 달성'), findsNothing);
  });
}
