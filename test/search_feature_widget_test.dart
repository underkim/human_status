import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:human_status/models/quest.dart';
import 'package:human_status/models/transaction.dart';
import 'package:human_status/screens/finance_screen.dart';
import 'package:human_status/screens/quests_screen.dart';
import 'package:human_status/widgets/transaction_tile.dart';

import 'helpers/test_app.dart';

Quest _quest(
  String id,
  String title, {
  String description = '',
  QuestStatus status = QuestStatus.active,
  double xp = 10,
}) {
  return Quest(
    id: id,
    title: title,
    description: description,
    statRewards: {'health': xp},
    status: status,
    source: status == QuestStatus.suggested
        ? QuestSource.suggested
        : QuestSource.manual,
    createdAt: DateTime(2026, 7, 1),
  );
}

Transaction _tx(
  String id, {
  String category = '식비',
  String memo = '',
  TransactionType type = TransactionType.expense,
  double amount = 1000,
  DateTime? date,
}) {
  final d = date ?? DateTime(2026, 7, 10);
  return Transaction(
    id: id,
    type: type,
    category: category,
    memo: memo,
    amount: amount,
    date: d,
    createdAt: d,
  );
}

Future<void> _openQuestSearch(WidgetTester tester) async {
  await tester.tap(find.byTooltip('퀘스트 검색'));
  await tester.pumpAndSettle();
}

Future<void> _typeInto(WidgetTester tester, Finder field, String text) async {
  await tester.enterText(field, text);
  await tester.pump();
}

/// [text]를 담은 거래 목록의 [TransactionTile]만 찾는다 — 같은 문자열이
/// "이번 달 카테고리별 지출" 카드에도 독립적으로 나타날 수 있어(요약은 검색과
/// 무관하게 전체 거래를 기준으로 계산되므로) 일반 find.text만으로는
/// 모호하다.
Finder _tileText(String text) => find.descendant(
  of: find.byType(TransactionTile),
  matching: find.text(text),
);

/// 완료 성공 시 뜨는 레벨업/업적 다이얼로그를 모두 닫는다 —
/// test/quests_screen_flow_test.dart의 같은 패턴.
Future<void> _dismissCelebrationDialogs(WidgetTester tester) async {
  await tester.pumpAndSettle();
  while (find.text('확인').evaluate().isNotEmpty) {
    await tester.tap(find.text('확인').first);
    await tester.pumpAndSettle();
  }
}

/// "이번 달 카테고리별 지출" 카드 안의 [category] 행을 탭해 카테고리 필터를
/// 설정/해제한다.
Future<void> _tapCategoryBreakdownRow(
  WidgetTester tester,
  String category,
) async {
  final card = find.ancestor(
    of: find.text('이번 달 카테고리별 지출'),
    matching: find.byType(Card),
  );
  await tester.tap(find.descendant(of: card, matching: find.text(category)));
  await tester.pumpAndSettle();
}

void main() {
  group('퀘스트 검색', () {
    testWidgets('AppBar의 검색 아이콘을 누르면 한국어 힌트의 검색 입력과 닫기 버튼이 표시된다', (
      tester,
    ) async {
      final storage = await createTestStorage();
      await storage.saveQuest(_quest('q1', '물 마시기'));
      await pumpApp(tester, storage, const QuestsScreen());

      expect(find.byTooltip('검색 닫기'), findsNothing);

      await _openQuestSearch(tester);

      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.decoration?.hintText, '퀘스트 검색');
      expect(find.byTooltip('검색 닫기'), findsOneWidget);
      // 검색어가 비어 있을 때는 지우기 버튼이 보이지 않는다.
      expect(find.byTooltip('검색어 지우기'), findsNothing);
    });

    testWidgets('퀘스트 제목을 입력하면 일치하는 카드만 남고 진행중 탭 건수가 검색 결과 수로 바뀐다', (
      tester,
    ) async {
      final storage = await createTestStorage();
      await storage.saveQuest(_quest('q1', '물 마시기'));
      await storage.saveQuest(_quest('q2', '운동하기'));
      await pumpApp(tester, storage, const QuestsScreen());

      await _openQuestSearch(tester);
      await _typeInto(tester, find.byType(TextField), '물');

      expect(find.text('물 마시기'), findsOneWidget);
      expect(find.text('운동하기'), findsNothing);
      expect(find.text('진행중 (1)'), findsOneWidget);
    });

    testWidgets('퀘스트 설명으로 검색해도 일치하며 추천과 완료 탭에도 같은 검색어가 유지된다', (tester) async {
      final storage = await createTestStorage();
      await storage.saveQuest(_quest('a1', '아침 루틴', description: '가벼운 산책 30분'));
      await storage.saveQuest(
        _quest('s1', '저녁 산책', status: QuestStatus.suggested),
      );
      await storage.saveQuest(
        _quest('c1', '산책 완료 기록', status: QuestStatus.completed),
      );
      await pumpApp(tester, storage, const QuestsScreen());

      await _openQuestSearch(tester);
      await _typeInto(tester, find.byType(TextField), '산책');

      // 진행중 탭: description으로 매치.
      expect(find.text('아침 루틴'), findsOneWidget);
      expect(find.text('진행중 (1)'), findsOneWidget);
      expect(find.text('추천 (1)'), findsOneWidget);
      expect(find.text('완료 (1)'), findsOneWidget);

      // 검색어를 유지한 채 추천 탭으로 전환.
      await tester.tap(find.byType(Tab).at(1));
      await tester.pumpAndSettle();
      expect(find.text('저녁 산책'), findsOneWidget);
      final suggestedField = tester.widget<TextField>(find.byType(TextField));
      expect(suggestedField.controller?.text, '산책');

      // 완료 탭에서도 같은 검색어로 필터링된 결과가 보인다.
      await tester.tap(find.byType(Tab).at(2));
      await tester.pumpAndSettle();
      expect(find.text('산책 완료 기록'), findsOneWidget);
    });

    testWidgets('검색 중 퀘스트를 완료하면 진행중 결과에서 사라지고 완료 탭 결과에 나타난다', (tester) async {
      final storage = await createTestStorage();
      await storage.saveQuest(_quest('q1', '물 마시기'));
      await pumpApp(tester, storage, const QuestsScreen());

      await _openQuestSearch(tester);
      await _typeInto(tester, find.byType(TextField), '물');
      expect(find.text('진행중 (1)'), findsOneWidget);

      await tester.tap(find.text('완료'));
      await _dismissCelebrationDialogs(tester);

      expect(find.text('진행중 (0)'), findsOneWidget);
      expect(find.text('완료 (1)'), findsOneWidget);

      await tester.tap(find.byType(Tab).at(2));
      await tester.pumpAndSettle();
      expect(find.text('물 마시기'), findsOneWidget);
      // 검색어는 완료 처리 이후에도 그대로 유지된다.
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller?.text, '물');
    });

    testWidgets('퀘스트 검색 결과가 없으면 검색 전용 EmptyState가 표시되고 검색어 지우기로 원본 목록이 복원된다', (
      tester,
    ) async {
      final storage = await createTestStorage();
      await storage.saveQuest(_quest('q1', '물 마시기'));
      await pumpApp(tester, storage, const QuestsScreen());

      await _openQuestSearch(tester);
      await _typeInto(tester, find.byType(TextField), '존재하지않는검색어');

      expect(find.text('검색 결과가 없어요.'), findsOneWidget);
      expect(find.text('물 마시기'), findsNothing);

      await tester.tap(find.widgetWithText(OutlinedButton, '검색어 지우기'));
      await tester.pumpAndSettle();

      expect(find.text('물 마시기'), findsOneWidget);
      expect(find.text('진행중 (1)'), findsOneWidget);
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller?.text, '');
    });

    testWidgets('원본 퀘스트가 아예 없으면 검색해도 검색 전용 EmptyState가 아닌 원래 빈 상태 문구가 유지된다', (
      tester,
    ) async {
      final storage = await createTestStorage();
      await pumpApp(tester, storage, const QuestsScreen());

      expect(
        find.text('진행중인 퀘스트가 없어요.\n오른쪽 아래 + 버튼으로 추가해보세요.'),
        findsOneWidget,
      );

      await _openQuestSearch(tester);
      await _typeInto(tester, find.byType(TextField), '아무거나');

      // 원본 데이터가 없는 것과 검색 결과가 없는 것은 다른 상태다 — 원본이
      // 아예 없을 때는 검색어를 입력해도 탭 최초의 빈 상태 문구를 유지해야
      // 하며, "검색 결과가 없어요."로 바뀌면 안 된다.
      expect(
        find.text('진행중인 퀘스트가 없어요.\n오른쪽 아래 + 버튼으로 추가해보세요.'),
        findsOneWidget,
      );
      expect(find.text('검색 결과가 없어요.'), findsNothing);

      await tester.tap(find.byType(Tab).at(1));
      await tester.pumpAndSettle();
      expect(find.text('추천 퀘스트가 없어요.\n하루가 지나면 새로운 추천이 생성돼요.'), findsOneWidget);
      expect(find.text('검색 결과가 없어요.'), findsNothing);

      await tester.tap(find.byType(Tab).at(2));
      await tester.pumpAndSettle();
      expect(find.text('아직 완료한 퀘스트가 없어요.'), findsOneWidget);
      expect(find.text('검색 결과가 없어요.'), findsNothing);
    });

    testWidgets('검색 닫기는 검색어를 비우고 일반 AppBar와 원본 탭 건수를 복원한다', (tester) async {
      final storage = await createTestStorage();
      await storage.saveQuest(_quest('q1', '물 마시기'));
      await storage.saveQuest(_quest('q2', '운동하기'));
      await pumpApp(tester, storage, const QuestsScreen());

      await _openQuestSearch(tester);
      await _typeInto(tester, find.byType(TextField), '물');
      expect(find.text('진행중 (1)'), findsOneWidget);

      await tester.tap(find.byTooltip('검색 닫기'));
      await tester.pumpAndSettle();

      expect(find.text('퀘스트'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      expect(find.text('진행중 (2)'), findsOneWidget);
      expect(find.byTooltip('퀘스트 검색'), findsOneWidget);
    });
  });

  group('거래 검색', () {
    testWidgets('검색 입력은 memo와 category 각각으로 거래를 필터링하고 N건 표시를 갱신한다', (
      tester,
    ) async {
      setScreenSize(tester, const Size(800, 2000));
      final storage = await createTestStorage();
      await storage.saveTransaction(_tx('t1', category: '식비', memo: '점심 식사'));
      await storage.saveTransaction(_tx('t2', category: '카페', memo: '아메리카노'));
      await pumpApp(tester, storage, const Scaffold(body: FinanceListView()));

      expect(find.text('2건'), findsOneWidget);
      expect(find.byType(TransactionTile), findsNWidgets(2));

      await _typeInto(tester, find.byType(TextField), '아메리카노');
      expect(find.text('1건'), findsOneWidget);
      expect(find.byType(TransactionTile), findsOneWidget);
      expect(_tileText('카페'), findsOneWidget);
      expect(_tileText('식비'), findsNothing);

      await tester.tap(find.byTooltip('검색어 지우기'));
      await tester.pump();
      await _typeInto(tester, find.byType(TextField), '식비');
      expect(find.text('1건'), findsOneWidget);
      expect(find.byType(TransactionTile), findsOneWidget);
      expect(_tileText('식비'), findsOneWidget);
      expect(_tileText('카페'), findsNothing);
    });

    testWidgets('영문 대소문자를 무시하고 한글 부분 문자열을 찾는다', (tester) async {
      setScreenSize(tester, const Size(800, 2000));
      final storage = await createTestStorage();
      await storage.saveTransaction(_tx('t1', category: 'Cafe', memo: '아메리카노'));
      await storage.saveTransaction(_tx('t2', category: '식비', memo: '김밥'));
      await pumpApp(tester, storage, const Scaffold(body: FinanceListView()));

      await _typeInto(tester, find.byType(TextField), 'CAFE');
      expect(find.text('1건'), findsOneWidget);
      expect(_tileText('Cafe'), findsOneWidget);

      await tester.tap(find.byTooltip('검색어 지우기'));
      await tester.pump();
      await _typeInto(tester, find.byType(TextField), '아메리카노');
      expect(find.text('1건'), findsOneWidget);
      expect(_tileText('Cafe'), findsOneWidget);
    });

    testWidgets('카테고리 InputChip과 AND 조건으로 적용된다', (tester) async {
      setScreenSize(tester, const Size(800, 2000));
      final storage = await createTestStorage();
      final now = DateTime.now();
      await storage.saveTransaction(
        _tx('t1', category: '식비', memo: '점심', date: now),
      );
      await storage.saveTransaction(
        _tx('t2', category: '식비', memo: '커피', date: now),
      );
      await storage.saveTransaction(
        _tx('t3', category: '카페', memo: '커피', date: now),
      );
      await pumpApp(tester, storage, const Scaffold(body: FinanceListView()));

      await _tapCategoryBreakdownRow(tester, '식비');
      expect(find.text('카테고리: 식비'), findsOneWidget);
      expect(find.text('2건'), findsOneWidget);

      await _typeInto(tester, find.byType(TextField), '커피');

      // AND 조건: 카테고리가 식비이면서 검색어를 포함하는 t2만 남는다 — 검색어만
      // 만족하는 카페(t3)는 카테고리 필터에 막혀 보이지 않는다.
      expect(find.text('1건'), findsOneWidget);
      expect(find.byType(TransactionTile), findsOneWidget);
    });

    testWidgets('검색어 지우기는 검색만 해제하고 선택된 카테고리 필터는 유지한다', (tester) async {
      setScreenSize(tester, const Size(800, 2000));
      final storage = await createTestStorage();
      final now = DateTime.now();
      await storage.saveTransaction(
        _tx('t1', category: '식비', memo: '점심', date: now),
      );
      await storage.saveTransaction(
        _tx('t2', category: '식비', memo: '커피', date: now),
      );
      await pumpApp(tester, storage, const Scaffold(body: FinanceListView()));

      await _tapCategoryBreakdownRow(tester, '식비');
      await _typeInto(tester, find.byType(TextField), '커피');
      expect(find.text('1건'), findsOneWidget);

      await tester.tap(find.byTooltip('검색어 지우기'));
      await tester.pumpAndSettle();

      // 카테고리 필터는 그대로 남아 두 건 모두 다시 보인다.
      expect(find.text('카테고리: 식비'), findsOneWidget);
      expect(find.text('2건'), findsOneWidget);
    });

    testWidgets('검색 및 필터 초기화 CTA는 두 조건을 모두 해제하고 전체 거래를 복원한다', (tester) async {
      setScreenSize(tester, const Size(800, 2000));
      final storage = await createTestStorage();
      final now = DateTime.now();
      await storage.saveTransaction(
        _tx('t1', category: '식비', memo: '점심', date: now),
      );
      await storage.saveTransaction(
        _tx('t2', category: '카페', memo: '커피', date: now),
      );
      await pumpApp(tester, storage, const Scaffold(body: FinanceListView()));

      await _tapCategoryBreakdownRow(tester, '식비');
      await _typeInto(tester, find.byType(TextField), '존재하지않는검색어');

      expect(find.text('검색 조건에 맞는 거래가 없어요.'), findsOneWidget);

      await tester.tap(find.widgetWithText(OutlinedButton, '검색 및 필터 초기화'));
      await tester.pumpAndSettle();

      expect(find.text('카테고리: 식비'), findsNothing);
      expect(find.text('2건'), findsOneWidget);
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller?.text, '');
    });

    testWidgets('검색 결과의 거래는 날짜 내림차순과 해당 월 헤더를 유지한다', (tester) async {
      setScreenSize(tester, const Size(800, 2000));
      final storage = await createTestStorage();
      await storage.saveTransaction(
        _tx('t1', category: '카페', memo: '검색어 커피', date: DateTime(2026, 7, 20)),
      );
      await storage.saveTransaction(
        _tx('t2', category: '식비', memo: '검색어 점심', date: DateTime(2026, 7, 5)),
      );
      await storage.saveTransaction(
        _tx('t3', category: '카페', memo: '검색어 저녁', date: DateTime(2026, 5, 15)),
      );
      await storage.saveTransaction(
        _tx('t4', category: '기타', memo: '매치안됨', date: DateTime(2026, 7, 10)),
      );
      await pumpApp(tester, storage, const Scaffold(body: FinanceListView()));

      await _typeInto(tester, find.byType(TextField), '검색어');

      expect(find.text('3건'), findsOneWidget);
      expect(find.byType(TransactionTile), findsNWidgets(3));
      expect(_tileText('기타'), findsNothing);
      expect(find.text('2026년 7월'), findsOneWidget);
      expect(find.text('2026년 5월'), findsOneWidget);

      // 날짜 내림차순: 7월 헤더가 5월 헤더보다 위에 있다.
      final julyY = tester.getTopLeft(find.text('2026년 7월')).dy;
      final mayY = tester.getTopLeft(find.text('2026년 5월')).dy;
      expect(julyY, lessThan(mayY));
      // 7월 그룹 안에서도 7/20(t1, memo "검색어 커피")이 7/5(t2, memo "검색어
      // 점심")보다 위에 있다 — 카테고리 '카페'는 t1과 t3(5월) 둘 다에 쓰여
      // 모호하므로 각 거래를 유일하게 식별하는 memo 텍스트로 비교한다.
      final julyTxY = tester.getTopLeft(_tileText('검색어 커피')).dy;
      final julyOlderTxY = tester.getTopLeft(_tileText('검색어 점심')).dy;
      expect(julyTxY, lessThan(julyOlderTxY));
    });

    testWidgets(
      '검색 중 transactionsProvider가 추가 또는 삭제로 갱신되면 현재 검색어로 목록이 즉시 재계산된다',
      (tester) async {
        setScreenSize(tester, const Size(800, 2000));
        final storage = await createTestStorage();
        await storage.saveTransaction(_tx('t1', category: '카페', memo: '커피 한잔'));
        await storage.saveTransaction(_tx('t2', category: '식비', memo: '점심'));
        await pumpApp(tester, storage, const Scaffold(body: FinanceListView()));

        await _typeInto(tester, find.byType(TextField), '커피');
        expect(find.text('1건'), findsOneWidget);
        expect(_tileText('카페'), findsOneWidget);

        // 삭제: 검색 중인 유일한 결과를 지우면 검색 전용 EmptyState로 즉시
        // 재계산된다.
        await tester.tap(find.byIcon(Icons.delete_outline));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FilledButton, '삭제'));
        await tester.pumpAndSettle();
        expect(find.text('검색 조건에 맞는 거래가 없어요.'), findsOneWidget);

        // 추가: 검색어와 일치하는 거래를 새로 추가하면 다시 나타난다. 검색
        // 입력창이 다이얼로그 아래에서도 계속 마운트돼 있으므로, 전역
        // TextField 인덱스 대신 AlertDialog 안으로 범위를 좁혀 찾는다.
        await tester.tap(find.byTooltip('거래 직접 추가'));
        await tester.pumpAndSettle();
        final dialogFields = find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextField),
        );
        await tester.enterText(dialogFields.at(0), '카페'); // 카테고리
        await tester.enterText(dialogFields.at(1), '커피 두잔'); // 메모
        await tester.enterText(dialogFields.at(2), '4500'); // 금액
        await tester.tap(find.widgetWithText(FilledButton, '추가'));
        await tester.pumpAndSettle();

        expect(find.text('1건'), findsOneWidget);
        expect(_tileText('카페'), findsOneWidget);
      },
    );

    testWidgets('원본 거래가 아예 없으면 검색해도 검색 전용 EmptyState가 아닌 원래 빈 상태 문구가 유지된다', (
      tester,
    ) async {
      setScreenSize(tester, const Size(800, 2000));
      final storage = await createTestStorage();
      await pumpApp(tester, storage, const Scaffold(body: FinanceListView()));

      expect(find.text('아직 기록된 거래가 없어요.'), findsOneWidget);

      await _typeInto(tester, find.byType(TextField), '아무거나');

      // 원본 거래가 없는 것과 검색 결과가 없는 것은 다른 상태다 — 원본이
      // 아예 없을 때는 검색어를 입력해도 "아직 기록된 거래가 없어요."를
      // 유지해야 하며, 검색 전용 문구로 바뀌면 안 된다.
      expect(find.text('아직 기록된 거래가 없어요.'), findsOneWidget);
      expect(find.text('검색 조건에 맞는 거래가 없어요.'), findsNothing);
    });

    testWidgets('좁은 화면에서도 검색 입력과 기존 거래 액션 Wrap에 overflow 예외가 발생하지 않는다', (
      tester,
    ) async {
      // finance_screen.dart의 거래 내역 헤더 Row는 ~400dp 미만에서는 이
      // 검색 기능과 무관하게 이미 넘칠 수 있다고 소스 주석에 문서화돼 있다
      // (그 아래로 내려가는 것은 Wrap의 줄바꿈으로 흡수). 검색 입력 자체가
      // 이 폭에서 추가로 넘치지 않는지가 이 테스트의 관심사이므로, 그
      // 경계보다 넉넉히 위인 폭을 쓴다.
      setScreenSize(tester, const Size(480, 3000));
      final storage = await createTestStorage();
      await storage.saveTransaction(_tx('t1', category: '식비', memo: '점심'));
      await pumpApp(tester, storage, const Scaffold(body: FinanceListView()));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      await _typeInto(tester, find.byType(TextField), '점심');
      expect(tester.takeException(), isNull);
    });
  });

  group('검색 상태 수명', () {
    testWidgets('화면을 나갔다 다시 열면 퀘스트와 거래 검색어가 남지 않는다', (tester) async {
      final storage = await createTestStorage();
      await storage.saveQuest(_quest('q1', '물 마시기'));
      await storage.saveQuest(_quest('q2', '운동하기'));

      final questsNavigatorKey = GlobalKey<NavigatorState>();
      await pumpApp(
        tester,
        storage,
        Navigator(
          key: questsNavigatorKey,
          onGenerateRoute: (_) =>
              MaterialPageRoute(builder: (_) => const QuestsScreen()),
        ),
      );

      await _openQuestSearch(tester);
      await _typeInto(tester, find.byType(TextField), '물');
      expect(find.text('진행중 (1)'), findsOneWidget);

      // 화면을 나간다 — QuestsScreen을 라우트에서 완전히 치워 dispose시킨다.
      questsNavigatorKey.currentState!.pushReplacement(
        MaterialPageRoute(builder: (_) => const SizedBox()),
      );
      await tester.pumpAndSettle();

      // 다시 들어온다 — 새 QuestsScreen State가 생성된다.
      questsNavigatorKey.currentState!.pushReplacement(
        MaterialPageRoute(builder: (_) => const QuestsScreen()),
      );
      await tester.pumpAndSettle();

      expect(find.text('퀘스트'), findsOneWidget);
      expect(find.text('진행중 (2)'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('거래 화면을 나갔다 다시 열어도 검색어가 남지 않는다', (tester) async {
      setScreenSize(tester, const Size(800, 2000));
      final storage = await createTestStorage();
      await storage.saveTransaction(_tx('t1', category: '식비', memo: '점심'));
      await storage.saveTransaction(_tx('t2', category: '카페', memo: '커피'));

      final financeNavigatorKey = GlobalKey<NavigatorState>();
      await pumpApp(
        tester,
        storage,
        Navigator(
          key: financeNavigatorKey,
          onGenerateRoute: (_) => MaterialPageRoute(
            builder: (_) => const Scaffold(body: FinanceListView()),
          ),
        ),
      );

      await _typeInto(tester, find.byType(TextField), '커피');
      expect(find.text('1건'), findsOneWidget);

      financeNavigatorKey.currentState!.pushReplacement(
        MaterialPageRoute(builder: (_) => const SizedBox()),
      );
      await tester.pumpAndSettle();

      financeNavigatorKey.currentState!.pushReplacement(
        MaterialPageRoute(
          builder: (_) => const Scaffold(body: FinanceListView()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('2건'), findsOneWidget);
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller?.text, '');
    });
  });
}
