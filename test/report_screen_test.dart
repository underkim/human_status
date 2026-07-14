import 'package:flutter_test/flutter_test.dart';
import 'package:human_status/models/quest.dart';
import 'package:human_status/models/transaction.dart';
import 'package:human_status/screens/report_screen.dart';

import 'helpers/test_app.dart';

void main() {
  testWidgets('이번 주 퀘스트·재무가 지난주와 비교되어 표시된다', (tester) async {
    final storage = await createTestStorage();
    final now = DateTime.now();
    final monday = DateTime(now.year, now.month, now.day - (now.weekday - 1));

    Future<void> addCompleted(String id, DateTime at, double xp) => storage.saveQuest(Quest(
          id: id,
          title: id,
          description: '',
          statRewards: {'health': xp},
          status: QuestStatus.completed,
          createdAt: at,
          completedAt: at,
        ));

    // 이번 주 2개(XP 50), 지난주 1개(XP 10).
    await addCompleted('w1', monday, 30);
    await addCompleted('w2', monday, 20);
    await addCompleted('prev', DateTime(monday.year, monday.month, monday.day - 3), 10);
    await storage.saveTransaction(Transaction(
      id: 't1',
      type: TransactionType.expense,
      category: '식비',
      memo: '',
      amount: 45000,
      date: monday,
      createdAt: monday,
    ));

    await pumpApp(tester, storage, const ReportScreen());

    expect(find.text('2개'), findsOneWidget); // 완료 퀘스트
    expect(find.text('50'), findsOneWidget); // 획득 XP
    expect(find.text('지난주 대비 퀘스트 +1개 · XP +40'), findsOneWidget);
    expect(find.text('💪 건강'), findsOneWidget);
    expect(find.text('+50 XP'), findsOneWidget);
    expect(find.text('지난주보다 45,000원 더 썼어요'), findsOneWidget);
    expect(find.text('최다 지출: 식비 (45,000원)'), findsOneWidget);
  });

  testWidgets('월간으로 전환하면 이번 달 집계로 바뀐다', (tester) async {
    final storage = await createTestStorage();
    final now = DateTime.now();
    final firstOfMonth = DateTime(now.year, now.month, 1);

    await storage.saveQuest(Quest(
      id: 'm1',
      title: '이번 달 퀘스트',
      description: '',
      statRewards: {'mental': 15},
      status: QuestStatus.completed,
      createdAt: firstOfMonth,
      completedAt: firstOfMonth,
    ));

    await pumpApp(tester, storage, const ReportScreen());
    await tester.tap(find.text('월간'));
    await tester.pumpAndSettle();

    expect(find.text('${now.year}년 ${now.month}월'), findsOneWidget);
    expect(find.text('1개'), findsWidgets); // 완료 퀘스트(달성 목표 0개와 구분 없이 개수만 확인)
    expect(find.text('🧘 마음'), findsOneWidget);
    expect(find.text('+15 XP'), findsOneWidget);
  });

  testWidgets('활동이 없으면 빈 상태 안내가 나온다', (tester) async {
    final storage = await createTestStorage();
    await pumpApp(tester, storage, const ReportScreen());

    expect(find.text('이 기간에 완료한 퀘스트가 없어요.'), findsOneWidget);
    expect(find.text('이 기간에 기록된 거래가 없어요.'), findsOneWidget);
  });
}
