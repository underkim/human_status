// Phase 6 Part B — 시각 전용 차트(fl_chart BarChart/LineChart)에 보조기술
// 대체 semantics 요약이 제공되는지, 그리고 축 라벨 등 차트 내부 요소가
// 중복 낭독되지 않도록 제외됐는지 확인한다.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:human_status/models/asset_snapshot.dart';
import 'package:human_status/models/quest.dart';
import 'package:human_status/models/transaction.dart';
import 'package:human_status/providers/profile_provider.dart';
import 'package:human_status/providers/progression_provider.dart';
import 'package:human_status/screens/asset_snapshot_screen.dart';
import 'package:human_status/screens/finance_screen.dart';
import 'package:human_status/screens/insights_screen.dart';
import 'package:human_status/screens/report_screen.dart';
import 'package:human_status/theme/app_theme.dart';

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

  testWidgets(
    '리포트의 XP 추이 차트는 시각 요소 없이도 가장 많이 획득한 구간을 알 수 있는 semantics 요약을 제공한다',
    (tester) async {
      setScreenSize(tester, const Size(600, 1600));
      final storage = await createTestStorage();
      final now = DateTime.now();
      final monday = DateTime(now.year, now.month, now.day - (now.weekday - 1));
      await storage.saveQuest(
        Quest(
          id: 'w1',
          title: 'w1',
          description: '',
          statRewards: const {'health': 50},
          status: QuestStatus.completed,
          createdAt: monday,
          completedAt: monday,
        ),
      );
      final handle = tester.ensureSemantics();

      await pumpApp(tester, storage, const ReportScreen());
      await tester.pumpAndSettle();

      expect(findBySemanticsLabelContaining('XP 추이'), findsOneWidget);
      expect(findBySemanticsLabelContaining('가장 많이 획득한 구간'), findsOneWidget);
      expect(findBySemanticsLabelContaining('50XP'), findsOneWidget);

      handle.dispose();
    },
  );

  testWidgets(
    '통계의 최근 7일 XP 차트는 시각 요소 없이도 가장 많이 획득한 요일을 알 수 있는 semantics 요약을 제공한다',
    (tester) async {
      final storage = await createTestStorage();
      final fixedNow = DateTime(2026, 7, 16, 10); // Thursday
      await storage.saveQuest(
        Quest(
          id: 'today',
          title: 'today',
          description: '',
          statRewards: const {'health': 30},
          status: QuestStatus.completed,
          createdAt: fixedNow,
          completedAt: fixedNow,
        ),
      );
      final handle = tester.ensureSemantics();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            storageServiceProvider.overrideWithValue(storage),
            nowProvider.overrideWithValue(fixedNow),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            home: const InsightsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // '최근 7일 XP'만으로는 섹션 제목 Text와도 겹치므로, 콜론이 붙은
      // 요약 문장 시작 부분으로 semantics 요약 자체가 붙었는지 확인한다.
      expect(findBySemanticsLabelContaining('최근 7일 XP:'), findsOneWidget);
      expect(findBySemanticsLabelContaining('가장 많이 획득한 요일'), findsOneWidget);
      expect(findBySemanticsLabelContaining('30XP'), findsOneWidget);

      handle.dispose();
    },
  );

  testWidgets('자산 순자산 추이 차트는 시각 요소 없이도 기간·최고 순자산을 알 수 있는 semantics 요약을 제공한다', (
    tester,
  ) async {
    final storage = await createTestStorage();
    await storage.saveAssetSnapshot(
      AssetSnapshot(
        id: 's1',
        importedAt: DateTime(2026, 7, 1),
        assetsByCategory: const {'현금': 1000000},
        liabilitiesByCategory: const {},
        totalAssets: 1000000,
        totalLiabilities: 0,
      ),
    );
    await storage.saveAssetSnapshot(
      AssetSnapshot(
        id: 's2',
        importedAt: DateTime(2026, 7, 15),
        assetsByCategory: const {'현금': 1500000},
        liabilitiesByCategory: const {},
        totalAssets: 1500000,
        totalLiabilities: 0,
      ),
    );
    final handle = tester.ensureSemantics();

    await pumpApp(tester, storage, const AssetSnapshotListView());
    await tester.pumpAndSettle();

    // '순자산 추이'는 카드 제목 Text와도 겹치므로, 요약 문장에서만 나오는
    // 부분으로 semantics 요약 자체가 붙었는지 확인한다.
    expect(findBySemanticsLabelContaining('7/1'), findsOneWidget);
    expect(findBySemanticsLabelContaining('500,000원 증가'), findsOneWidget);
    expect(findBySemanticsLabelContaining('최고 순자산은'), findsOneWidget);

    handle.dispose();
  });
}
