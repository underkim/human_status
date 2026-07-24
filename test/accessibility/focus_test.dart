// Phase 6 Part B — 검색 진입 시 초기 포커스와, 다이얼로그의 키보드
// Tab/Enter 조작성을 확인한다. focus 트리 내부 구조는 위젯 테스트로 직접
// 들여다보기 어려우므로, "포커스가 어딘가로 이동했다"와 "Enter로 다이얼로그
// 안의 동작을 실행할 수 있다"는 관찰 가능한 결과로 검증한다.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:human_status/models/quest.dart';
import 'package:human_status/models/transaction.dart';
import 'package:human_status/screens/finance_screen.dart';
import 'package:human_status/screens/quests_screen.dart';

import '../helpers/test_app.dart';

void main() {
  testWidgets('퀘스트 검색을 열면 검색 입력창이 곧바로 포커스를 받는다', (tester) async {
    final storage = await createTestStorage();
    await storage.saveQuest(
      Quest(
        id: 'q1',
        title: '물 마시기',
        description: '',
        statRewards: const {'health': 10},
        status: QuestStatus.active,
        source: QuestSource.manual,
        createdAt: DateTime(2026, 7, 1),
      ),
    );
    await pumpApp(tester, storage, const QuestsScreen());

    await tester.tap(find.byTooltip('퀘스트 검색'));
    await tester.pumpAndSettle();

    // 텍스트 입력 연결이 열려 있다는 것은 해당 TextField가 실제로 포커스를
    // 받아 소프트 키보드를 요청할 수 있는 상태라는 뜻이다 — 위젯 설정값
    // (autofocus: true)이 아니라 런타임 결과를 확인한다.
    expect(tester.testTextInput.hasAnyClients, isTrue);
  });

  testWidgets('삭제 확인 다이얼로그는 Tab/Enter만으로 조작할 수 있다', (tester) async {
    final storage = await createTestStorage();
    final now = DateTime.now();
    await storage.saveTransaction(
      Transaction(
        id: 't1',
        type: TransactionType.expense,
        category: '식비',
        memo: '',
        amount: 5000,
        date: now,
        createdAt: now,
      ),
    );
    setScreenSize(tester, const Size(800, 2000));
    await pumpApp(tester, storage, const Scaffold(body: FinanceListView()));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    expect(find.text('거래 삭제'), findsOneWidget);

    // Tab으로 다이얼로그 안의 버튼들 사이를 이동할 수 있고(포커스가 실제로
    // 옮겨간다), Enter로 현재 포커스된 동작을 실행해 다이얼로그를 닫을 수
    // 있다 — 마우스/터치 없이도 다이얼로그를 완전히 조작할 수 있음을
    // 보장한다.
    final focusBeforeTab = FocusManager.instance.primaryFocus;
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus, isNotNull);
    expect(FocusManager.instance.primaryFocus, isNot(same(focusBeforeTab)));

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('거래 삭제'), findsNothing);
  });
}
