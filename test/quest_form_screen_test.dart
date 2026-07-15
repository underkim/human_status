import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:human_status/models/quest.dart';
import 'package:human_status/screens/quest_form_screen.dart';

import 'helpers/test_app.dart';

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
}
