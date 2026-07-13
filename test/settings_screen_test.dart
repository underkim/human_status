import 'package:flutter_test/flutter_test.dart';
import 'package:human_status/models/quest.dart';
import 'package:human_status/screens/settings_screen.dart';
import 'package:human_status/services/storage_service.dart';

import 'helpers/test_app.dart';

void main() {
  testWidgets('데이터 초기화는 확인 후 스텟을 기본값으로 되돌리고 API 키는 보존한다', (tester) async {
    final storage = await createTestStorage();
    final profile = storage.getProfile();
    profile.claudeApiKey = 'sk-ant-test';
    await storage.saveProfile(profile);
    await storage.saveQuest(Quest(
      id: 'q1',
      title: '지울 퀘스트',
      description: '',
      statRewards: {'health': 10},
      createdAt: DateTime(2026, 7, 1),
    ));
    final health = storage.getStat('health')!;
    health.level = 3;
    await storage.saveStat(health);

    await pumpApp(tester, storage, const SettingsScreen());
    expect(find.text('설정됨 — AI 추천 사용 중'), findsOneWidget);

    await tester.tap(find.text('데이터 초기화'));
    await tester.pumpAndSettle();

    // 확인을 거치기 전에는 아무것도 지워지지 않는다.
    expect(find.text('취소'), findsOneWidget);
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();
    expect(storage.getQuests(), isNotEmpty);

    await tester.tap(find.text('데이터 초기화'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('초기화'));
    await tester.pumpAndSettle();

    expect(find.text('초기화되었습니다.'), findsOneWidget);
    expect(storage.getQuests(), isEmpty);
    expect(storage.getStats().length, StorageService.defaultStats.length);
    expect(storage.getStat('health')!.level, 1);
    expect(storage.getProfile().claudeApiKey, 'sk-ant-test');
  });
}
