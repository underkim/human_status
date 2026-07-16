import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:human_status/models/quest.dart';
import 'package:human_status/providers/profile_provider.dart';
import 'package:human_status/providers/quest_provider.dart';
import 'package:human_status/screens/quests_screen.dart';
import 'package:human_status/widgets/quest_card.dart';

import 'helpers/test_app.dart';

Quest _quest(String id, String title, {QuestStatus status = QuestStatus.active, double xp = 30}) {
  return Quest(
    id: id,
    title: title,
    description: '',
    statRewards: {'health': xp},
    status: status,
    source: status == QuestStatus.suggested ? QuestSource.suggested : QuestSource.manual,
    createdAt: DateTime(2026, 7, 1),
  );
}

/// completeQuest/deleteQuest/adoptSuggestion/dismissSuggestion 호출을
/// [gate]가 풀릴 때까지 붙잡아두고, 호출 횟수를 세고, [shouldThrow]가
/// true면 실패를 재현하는 QuestsNotifier — goals_screen_test.dart의
/// `_GatedGoalsListNotifier`와 같은 패턴.
class _GatedQuestsListNotifier extends QuestsNotifier {
  _GatedQuestsListNotifier(super.storage, super.ref);

  int completeCalls = 0;
  int deleteCalls = 0;
  int adoptCalls = 0;
  int dismissCalls = 0;
  bool shouldThrow = false;
  Completer<void> gate = Completer<void>();

  @override
  Future<QuestCompletionResult> completeQuest(String id) async {
    completeCalls++;
    await gate.future;
    if (shouldThrow) throw StateError('simulated complete failure');
    return super.completeQuest(id);
  }

  @override
  Future<void> deleteQuest(String id) async {
    deleteCalls++;
    await gate.future;
    if (shouldThrow) throw StateError('simulated delete failure');
    await super.deleteQuest(id);
  }

  @override
  Future<void> adoptSuggestion(String id) async {
    adoptCalls++;
    await gate.future;
    if (shouldThrow) throw StateError('simulated adopt failure');
    await super.adoptSuggestion(id);
  }

  @override
  Future<void> dismissSuggestion(String id) async {
    dismissCalls++;
    await gate.future;
    if (shouldThrow) throw StateError('simulated dismiss failure');
    await super.dismissSuggestion(id);
  }
}

void main() {
  testWidgets('완료 버튼은 XP를 적립하고 스낵바·업적 다이얼로그를 띄운 뒤 완료 탭으로 옮긴다', (tester) async {
    final storage = await createTestStorage();
    await storage.saveQuest(_quest('q1', '물 마시기'));

    await pumpApp(tester, storage, const QuestsScreen());
    expect(find.text('진행중 (1)'), findsOneWidget);

    await tester.tap(find.text('완료'));
    await tester.pumpAndSettle();

    // 완료 피드백: 스낵바 + 첫 퀘스트 업적('첫 걸음') 다이얼로그.
    expect(find.text('"물 마시기" 완료!'), findsOneWidget);
    expect(find.text('🏆 업적 달성!'), findsOneWidget);
    expect(find.text('첫 걸음'), findsOneWidget);
    await tester.tap(find.text('확인'));
    await tester.pumpAndSettle();

    // XP가 실제 저장소까지 반영됐는지.
    expect(storage.getStat('health')!.currentXp, 30);
    expect(find.text('진행중 (0)'), findsOneWidget);
    expect(find.text('완료 (1)'), findsOneWidget);

    await tester.tap(find.text('완료 (1)'));
    await tester.pumpAndSettle();
    expect(find.text('물 마시기'), findsOneWidget);
  });

  testWidgets('레벨업에 필요한 XP를 채우면 레벨업 다이얼로그가 뜬다', (tester) async {
    final storage = await createTestStorage();
    await storage.saveQuest(_quest('q1', '운동 30분', xp: 120));

    await pumpApp(tester, storage, const QuestsScreen());
    await tester.tap(find.text('완료'));
    await tester.pumpAndSettle();

    expect(find.text('🎉 레벨업!'), findsOneWidget);
    expect(find.text('💪 건강 스텟이 Lv.2(으)로 올랐습니다!'), findsOneWidget);
    await tester.tap(find.text('확인'));
    await tester.pumpAndSettle();

    // 업적 다이얼로그가 이어서 뜬다.
    expect(find.text('🏆 업적 달성!'), findsOneWidget);
    await tester.tap(find.text('확인'));
    await tester.pumpAndSettle();

    final stat = storage.getStat('health')!;
    expect(stat.level, 2);
    expect(stat.currentXp, 20);
  });

  testWidgets('진행중 퀘스트 메뉴에서 삭제하면 확인 후 목록에서 사라진다', (tester) async {
    final storage = await createTestStorage();
    await storage.saveQuest(_quest('q1', '지울 퀘스트'));

    await pumpApp(tester, storage, const QuestsScreen());

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('삭제'));
    await tester.pumpAndSettle();

    // 확인 다이얼로그.
    expect(find.textContaining('삭제할까요'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '삭제'));
    await tester.pumpAndSettle();

    expect(storage.getQuests(), isEmpty);
    expect(find.text('진행중 (0)'), findsOneWidget);
  });

  testWidgets('진행중 퀘스트 메뉴의 수정은 편집 화면으로 이동한다', (tester) async {
    final storage = await createTestStorage();
    await storage.saveQuest(_quest('q1', '수정할 퀘스트'));

    await pumpApp(tester, storage, const QuestsScreen());

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('수정'));
    await tester.pumpAndSettle();

    expect(find.text('퀘스트 수정'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, '수정할 퀘스트'), findsOneWidget);
  });

  testWidgets('반복 퀘스트에는 매일 반복 배지가 보인다', (tester) async {
    final storage = await createTestStorage();
    final quest = _quest('r1', '아침 스트레칭');
    quest.isRecurring = true;
    await storage.saveQuest(quest);

    await pumpApp(tester, storage, const QuestsScreen());

    expect(find.text('🔁 매일 반복'), findsOneWidget);
  });

  testWidgets('추천 퀘스트는 채택하면 진행중으로, 무시하면 목록에서 사라진다', (tester) async {
    final storage = await createTestStorage();
    await storage.saveQuest(_quest('s1', '아침 산책', status: QuestStatus.suggested));
    await storage.saveQuest(_quest('s2', '독서 10분', status: QuestStatus.suggested));

    await pumpApp(tester, storage, const QuestsScreen());
    await tester.tap(find.text('추천 (2)'));
    await tester.pumpAndSettle();

    // '아침 산책' 카드의 채택 버튼을 눌러 진행중으로 옮긴다.
    await tester.tap(find.text('채택').first);
    await tester.pumpAndSettle();
    expect(find.text('진행중 (1)'), findsOneWidget);
    expect(find.text('추천 (1)'), findsOneWidget);

    await tester.tap(find.text('무시'));
    await tester.pumpAndSettle();
    expect(find.text('추천 (0)'), findsOneWidget);
    expect(storage.getQuests().length, 1);
    expect(storage.getQuests().single.status, QuestStatus.active);
  });

  testWidgets('완료 버튼을 리빌드 전에 두 번 눌러도 완료 처리는 한 번만 일어난다', (tester) async {
    final storage = await createTestStorage();
    await storage.saveQuest(_quest('q1', '완료할 퀘스트'));
    late _GatedQuestsListNotifier notifier;
    await pumpApp(
      tester,
      storage,
      const QuestsScreen(),
      overrides: [
        questsProvider.overrideWith((ref) {
          notifier = _GatedQuestsListNotifier(ref.watch(storageServiceProvider), ref);
          return notifier;
        }),
      ],
    );

    final button = tester.widget<FilledButton>(find.widgetWithText(FilledButton, '완료'));
    button.onPressed!();
    button.onPressed!();

    expect(notifier.completeCalls, 1);

    notifier.gate.complete();
    await tester.pumpAndSettle();

    expect(find.text('"완료할 퀘스트" 완료!'), findsOneWidget);
    while (find.text('확인').evaluate().isNotEmpty) {
      await tester.tap(find.text('확인').first);
      await tester.pumpAndSettle();
    }

    expect(notifier.completeCalls, 1);
    expect(storage.getQuest('q1')!.status, QuestStatus.completed);
  });

  testWidgets('완료가 실패하면 일반 오류 메시지만 보여주고 퀘스트는 진행중으로 남으며, 재시도는 성공한다', (tester) async {
    final storage = await createTestStorage();
    await storage.saveQuest(_quest('q1', '완료할 퀘스트'));
    late _GatedQuestsListNotifier notifier;
    await pumpApp(
      tester,
      storage,
      const QuestsScreen(),
      overrides: [
        questsProvider.overrideWith((ref) {
          notifier = _GatedQuestsListNotifier(ref.watch(storageServiceProvider), ref);
          notifier.shouldThrow = true;
          return notifier;
        }),
      ],
    );

    await tester.tap(find.text('완료'));
    notifier.gate.complete();
    await tester.pumpAndSettle();

    expect(find.text('퀘스트 완료 처리에 실패했어요. 잠시 후 다시 시도해주세요.'), findsOneWidget);
    expect(find.text('StateError'), findsNothing);
    expect(storage.getQuest('q1')!.status, QuestStatus.active);

    notifier.shouldThrow = false;
    notifier.gate = Completer<void>();
    await tester.tap(find.text('완료'));
    notifier.gate.complete();
    await tester.pumpAndSettle();
    while (find.text('확인').evaluate().isNotEmpty) {
      await tester.tap(find.text('확인').first);
      await tester.pumpAndSettle();
    }

    expect(notifier.completeCalls, 2);
    expect(storage.getQuest('q1')!.status, QuestStatus.completed);
  });

  testWidgets('삭제 확인창이 뜨기 전에 같은 퀘스트를 빠르게 두 번 눌러도 확인창은 하나만 뜨고 삭제는 한 번만 반영된다', (tester) async {
    final storage = await createTestStorage();
    await storage.saveQuest(_quest('q1', '지울 퀘스트'));
    late _GatedQuestsListNotifier notifier;
    await pumpApp(
      tester,
      storage,
      const QuestsScreen(),
      overrides: [
        questsProvider.overrideWith((ref) {
          notifier = _GatedQuestsListNotifier(ref.watch(storageServiceProvider), ref);
          return notifier;
        }),
      ],
    );

    // 확인창이 뜨기도 전에(동일 콜백을 두 번 직접 호출) — 두 번째 호출은
    // pending 가드에 막혀야 한다. goals_screen_test.dart의 같은 패턴.
    final card = tester.widget<QuestCard>(find.byType(QuestCard));
    card.onDelete!();
    card.onDelete!();
    await tester.pumpAndSettle();

    expect(find.textContaining('삭제할까요'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, '삭제'));
    await tester.pump();
    notifier.gate.complete();
    await tester.pumpAndSettle();

    expect(notifier.deleteCalls, 1);
    expect(storage.getQuests(), isEmpty);
  });

  testWidgets('삭제가 실패하면 일반 오류 메시지만 보여주고 목록은 그대로 남으며, 재시도는 성공한다', (tester) async {
    final storage = await createTestStorage();
    await storage.saveQuest(_quest('q1', '지울 퀘스트'));
    late _GatedQuestsListNotifier notifier;
    await pumpApp(
      tester,
      storage,
      const QuestsScreen(),
      overrides: [
        questsProvider.overrideWith((ref) {
          notifier = _GatedQuestsListNotifier(ref.watch(storageServiceProvider), ref);
          notifier.shouldThrow = true;
          return notifier;
        }),
      ],
    );

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('삭제'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '삭제'));
    await tester.pump();
    notifier.gate.complete();
    await tester.pumpAndSettle();

    expect(find.text('퀘스트를 삭제하지 못했어요. 잠시 후 다시 시도해주세요.'), findsOneWidget);
    expect(find.text('StateError'), findsNothing);
    expect(storage.getQuests(), hasLength(1));

    notifier.shouldThrow = false;
    notifier.gate = Completer<void>();
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('삭제'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '삭제'));
    await tester.pump();
    notifier.gate.complete();
    await tester.pumpAndSettle();

    expect(notifier.deleteCalls, 2);
    expect(storage.getQuests(), isEmpty);
  });

  testWidgets('추천 퀘스트의 채택/무시를 연타해도 각각 한 번만 반영되고, 실패는 일반 오류 후 재시도할 수 있다', (tester) async {
    final storage = await createTestStorage();
    await storage.saveQuest(_quest('s1', '추천 퀘스트', status: QuestStatus.suggested));
    late _GatedQuestsListNotifier notifier;
    await pumpApp(
      tester,
      storage,
      const QuestsScreen(),
      overrides: [
        questsProvider.overrideWith((ref) {
          notifier = _GatedQuestsListNotifier(ref.watch(storageServiceProvider), ref);
          return notifier;
        }),
      ],
    );

    await tester.tap(find.text('추천 (1)'));
    await tester.pumpAndSettle();

    final adoptButton = tester.widget<FilledButton>(find.widgetWithText(FilledButton, '채택'));
    adoptButton.onPressed!();
    adoptButton.onPressed!();
    expect(notifier.adoptCalls, 1);

    notifier.gate.complete();
    await tester.pumpAndSettle();
    expect(notifier.adoptCalls, 1);
    expect(storage.getQuest('s1')!.status, QuestStatus.active);
  });

  testWidgets('추천 퀘스트 채택이 실패하면 일반 오류 메시지만 보여주고 여전히 추천 상태로 남으며, 재시도는 성공한다', (tester) async {
    final storage = await createTestStorage();
    await storage.saveQuest(_quest('s1', '추천 퀘스트', status: QuestStatus.suggested));
    late _GatedQuestsListNotifier notifier;
    await pumpApp(
      tester,
      storage,
      const QuestsScreen(),
      overrides: [
        questsProvider.overrideWith((ref) {
          notifier = _GatedQuestsListNotifier(ref.watch(storageServiceProvider), ref);
          notifier.shouldThrow = true;
          return notifier;
        }),
      ],
    );

    await tester.tap(find.text('추천 (1)'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('채택'));
    notifier.gate.complete();
    await tester.pumpAndSettle();

    expect(find.text('퀘스트를 채택하지 못했어요. 잠시 후 다시 시도해주세요.'), findsOneWidget);
    expect(find.text('StateError'), findsNothing);
    expect(storage.getQuest('s1')!.status, QuestStatus.suggested);

    notifier.shouldThrow = false;
    notifier.gate = Completer<void>();
    await tester.tap(find.text('채택'));
    notifier.gate.complete();
    await tester.pumpAndSettle();

    expect(notifier.adoptCalls, 2);
    expect(storage.getQuest('s1')!.status, QuestStatus.active);
  });

  testWidgets('추천 퀘스트 무시가 실패하면 일반 오류 메시지만 보여주고 여전히 목록에 남으며, 재시도는 성공한다', (tester) async {
    final storage = await createTestStorage();
    await storage.saveQuest(_quest('s1', '추천 퀘스트', status: QuestStatus.suggested));
    late _GatedQuestsListNotifier notifier;
    await pumpApp(
      tester,
      storage,
      const QuestsScreen(),
      overrides: [
        questsProvider.overrideWith((ref) {
          notifier = _GatedQuestsListNotifier(ref.watch(storageServiceProvider), ref);
          notifier.shouldThrow = true;
          return notifier;
        }),
      ],
    );

    await tester.tap(find.text('추천 (1)'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('무시'));
    notifier.gate.complete();
    await tester.pumpAndSettle();

    expect(find.text('퀘스트를 무시하지 못했어요. 잠시 후 다시 시도해주세요.'), findsOneWidget);
    expect(storage.getQuests(), hasLength(1));

    notifier.shouldThrow = false;
    notifier.gate = Completer<void>();
    await tester.tap(find.text('무시'));
    notifier.gate.complete();
    await tester.pumpAndSettle();

    expect(notifier.dismissCalls, 2);
    expect(storage.getQuests(), isEmpty);
  });
}
