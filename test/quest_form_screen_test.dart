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
}
