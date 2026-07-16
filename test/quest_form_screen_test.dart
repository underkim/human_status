import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:human_status/models/quest.dart';
import 'package:human_status/providers/profile_provider.dart';
import 'package:human_status/providers/quest_provider.dart';
import 'package:human_status/screens/quest_form_screen.dart';

import 'helpers/test_app.dart';

/// 제출 중엔 계속 애니메이션하는 CircularProgressIndicator가 화면에 남아
/// 있어 pumpAndSettle이 절대 멈추지 않는다 — 대신 고정된 프레임 수만큼
/// 수동으로 진행시킨다. goal_form_screen_test.dart의 `_pumpSubmit`과 같은
/// 패턴.
Future<void> _pumpSubmit(WidgetTester tester, {int iterations = 10}) async {
  for (var i = 0; i < iterations; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

/// addQuest/updateQuest 호출을 [gate]가 풀릴 때까지 붙잡아두고, 호출
/// 횟수를 세고, [shouldThrow]가 true면 실패를 재현하는 QuestsNotifier —
/// goal_form_screen_test.dart의 `_GatedGoalsNotifier`와 같은 패턴.
class _GatedQuestsNotifier extends QuestsNotifier {
  _GatedQuestsNotifier(super.storage, super.ref);

  int addCalls = 0;
  int updateCalls = 0;
  bool shouldThrow = false;
  Completer<void> gate = Completer<void>();

  @override
  Future<void> addQuest(Quest quest) async {
    addCalls++;
    await gate.future;
    if (shouldThrow) throw StateError('simulated create failure');
    await super.addQuest(quest);
  }

  @override
  Future<void> updateQuest(Quest proposed) async {
    updateCalls++;
    await gate.future;
    if (shouldThrow) throw StateError('simulated update failure');
    await super.updateQuest(proposed);
  }
}

void main() {
  testWidgets('제목 없이 저장하면 검증 오류가 뜨고 퀘스트가 만들어지지 않는다', (tester) async {
    setScreenSize(tester, const Size(600, 1200));
    final storage = await createTestStorage();
    await pumpApp(tester, storage, const QuestFormScreen());

    await tester.tap(find.text('추가하기'));
    await tester.pumpAndSettle();

    expect(find.text('제목을 입력해주세요'), findsOneWidget);
    expect(storage.getQuests(), isEmpty);
  });

  testWidgets('난이도에 맞는 XP로 활성 퀘스트가 저장된다', (tester) async {
    setScreenSize(tester, const Size(600, 1200));
    final storage = await createTestStorage();
    await pumpApp(tester, storage, const QuestFormScreen());

    await tester.enterText(find.widgetWithText(TextFormField, '제목'), '아침 러닝');
    // 난이도 '보통'(+30XP) 선택.
    await tester.tap(find.text('쉬움 (+15XP)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('보통 (+30XP)').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('추가하기'));
    await tester.pumpAndSettle();

    final quests = storage.getQuests();
    expect(quests.length, 1);
    final quest = quests.single;
    expect(quest.title, '아침 러닝');
    expect(quest.status, QuestStatus.active);
    expect(quest.difficulty, QuestDifficulty.medium);
    // 기본 연결 스텟은 첫 번째(health).
    expect(quest.statRewards, {'health': 30});
  });

  testWidgets('매일 반복 스위치를 켜면 반복 퀘스트로 저장된다', (tester) async {
    setScreenSize(tester, const Size(600, 1200));
    final storage = await createTestStorage();
    await pumpApp(tester, storage, const QuestFormScreen());

    await tester.enterText(find.widgetWithText(TextFormField, '제목'), '물 2L 마시기');
    await tester.tap(find.text('매일 반복'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('추가하기'));
    await tester.pumpAndSettle();

    expect(storage.getQuests().single.isRecurring, isTrue);
  });

  testWidgets('편집 모드는 기존 값을 채우고 저장 시 같은 퀘스트를 갱신한다', (tester) async {
    setScreenSize(tester, const Size(600, 1200));
    final storage = await createTestStorage();
    final existing = Quest(
      id: 'q1',
      title: '옛 제목',
      description: '옛 설명',
      statRewards: {'health': 30},
      difficulty: QuestDifficulty.medium,
      status: QuestStatus.active,
      createdAt: DateTime(2026, 7, 1),
      goalId: 'g1',
    );
    await storage.saveQuest(existing);

    await pumpApp(tester, storage, QuestFormScreen(existing: existing));

    // 헤더·버튼이 편집 모드로 바뀌고 값이 미리 채워진다.
    expect(find.text('퀘스트 수정'), findsOneWidget);
    expect(find.text('저장하기'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, '옛 제목'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, '옛 설명'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextFormField, '옛 제목'), '새 제목');
    await tester.tap(find.text('저장하기'));
    await tester.pumpAndSettle();

    // 새 퀘스트가 생기지 않고 같은 id가 갱신되며, 상태·생성시각·목표연결은 유지.
    expect(storage.getQuests().length, 1);
    final updated = storage.getQuests().single;
    expect(updated.id, 'q1');
    expect(updated.title, '새 제목');
    expect(updated.status, QuestStatus.active);
    expect(updated.createdAt, DateTime(2026, 7, 1));
    expect(updated.goalId, 'g1');
  });

  testWidgets('생성 버튼을 리빌드 전에 두 번 눌러도 퀘스트는 한 번만 생성된다', (tester) async {
    setScreenSize(tester, const Size(600, 1200));
    final storage = await createTestStorage();
    late _GatedQuestsNotifier notifier;
    await pumpApp(
      tester,
      storage,
      const QuestFormScreen(),
      overrides: [
        questsProvider.overrideWith((ref) {
          notifier = _GatedQuestsNotifier(ref.watch(storageServiceProvider), ref);
          return notifier;
        }),
      ],
    );

    await tester.enterText(find.widgetWithText(TextFormField, '제목'), '중복 탭 퀘스트');

    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '추가하기'),
    );
    // 리빌드(pump) 이전에 동일 콜백을 두 번 직접 호출 — onPressed: null로
    // 바뀌는 건 다음 프레임부터라, 실제 연타는 이 두 호출로만 재현된다.
    button.onPressed!();
    button.onPressed!();

    expect(notifier.addCalls, 1);

    notifier.gate.complete();
    await _pumpSubmit(tester);

    expect(notifier.addCalls, 1);
    expect(storage.getQuests(), hasLength(1));
  });

  testWidgets('생성이 실패하면 입력값이 유지된 채 화면이 열려 있고 일반 오류 메시지만 보여준다', (tester) async {
    setScreenSize(tester, const Size(600, 1200));
    final storage = await createTestStorage();
    late _GatedQuestsNotifier notifier;
    await pumpApp(
      tester,
      storage,
      const QuestFormScreen(),
      overrides: [
        questsProvider.overrideWith((ref) {
          notifier = _GatedQuestsNotifier(ref.watch(storageServiceProvider), ref);
          notifier.shouldThrow = true;
          return notifier;
        }),
      ],
    );

    await tester.enterText(find.widgetWithText(TextFormField, '제목'), '실패할 퀘스트');
    await tester.tap(find.text('추가하기'));
    notifier.gate.complete();
    await _pumpSubmit(tester);

    // 원인은 노출되지 않고, 화면은 그대로 열려 있으며, 입력값도 그대로 남는다.
    expect(find.text('퀘스트를 저장하지 못했어요. 잠시 후 다시 시도해주세요.'), findsOneWidget);
    expect(find.text('StateError'), findsNothing);
    expect(find.text('퀘스트 추가'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, '실패할 퀘스트'), findsOneWidget);
    expect(storage.getQuests(), isEmpty);

    // 실패 이후 버튼은 다시 활성화되어 재시도할 수 있다.
    expect(
      tester.widget<FilledButton>(find.widgetWithText(FilledButton, '추가하기')).onPressed,
      isNotNull,
    );
  });

  testWidgets('편집 저장 버튼을 리빌드 전에 두 번 눌러도 수정은 한 번만 반영된다', (tester) async {
    setScreenSize(tester, const Size(600, 1200));
    final storage = await createTestStorage();
    final existing = Quest(
      id: 'q1',
      title: '옛 제목',
      description: '',
      statRewards: {'health': 15},
      createdAt: DateTime(2026, 7, 1),
    );
    await storage.saveQuest(existing);
    late _GatedQuestsNotifier notifier;
    await pumpApp(
      tester,
      storage,
      QuestFormScreen(existing: existing),
      overrides: [
        questsProvider.overrideWith((ref) {
          notifier = _GatedQuestsNotifier(ref.watch(storageServiceProvider), ref);
          return notifier;
        }),
      ],
    );

    await tester.enterText(find.widgetWithText(TextFormField, '옛 제목'), '새 제목');

    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '저장하기'),
    );
    button.onPressed!();
    button.onPressed!();

    expect(notifier.updateCalls, 1);

    notifier.gate.complete();
    await _pumpSubmit(tester);

    expect(notifier.updateCalls, 1);
    expect(storage.getQuests().single.title, '새 제목');
  });

  testWidgets('편집 저장이 실패하면 existing과 storage가 그대로고 화면이 열린 채 일반 오류만 보여준다', (tester) async {
    setScreenSize(tester, const Size(600, 1200));
    final storage = await createTestStorage();
    final existing = Quest(
      id: 'q1',
      title: '옛 제목',
      description: '',
      statRewards: {'health': 15},
      createdAt: DateTime(2026, 7, 1),
    );
    await storage.saveQuest(existing);
    late _GatedQuestsNotifier notifier;
    await pumpApp(
      tester,
      storage,
      QuestFormScreen(existing: existing),
      overrides: [
        questsProvider.overrideWith((ref) {
          notifier = _GatedQuestsNotifier(ref.watch(storageServiceProvider), ref);
          notifier.shouldThrow = true;
          return notifier;
        }),
      ],
    );

    await tester.enterText(find.widgetWithText(TextFormField, '옛 제목'), '바뀔 뻔한 제목');
    await tester.tap(find.text('저장하기'));
    notifier.gate.complete();
    await _pumpSubmit(tester);

    expect(find.text('퀘스트를 저장하지 못했어요. 잠시 후 다시 시도해주세요.'), findsOneWidget);
    expect(find.text('퀘스트 수정'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, '바뀔 뻔한 제목'), findsOneWidget);
    // 라이브 객체도 storage도 실패 시 절대 바뀌지 않는다.
    expect(existing.title, '옛 제목');
    expect(storage.getQuest('q1')!.title, '옛 제목');
  });

  testWidgets('제출 도중 화면을 나가도(dispose) 완료 후 콜백이 안전하게 무시되고 저장은 그대로 반영된다', (tester) async {
    setScreenSize(tester, const Size(600, 1200));
    final storage = await createTestStorage();
    late _GatedQuestsNotifier notifier;
    // ProviderScope/storage는 살아있는 채로 폼 위젯만 dispose되는 상황을
    // 재현하기 위해, Navigator로 폼을 push한 뒤 저장이 끝나기 전에 pop한다.
    await pumpApp(
      tester,
      storage,
      Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: FilledButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const QuestFormScreen()),
              ),
              child: const Text('열기'),
            ),
          ),
        ),
      ),
      overrides: [
        questsProvider.overrideWith((ref) {
          notifier = _GatedQuestsNotifier(ref.watch(storageServiceProvider), ref);
          return notifier;
        }),
      ],
    );

    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextFormField, '제목'), '나갈 퀘스트');
    await tester.tap(find.text('추가하기'));
    await tester.pump();

    // 저장이 아직 완료되지 않은 상태에서(게이트가 안 풀린 채로) 뒤로 가기 —
    // 폼 State는 dispose되지만 ProviderScope/storage는 계속 살아있다.
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.pop();
    await tester.pumpAndSettle();

    notifier.gate.complete();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 200));

    // setState-after-dispose 에러 없이(테스트가 실패하지 않고) 저장은
    // storage에 정상적으로 반영된다.
    expect(storage.getQuests(), hasLength(1));
    expect(storage.getQuests().single.title, '나갈 퀘스트');
  });
}
