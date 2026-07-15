import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:human_status/data/achievement_definitions.dart';
import 'package:human_status/models/quest.dart';
import 'package:human_status/providers/profile_provider.dart';
import 'package:human_status/providers/progression_provider.dart';
import 'package:human_status/screens/dashboard_screen.dart';
import 'package:human_status/screens/insights_screen.dart';
import 'package:human_status/services/storage_service.dart';
import 'package:human_status/theme/app_theme.dart';
import 'package:human_status/widgets/progression_journey_card.dart';

import 'helpers/test_app.dart';

final _fixedNow = DateTime(2026, 7, 16, 10); // a Thursday

Future<void> _pumpCard(
  WidgetTester tester,
  StorageService storage, {
  DateTime? now,
}) {
  return tester.pumpWidget(
    ProviderScope(
      overrides: [
        storageServiceProvider.overrideWithValue(storage),
        nowProvider.overrideWithValue(now ?? _fixedNow),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(
          body: SingleChildScrollView(child: ProgressionJourneyCard()),
        ),
      ),
    ),
  );
}

Future<void> _completeQuest(
  StorageService storage,
  DateTime completedAt,
) async {
  await storage.saveQuest(
    Quest(
      id: 'q-${completedAt.toIso8601String()}',
      title: '완료된 퀘스트',
      description: '',
      statRewards: const {'health': 10},
      status: QuestStatus.completed,
      createdAt: completedAt,
      completedAt: completedAt,
    ),
  );
}

void main() {
  group('상태 문구 3가지', () {
    testWidgets('오늘 완료했으면 "오늘의 몫을 지켰어요" 문구가 뜬다', (tester) async {
      final storage = await createTestStorage();
      await _completeQuest(storage, _fixedNow);

      await _pumpCard(tester, storage);

      expect(find.text('오늘의 몫을 지켰어요. 내일도 이어가볼까요?'), findsOneWidget);
      expect(find.text('🔥 1일'), findsOneWidget);
    });

    testWidgets('어제까지만 연속이면 "퀘스트 하나만 완료하면 이어져요" 문구가 뜬다', (tester) async {
      final storage = await createTestStorage();
      await _completeQuest(
        storage,
        _fixedNow.subtract(const Duration(days: 1)),
      );

      await _pumpCard(tester, storage);

      expect(find.text('퀘스트 하나만 완료하면 연속 기록이 오늘도 이어져요.'), findsOneWidget);
      expect(find.text('🔥 1일'), findsOneWidget);
    });

    testWidgets('연속 기록이 없으면 "오늘부터 다시 시작해볼까요?" 문구가 뜬다', (tester) async {
      final storage = await createTestStorage();

      await _pumpCard(tester, storage);

      expect(find.text('오늘부터 다시 시작해볼까요? 첫 걸음이 연속 기록의 시작이에요.'), findsOneWidget);
      expect(find.text('🔥 0일'), findsOneWidget);
    });
  });

  testWidgets('완료된 퀘스트가 쌓이면 이번 주 활동일과 최고 기록이 갱신된다', (tester) async {
    final storage = await createTestStorage();
    await _completeQuest(storage, DateTime(2026, 7, 13)); // 이번 주 월
    await _completeQuest(storage, DateTime(2026, 7, 14)); // 이번 주 화
    await _completeQuest(storage, DateTime(2026, 7, 16)); // 오늘(목)

    await _pumpCard(tester, storage);

    expect(find.text('⭐ 2일'), findsOneWidget); // 6/13-14 최고 연속 2일
    expect(find.text('📅 3/7일'), findsOneWidget);
  });

  testWidgets('오늘의 행동에서 퀘스트를 완료하면 성장 여정 카드가 즉시 갱신된다', (tester) async {
    final storage = await createTestStorage();
    await storage.saveQuest(
      Quest(
        id: 'q1',
        title: '스트레칭',
        description: '',
        statRewards: const {'health': 10},
        createdAt: DateTime(2026, 7, 1),
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          storageServiceProvider.overrideWithValue(storage),
          nowProvider.overrideWithValue(_fixedNow),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: const DashboardScreen(),
        ),
      ),
    );

    expect(find.text('오늘부터 다시 시작해볼까요? 첫 걸음이 연속 기록의 시작이에요.'), findsOneWidget);
    expect(find.text('🔥 0일'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, '완료'));
    await tester.pumpAndSettle();
    final confirmButton = find.text('확인');
    if (confirmButton.evaluate().isNotEmpty) {
      await tester.tap(confirmButton);
      await tester.pumpAndSettle();
    }

    expect(find.text('오늘의 몫을 지켰어요. 내일도 이어가볼까요?'), findsOneWidget);
    expect(find.text('🔥 1일'), findsOneWidget);
  });

  group('다음 업적', () {
    testWidgets('현재 가장 가까운 업적의 진행도와 라벨이 보인다', (tester) async {
      final storage = await createTestStorage();
      // 모든 업적을 미리 잠금 해제해두고 first_quest만 남겨 결정적으로 만든다.
      for (final def in achievementDefinitions) {
        if (def.id == 'first_quest') continue;
        await storage.unlockAchievement(def.id, DateTime(2026, 1, 1));
      }

      await _pumpCard(tester, storage);

      final firstQuestDef = achievementDefinitions.firstWhere(
        (d) => d.id == 'first_quest',
      );
      expect(
        find.textContaining('다음 업적: ${firstQuestDef.title}'),
        findsOneWidget,
      );
      expect(find.text('0/1개 완료'), findsOneWidget);
    });

    testWidgets('퀘스트 완료로 해당 업적이 잠금 해제되면 다음 후보로 넘어가거나 완료 문구로 바뀐다', (
      tester,
    ) async {
      final storage = await createTestStorage();
      for (final def in achievementDefinitions) {
        if (def.id == 'first_quest') continue;
        await storage.unlockAchievement(def.id, DateTime(2026, 1, 1));
      }
      await storage.saveQuest(
        Quest(
          id: 'q1',
          title: '스트레칭',
          description: '',
          statRewards: const {'health': 10},
          createdAt: DateTime(2026, 7, 1),
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            storageServiceProvider.overrideWithValue(storage),
            nowProvider.overrideWithValue(_fixedNow),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            home: const DashboardScreen(),
          ),
        ),
      );

      expect(find.text('0/1개 완료'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, '완료'));
      await tester.pumpAndSettle();
      final confirmButton = find.text('확인');
      if (confirmButton.evaluate().isNotEmpty) {
        await tester.tap(confirmButton);
        await tester.pumpAndSettle();
      }

      // first_quest was the only remaining locked achievement, so once it
      // unlocks every measurable achievement is now unlocked.
      expect(find.text('모든 업적을 달성했어요! 🎉'), findsOneWidget);
      expect(find.text('0/1개 완료'), findsNothing);
    });
  });

  testWidgets('통계·업적 보기를 누르면 InsightsScreen이 하나만 열린다', (tester) async {
    final storage = await createTestStorage();
    await _pumpCard(tester, storage);

    await tester.tap(find.text('통계·업적 보기'));
    await tester.pumpAndSettle();

    expect(find.byType(InsightsScreen), findsOneWidget);
  });
}
