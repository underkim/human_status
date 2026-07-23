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

/// adoptSuggestion 호출도 completeQuest와 같은 방식으로 테스트가 직접
/// 통제할 수 있게 한다.
class _ControlledAdoptQuestsNotifier extends QuestsNotifier {
  final Future<void> Function() respond;
  int adoptCallCount = 0;

  _ControlledAdoptQuestsNotifier(super.storage, super.ref, this.respond);

  @override
  Future<void> adoptSuggestion(String id) {
    adoptCallCount++;
    return respond();
  }
}

/// adoptSuggestion의 첫 호출은 실패하고, 재시도인 두 번째 호출부터는 실제
/// 구현(super)에 위임해 성공하는 QuestsNotifier — 재시도가 정확히 새 호출
/// 한 번을 만들고 실제로 상태를 전이시키는지 결정적으로 증명한다.
class _FlakyAdoptQuestsNotifier extends QuestsNotifier {
  _FlakyAdoptQuestsNotifier(super.storage, super.ref);

  int adoptCallCount = 0;

  @override
  Future<void> adoptSuggestion(String id) async {
    adoptCallCount++;
    if (adoptCallCount == 1) {
      throw Exception('boom');
    }
    return super.adoptSuggestion(id);
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

Future<Quest> _seedSuggestedQuest(StorageService storage) async {
  final quest = Quest(
    id: 's1',
    title: '독서 10분',
    description: '',
    statRewards: {'intelligence': 10},
    status: QuestStatus.suggested,
    createdAt: DateTime(2026, 7, 1),
  );
  await storage.saveQuest(quest);
  return quest;
}

Future<void> _pumpHub(
  WidgetTester tester,
  StorageService storage,
  QuestsNotifier Function(Ref ref) createNotifier,
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
      const QuestCompletionResult(
        didComplete: true,
        levelUps: {},
        newAchievements: [],
      ),
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

  testWidgets('didComplete가 false면(다른 화면이 먼저 완료/삭제) 완료 스낵바나 다이얼로그를 띄우지 않는다', (
    tester,
  ) async {
    final storage = await createTestStorage();
    await _seedActiveQuest(storage);

    await _pumpHub(tester, storage, (ref) {
      return _ControlledQuestsNotifier(
        storage,
        ref,
        () async => const QuestCompletionResult(
          didComplete: false,
          levelUps: {},
          newAchievements: [],
        ),
      );
    });
    await tester.pump();

    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();

    expect(find.textContaining('완료!'), findsNothing);
    expect(find.text('🏆 업적 달성!'), findsNothing);
    expect(find.text('🎉 레벨업!'), findsNothing);
    expect(find.textContaining('실패'), findsNothing);
  });

  testWidgets('추천 퀘스트 채택을 리빌드 전에 두 번 눌러도 채택 요청은 한 번만 일어나고 버튼은 비활성화된다', (
    tester,
  ) async {
    final storage = await createTestStorage();
    await _seedSuggestedQuest(storage);

    late _ControlledAdoptQuestsNotifier notifier;
    final completer = Completer<void>();

    await _pumpHub(tester, storage, (ref) {
      notifier = _ControlledAdoptQuestsNotifier(
        storage,
        ref,
        () => completer.future,
      );
      return notifier;
    });
    await tester.pump();

    final adoptButton = find.byType(FilledButton);
    expect(adoptButton, findsOneWidget);
    expect(tester.widget<FilledButton>(adoptButton).onPressed, isNotNull);

    await tester.tap(adoptButton);
    await tester.pump();

    expect(notifier.adoptCallCount, 1);
    expect(tester.widget<FilledButton>(adoptButton).onPressed, isNull);

    await tester.tap(adoptButton);
    await tester.pump();
    expect(notifier.adoptCallCount, 1);

    completer.complete();
    await tester.pumpAndSettle();
    expect(notifier.adoptCallCount, 1);
  });

  testWidgets(
    '추천 퀘스트 채택이 실패하면 일반 오류 메시지와 재시도 버튼만 뜨고 추천 상태는 그대로 남으며, 재시도는 정확히 한 번 더 호출돼 강조 퀘스트로 전환된다',
    (tester) async {
      final storage = await createTestStorage();
      await _seedSuggestedQuest(storage);
      late _FlakyAdoptQuestsNotifier notifier;

      await _pumpHub(tester, storage, (ref) {
        notifier = _FlakyAdoptQuestsNotifier(
          ref.watch(storageServiceProvider),
          ref,
        );
        return notifier;
      });
      await tester.pump();

      await tester.tap(find.widgetWithText(FilledButton, '채택하고 시작'));
      await tester.pumpAndSettle();

      expect(notifier.adoptCallCount, 1);
      expect(find.text('독서 10분'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, '채택하고 시작'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '채택하고 시작'))
            .onPressed,
        isNotNull,
      );
      expect(find.text('퀘스트를 채택하지 못했어요. 다시 시도해주세요.'), findsOneWidget);
      expect(find.text('재시도'), findsOneWidget);
      expect(find.text('Exception'), findsNothing);
      expect(storage.getQuest('s1')!.status, QuestStatus.suggested);

      await tester.tap(find.text('재시도'));
      await tester.pumpAndSettle();

      // 재시도는 정확히 새 호출 한 번만 만들고(총 2회), 실제로 채택돼
      // 강조 퀘스트("다음 퀘스트")로 전환되며, 가드도 풀려 완료 버튼이
      // 다시 활성화된다.
      expect(notifier.adoptCallCount, 2);
      expect(storage.getQuest('s1')!.status, QuestStatus.active);
      expect(find.text('다음 퀘스트'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, '완료'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '완료'))
            .onPressed,
        isNotNull,
      );
    },
  );

  testWidgets('완료 실패 후 카드가 dispose된 뒤 재시도 콜백을 직접 호출해도 안전하다', (tester) async {
    final storage = await createTestStorage();
    await _seedActiveQuest(storage);
    late _ControlledQuestsNotifier notifier;

    await _pumpHub(tester, storage, (ref) {
      notifier = _ControlledQuestsNotifier(
        storage,
        ref,
        () => Future<QuestCompletionResult>.error(Exception('boom')),
      );
      return notifier;
    });
    await tester.pump();

    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();

    expect(notifier.completeCallCount, 1);
    final retryCallback = tester
        .widget<SnackBarAction>(find.byType(SnackBarAction))
        .onPressed;

    // 카드를 포함한 트리 전체를 치워 ActionHubCard의 State를 dispose한다
    // — 실제로는 스낵바를 띄운 화면을 벗어나는 라우트/탭 전환에 해당한다.
    await tester.pumpWidget(const SizedBox.shrink());

    // dispose 이후 캡처해둔 재시도 콜백을 직접 호출해도 setState-after-
    // dispose 등 프레임워크 예외 없이 조용히 끝나야 하고, provider가
    // 다시 호출되지도 않아야 한다.
    expect(() => retryCallback(), returnsNormally);
    await tester.pump();

    expect(notifier.completeCallCount, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('채택 실패 후 카드가 dispose된 뒤 재시도 콜백을 직접 호출해도 안전하다', (tester) async {
    final storage = await createTestStorage();
    await _seedSuggestedQuest(storage);
    late _ControlledAdoptQuestsNotifier notifier;

    await _pumpHub(tester, storage, (ref) {
      notifier = _ControlledAdoptQuestsNotifier(
        storage,
        ref,
        () => Future<void>.error(Exception('boom')),
      );
      return notifier;
    });
    await tester.pump();

    await tester.tap(find.widgetWithText(FilledButton, '채택하고 시작'));
    await tester.pumpAndSettle();

    expect(notifier.adoptCallCount, 1);
    final retryCallback = tester
        .widget<SnackBarAction>(find.byType(SnackBarAction))
        .onPressed;

    await tester.pumpWidget(const SizedBox.shrink());

    expect(() => retryCallback(), returnsNormally);
    await tester.pump();

    expect(notifier.adoptCallCount, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('완료 처리 중에는 접근성 레이블로 진행 상태가 안내된다', (tester) async {
    final storage = await createTestStorage();
    await _seedActiveQuest(storage);
    final semantics = tester.ensureSemantics();

    final completer = Completer<QuestCompletionResult>();
    await _pumpHub(tester, storage, (ref) {
      return _ControlledQuestsNotifier(storage, ref, () => completer.future);
    });
    await tester.pump();

    expect(find.bySemanticsLabel('완료 처리 중'), findsNothing);

    await tester.tap(find.byType(FilledButton));
    // QuestCompletionButton은 처리중 표시를 AnimatedSwitcher로 감싸므로, 그
    // 크로스페이드가 opacity 0인 첫 프레임(ticker 시작 기준 프레임)을 지나야
    // 새 child의 semantics가 트리에 온전히 포함된다. pendingActionIndicator
    // 내부 CircularProgressIndicator는 무한 반복 애니메이션이라
    // pumpAndSettle을 쓰면 끝나지 않으므로, 유한한 duration으로 직접
    // 두 프레임만 흘려보낸다.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.bySemanticsLabel('완료 처리 중'), findsOneWidget);

    completer.complete(
      const QuestCompletionResult(
        didComplete: true,
        levelUps: {},
        newAchievements: [],
      ),
    );
    await tester.pumpAndSettle();
    semantics.dispose();
  });

  testWidgets('채택 처리 중에는 접근성 레이블로 진행 상태가 안내된다', (tester) async {
    final storage = await createTestStorage();
    await _seedSuggestedQuest(storage);
    final semantics = tester.ensureSemantics();

    final completer = Completer<void>();
    await _pumpHub(tester, storage, (ref) {
      return _ControlledAdoptQuestsNotifier(
        storage,
        ref,
        () => completer.future,
      );
    });
    await tester.pump();

    expect(find.bySemanticsLabel('채택 처리 중'), findsNothing);

    await tester.tap(find.widgetWithText(FilledButton, '채택하고 시작'));
    await tester.pump();

    expect(find.bySemanticsLabel('채택 처리 중'), findsOneWidget);

    completer.complete();
    await tester.pumpAndSettle();
    semantics.dispose();
  });
}
