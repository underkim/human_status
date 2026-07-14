import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:human_status/models/transaction.dart';
import 'package:human_status/screens/finance_screen.dart';
import 'package:human_status/services/storage_service.dart';

import 'helpers/test_app.dart';

Future<void> _setBudget(StorageService storage, double amount) async {
  final plan = storage.getFinancialPlan();
  plan.monthlyBudget = amount;
  await storage.saveFinancialPlan(plan);
}

Future<void> _spend(StorageService storage, String id, double amount) {
  final now = DateTime.now();
  return storage.saveTransaction(Transaction(
    id: id,
    type: TransactionType.expense,
    category: '식비',
    memo: '',
    amount: amount,
    date: now,
    createdAt: now,
  ));
}

void main() {
  testWidgets('예산 미설정이면 설정 안내가 뜨고 다이얼로그로 예산을 저장한다', (tester) async {
    final storage = await createTestStorage();
    await pumpApp(tester, storage, const Scaffold(body: FinanceListView()));

    expect(find.text('월 지출 한도를 정하면 남은 예산과 초과 여부를 보여드려요.'), findsOneWidget);

    await tester.tap(find.text('설정'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '300000');
    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();

    expect(storage.getFinancialPlan().monthlyBudget, 300000);
    expect(find.text('0원 / 300,000원'), findsOneWidget);
    expect(find.text('남은 예산 300,000원'), findsOneWidget);
  });

  testWidgets('지출이 예산의 90%를 넘으면 경고 문구가 나온다', (tester) async {
    final storage = await createTestStorage();
    await _setBudget(storage, 300000);
    await _spend(storage, 't1', 280000);

    await pumpApp(tester, storage, const Scaffold(body: FinanceListView()));

    expect(find.text('280,000원 / 300,000원'), findsOneWidget);
    expect(find.text('93%'), findsOneWidget);
    expect(find.text('남은 예산 20,000원 — 거의 다 썼어요'), findsOneWidget);
  });

  testWidgets('예산을 넘으면 초과 금액이 표시된다', (tester) async {
    final storage = await createTestStorage();
    await _setBudget(storage, 300000);
    await _spend(storage, 't1', 340000);

    await pumpApp(tester, storage, const Scaffold(body: FinanceListView()));

    expect(find.text('예산을 40,000원 초과했어요'), findsOneWidget);
    expect(find.text('113%'), findsOneWidget);
  });

  testWidgets('카테고리 예산을 추가하면 행이 생기고 사용률이 표시된다', (tester) async {
    final storage = await createTestStorage();
    await _spend(storage, 't1', 120000);

    await pumpApp(tester, storage, const Scaffold(body: FinanceListView()));

    await tester.tap(find.text('카테고리 예산 추가'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), '식비');
    await tester.enterText(find.byType(TextField).at(1), '100000');
    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();

    expect(storage.getFinancialPlan().categoryBudgets, {'식비': 100000});
    // 12만 지출 / 10만 예산 — 초과 상태 행.
    expect(find.text('12만 / 10만'), findsOneWidget);
  });

  testWidgets('카테고리 예산 행을 탭해 삭제하면 미설정 상태로 돌아간다', (tester) async {
    final storage = await createTestStorage();
    final plan = storage.getFinancialPlan();
    plan.categoryBudgets['교통'] = 50000;
    await storage.saveFinancialPlan(plan);

    await pumpApp(tester, storage, const Scaffold(body: FinanceListView()));
    expect(find.text('교통'), findsOneWidget);

    await tester.tap(find.text('교통'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('삭제'));
    await tester.pumpAndSettle();

    expect(storage.getFinancialPlan().categoryBudgets, isEmpty);
    expect(find.text('월 지출 한도를 정하면 남은 예산과 초과 여부를 보여드려요.'), findsOneWidget);
  });

  testWidgets('예산 삭제 버튼은 카드를 미설정 상태로 되돌린다', (tester) async {
    final storage = await createTestStorage();
    await _setBudget(storage, 300000);

    await pumpApp(tester, storage, const Scaffold(body: FinanceListView()));
    await tester.tap(find.byTooltip('예산 수정'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('예산 삭제'));
    await tester.pumpAndSettle();

    expect(storage.getFinancialPlan().monthlyBudget, isNull);
    expect(find.text('월 지출 한도를 정하면 남은 예산과 초과 여부를 보여드려요.'), findsOneWidget);
  });
}
