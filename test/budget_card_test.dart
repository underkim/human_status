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
