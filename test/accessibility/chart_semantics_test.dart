// Phase 6 Part B — 시각 전용 차트(fl_chart BarChart)에 보조기술 대체
// semantics 요약이 제공되는지, 그리고 축 라벨 등 차트 내부 요소가 중복
// 낭독되지 않도록 제외됐는지 확인한다.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:human_status/models/transaction.dart';
import 'package:human_status/screens/finance_screen.dart';

import '../helpers/test_app.dart';
import 'a11y_harness.dart';

Future<void> _spend(
  dynamic storage,
  String id,
  double amount, {
  required DateTime date,
  String category = '식비',
}) {
  return storage.saveTransaction(
    Transaction(
      id: id,
      type: TransactionType.expense,
      category: category,
      memo: '',
      amount: amount,
      date: date,
      createdAt: date,
    ),
  );
}

void main() {
  testWidgets('월별 지출 차트는 시각 요소 없이도 기간·최고 지출 달을 알 수 있는 semantics 요약을 제공한다', (
    tester,
  ) async {
    final storage = await createTestStorage();
    final now = DateTime.now();
    await _spend(storage, 't1', 100000, date: now);
    await _spend(
      storage,
      't2',
      800000,
      date: DateTime(now.year, now.month - 1),
    );
    final handle = tester.ensureSemantics();

    await pumpApp(tester, storage, const Scaffold(body: FinanceListView()));
    await tester.pumpAndSettle();

    // 최고 지출 달(800,000원)이 요약 문장에 포함돼 있어야 한다.
    expect(findBySemanticsLabelContaining('가장 많이 쓴 달'), findsOneWidget);
    expect(findBySemanticsLabelContaining('800,000원'), findsOneWidget);

    // 차트 내부(막대/축 라벨)는 ExcludeSemantics로 제외돼, 하단 축에
    // "7월"처럼 연도 없이 월만 단독으로 그려지는 라벨이 별도 semantics
    // 노드로 노출되지 않는다("2026년 7월"처럼 연도가 붙는 거래 내역의
    // 월 구분 헤더와는 패턴으로 구분된다).
    expect(find.bySemanticsLabel(RegExp(r'^\d+월$')), findsNothing);

    handle.dispose();
  });
}
