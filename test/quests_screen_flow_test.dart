import 'package:flutter_test/flutter_test.dart';
import 'package:human_status/models/quest.dart';
import 'package:human_status/screens/quests_screen.dart';

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
}
