import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:human_status/models/quest.dart';
import 'package:human_status/providers/profile_provider.dart';
import 'package:human_status/providers/quest_provider.dart';
import 'package:human_status/services/storage_service.dart';
import 'package:human_status/widgets/action_hub_card.dart';

import 'helpers/test_app.dart';

/// completeQuest는 [respond]가 반환하는 Future를 그대로 돌려주므로, 테스트가
/// 이 Future를 직접 쥐고 완료/실패 시점을 통제할 수 있다.
class _ControlledQuestsNotifier extends QuestsNotifier {
  final Future<QuestCompletionResult> Function() respond;
  int completeCallCount = 0;

  _ControlledQuestsNotifier(super.storage, super.ref, this.respond);

  @override
  Future<QuestCompletionResult> completeQuest(String id) {
    completeCallCount++;
    return respond();
  }
}

Future<Quest> _seedActiveQuest(StorageService storage) async {
  final quest = Quest(
    id: 'q1',
    title: '스트레칭',
    description: '',
    statRewards: {'health': 10},
    createdAt: DateTime(2026, 7, 1),
  );
  await storage.saveQuest(quest);
  return quest;
}

Future<void> _pumpHub(
  WidgetTester tester,
  StorageService storage,
  _ControlledQuestsNotifier Function(Ref ref) createNotifier,
) {
  return tester.pumpWidget(
    ProviderScope(
      overrides: [
        storageServiceProvider.overrideWithValue(storage),
        questsProvider.overrideWith(createNotifier),
      ],
      child: const MaterialApp(home: Scaffold(body: ActionHubCard())),
    ),
  );
}

void main() {
  testWidgets('완료 처리 중에는 완료 버튼이 비활성화되고 완료 요청이 중복 호출되지 않는다', (tester) async {
    final storage = await createTestStorage();
    await _seedActiveQuest(storage);

    late _ControlledQuestsNotifier notifier;
    final completer = Completer<QuestCompletionResult>();

    await _pumpHub(tester, storage, (ref) {
      notifier = _ControlledQuestsNotifier(
        storage,
        ref,
        () => completer.future,
      );
      return notifier;
    });
    await tester.pump();

    expect(find.byType(FilledButton), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNotNull,
    );

    await tester.tap(find.byType(FilledButton));
    await tester.pump();

    expect(notifier.completeCallCount, 1);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );

    // Pending 상태에서 다시 탭해도(버튼이 비활성화돼 있으므로) 완료 요청은
    // 늘어나지 않는다.
    await tester.tap(find.byType(FilledButton));
    await tester.pump();
    expect(notifier.completeCallCount, 1);

    completer.complete(
      const QuestCompletionResult(levelUps: {}, newAchievements: []),
    );
    await tester.pumpAndSettle();

    expect(notifier.completeCallCount, 1);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNotNull,
    );
  });

  testWidgets('완료 실패 시 퀘스트는 그대로 남고 성공 UI 없이 재시도 가능한 에러 스낵바만 뜬다', (
    tester,
  ) async {
    final storage = await createTestStorage();
    await _seedActiveQuest(storage);

    await _pumpHub(tester, storage, (ref) {
      return _ControlledQuestsNotifier(
        storage,
        ref,
        () => Future<QuestCompletionResult>.error(Exception('boom')),
      );
    });
    await tester.pump();

    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();

    expect(find.text('스트레칭'), findsOneWidget);
    expect(find.byType(FilledButton), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNotNull,
    );
    expect(find.textContaining('실패'), findsOneWidget);
    expect(find.text('재시도'), findsOneWidget);
    expect(find.text('🏆 업적 달성!'), findsNothing);
    expect(find.text('"스트레칭" 완료!'), findsNothing);
  });
}
