// Phase 6 Part A: finance_screen.dart을 lib/screens/finance/ 아래로 쪼개기
// 전에, 아직 다른 테스트가 커버하지 않는 위젯(요약 카드, 월별 지출 차트 카드,
// 코칭 카드)의 동작을 고정한다. 분할 전후로 이 파일이 그대로 통과해야 하며,
// 실패하면 분할 커밋이 문구/조건/provider 호출을 바꾼 것이다.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:human_status/models/transaction.dart';
import 'package:human_status/screens/finance_screen.dart';

import 'helpers/test_app.dart';

Future<void> _spend(
  dynamic storage,
  String id,
  double amount, {
  String category = '식비',
  DateTime? date,
}) {
  final now = date ?? DateTime.now();
  return storage.saveTransaction(
    Transaction(
      id: id,
      type: TransactionType.expense,
      category: category,
      memo: '',
      amount: amount,
      date: now,
      createdAt: now,
    ),
  );
}

Future<void> _earn(dynamic storage, String id, double amount) {
  final now = DateTime.now();
  return storage.saveTransaction(
    Transaction(
      id: id,
      type: TransactionType.income,
      category: '급여',
      memo: '',
      amount: amount,
      date: now,
      createdAt: now,
    ),
  );
}

void main() {
  group('이번 달 요약 카드', () {
    testWidgets('수입/지출/순저축 값을 원화 포맷으로 보여준다', (tester) async {
      final storage = await createTestStorage();
      await _earn(storage, 'i1', 1000000);
      await _spend(storage, 'e1', 400000);
      await pumpApp(tester, storage, const Scaffold(body: FinanceListView()));

      expect(find.text('이번 달'), findsOneWidget);
      expect(find.text('수입'), findsOneWidget);
      expect(find.text('지출'), findsOneWidget);
      expect(find.text('순저축'), findsOneWidget);
      expect(find.text('1,000,000원'), findsOneWidget);
      expect(find.text('400,000원'), findsOneWidget);
      expect(find.text('600,000원'), findsOneWidget);
    });

    testWidgets('거래가 없으면 세 값 모두 0원이다', (tester) async {
      final storage = await createTestStorage();
      await pumpApp(tester, storage, const Scaffold(body: FinanceListView()));

      expect(find.text('0원'), findsNWidgets(3));
    });
  });

  group('최근 6개월 지출 차트 카드', () {
    testWidgets('이번 달 지출이 있으면 차트 카드가 보인다', (tester) async {
      final storage = await createTestStorage();
      await _spend(storage, 'e1', 100000);
      await pumpApp(tester, storage, const Scaffold(body: FinanceListView()));

      expect(find.text('최근 6개월 지출'), findsOneWidget);
    });

    testWidgets('아무 달에도 지출이 없으면 차트 카드가 보이지 않는다', (tester) async {
      final storage = await createTestStorage();
      await _earn(storage, 'i1', 100000); // 수입만 있고 지출은 없음
      await pumpApp(tester, storage, const Scaffold(body: FinanceListView()));

      expect(find.text('최근 6개월 지출'), findsNothing);
    });
  });

  group('재무 코칭 카드', () {
    testWidgets('캐시된 코칭 문구가 없으면 안내 문구를 보여준다', (tester) async {
      final storage = await createTestStorage();
      await pumpApp(tester, storage, const Scaffold(body: FinanceListView()));

      expect(find.text('재무 코칭'), findsOneWidget);
      expect(find.text('아직 코칭 내용이 없어요. 새로고침 버튼을 눌러보세요.'), findsOneWidget);
    });

    testWidgets('캐시된 코칭 문구가 있으면 카테고리 아이콘과 메시지를 보여준다', (tester) async {
      final storage = await createTestStorage();
      final profile = storage.getProfile();
      profile.cachedAdvice = [
        {'category': 'spending', 'message': '이번 달 카페 지출이 지난달보다 늘었어요.'},
        {'category': 'goal', 'message': '저축 목표까지 얼마 남지 않았어요.'},
      ];
      await storage.saveProfile(profile);
      await pumpApp(tester, storage, const Scaffold(body: FinanceListView()));

      expect(find.text('이번 달 카페 지출이 지난달보다 늘었어요.'), findsOneWidget);
      expect(find.text('저축 목표까지 얼마 남지 않았어요.'), findsOneWidget);
      expect(find.text('아직 코칭 내용이 없어요. 새로고침 버튼을 눌러보세요.'), findsNothing);
      expect(find.byTooltip('새로고침'), findsOneWidget);
    });

    testWidgets('새로고침 버튼을 누르면 예외 없이 처리되고 다시 활성화된다', (tester) async {
      final storage = await createTestStorage();
      await pumpApp(tester, storage, const Scaffold(body: FinanceListView()));

      await tester.tap(find.byTooltip('새로고침'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      final refreshButton = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.refresh),
      );
      expect(refreshButton.onPressed, isNotNull);
    });
  });
}
