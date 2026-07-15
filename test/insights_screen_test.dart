import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:human_status/models/quest.dart';
import 'package:human_status/providers/profile_provider.dart';
import 'package:human_status/providers/progression_provider.dart';
import 'package:human_status/screens/insights_screen.dart';
import 'package:human_status/services/storage_service.dart';
import 'package:human_status/theme/app_theme.dart';

import 'helpers/test_app.dart';

final _fixedNow = DateTime(2026, 7, 16, 10); // Thursday

Future<void> _pumpInsights(WidgetTester tester, StorageService storage) {
  return tester.pumpWidget(
    ProviderScope(
      overrides: [
        storageServiceProvider.overrideWithValue(storage),
        nowProvider.overrideWithValue(_fixedNow),
      ],
      child: MaterialApp(theme: AppTheme.light, home: const InsightsScreen()),
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
  testWidgets('상단 요약이 대시보드 성장 여정 카드와 같은 스냅샷 값을 보여준다', (tester) async {
    final storage = await createTestStorage();
    await _completeQuest(storage, DateTime(2026, 7, 13)); // 이번 주 월
    await _completeQuest(storage, DateTime(2026, 7, 14)); // 이번 주 화
    await _completeQuest(storage, _fixedNow); // 오늘(목)

    await _pumpInsights(tester, storage);

    // currentStreak: 6/13,14 연속(2일)은 끊기고 오늘 하루만 살아있는 연속.
    expect(find.text('1일 연속'), findsOneWidget);
    expect(find.text('오늘의 몫을 지켰어요. 내일도 이어가볼까요?'), findsOneWidget);
    expect(find.text('최고 기록 2일'), findsOneWidget);
    expect(find.text('이번 주 3/7일'), findsOneWidget);
  });

  testWidgets('연속 기록이 없을 때는 시작 안내 문구를 보여준다', (tester) async {
    final storage = await createTestStorage();

    await _pumpInsights(tester, storage);

    expect(find.text('0일 연속'), findsOneWidget);
    expect(find.text('오늘부터 다시 시작해볼까요? 첫 걸음이 연속 기록의 시작이에요.'), findsOneWidget);
    expect(find.text('최고 기록 0일'), findsOneWidget);
    expect(find.text('이번 주 0/7일'), findsOneWidget);
  });

  testWidgets('상단 요약과 별개로 기존 업적 그리드가 그대로 유지된다', (tester) async {
    final storage = await createTestStorage();
    await _completeQuest(storage, _fixedNow);

    await _pumpInsights(tester, storage);
    // first_quest는 방금 완료로 잠금 해제되지 않았다(퀘스트 완료 흐름을 거치지
    // 않고 storage에 직접 심었으므로) — 다음 업적 진행도가 여전히 보인다.
    expect(find.textContaining('다음 업적:'), findsOneWidget);

    await tester.dragUntilVisible(
      find.text('업적'),
      find.byType(ListView),
      const Offset(0, -200),
    );
    expect(find.text('업적'), findsOneWidget);
  });
}
