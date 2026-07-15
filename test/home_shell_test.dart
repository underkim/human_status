import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:human_status/screens/home_shell.dart';

import 'helpers/test_app.dart';

void main() {
  testWidgets('컴팩트 폭에서는 바텀 내비게이션 5개로 각 탭을 오간다', (tester) async {
    setScreenSize(tester, const Size(400, 800));
    final storage = await createTestStorage();
    await pumpApp(tester, storage, const HomeShell());

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
    expect(find.byType(NavigationDestination), findsNWidgets(5));

    // 시작은 홈(대시보드).
    expect(find.text('Human Status'), findsOneWidget);
    expect(find.text('종합 레벨'), findsOneWidget);

    // 본문 EmptyState도 같은 아이콘을 쓰므로 내비게이션 바 안쪽만 찾는다.
    Finder navIcon(IconData icon) =>
        find.descendant(of: find.byType(NavigationBar), matching: find.byIcon(icon));

    await tester.tap(navIcon(Icons.checklist_outlined));
    await tester.pumpAndSettle();
    expect(find.text('진행중 (0)'), findsOneWidget);

    await tester.tap(navIcon(Icons.flag_outlined));
    await tester.pumpAndSettle();
    expect(find.text('아직 설정한 목표가 없어요.\n오른쪽 아래 + 버튼으로 목표를 추가해보세요.'), findsOneWidget);

    await tester.tap(navIcon(Icons.account_balance_wallet_outlined));
    await tester.pumpAndSettle();
    expect(find.text('이번 달'), findsOneWidget);

    await tester.tap(navIcon(Icons.more_horiz_outlined));
    await tester.pumpAndSettle();
    expect(find.text('통계'), findsOneWidget);
    expect(find.text('설정'), findsOneWidget);
  });

  testWidgets('600dp 이상에서는 NavigationRail로 전환되고 목적지 수는 그대로 5개다', (tester) async {
    setScreenSize(tester, const Size(700, 900));
    final storage = await createTestStorage();
    await pumpApp(tester, storage, const HomeShell());

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(
      tester.widget<NavigationRail>(find.byType(NavigationRail)).destinations.length,
      5,
    );

    await tester.tap(find.descendant(
      of: find.byType(NavigationRail),
      matching: find.byIcon(Icons.checklist_outlined),
    ));
    await tester.pumpAndSettle();
    expect(find.text('진행중 (0)'), findsOneWidget);
  });

  testWidgets('확장 폭에서는 레일이 extended로 라벨을 항상 보여준다', (tester) async {
    setScreenSize(tester, const Size(1100, 900));
    final storage = await createTestStorage();
    await pumpApp(tester, storage, const HomeShell());

    final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
    expect(rail.extended, isTrue);
    expect(rail.destinations.length, 5);
  });
}
