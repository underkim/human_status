import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:human_status/main.dart';
import 'package:human_status/models/quest.dart';
import 'package:human_status/providers/profile_provider.dart';
import 'package:human_status/screens/home_shell.dart';
import 'package:human_status/screens/onboarding_screen.dart';
import 'package:human_status/screens/settings_screen.dart';
import 'package:human_status/services/storage_service.dart';

import 'helpers/fake_secret_store.dart';
import 'helpers/test_app.dart';

void main() {
  testWidgets('데이터 초기화는 확인 후 스텟을 기본값으로 되돌리고 API 키/알림·온보딩 상태를 알맞게 처리한다', (
    tester,
  ) async {
    final storage = await createTestStorage();
    await storage.saveClaudeApiKey('sk-ant-test');
    final profile = storage.getProfile();
    profile.lastQuestRefresh = DateTime(2026, 7, 14, 9);
    profile.reminderMinutesSinceMidnight = 540;
    profile.weeklyReportReminderEnabled = true;
    profile.onboardingCompleted = true;
    profile.preferredStatId = 'health';
    await storage.saveProfile(profile);
    await storage.saveQuest(
      Quest(
        id: 'q1',
        title: '지울 퀘스트',
        description: '',
        statRewards: {'health': 10},
        createdAt: DateTime(2026, 7, 1),
      ),
    );
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
    // 기기 로컬 설정(API 키·알림)은 보존된다.
    expect(storage.claudeApiKey, 'sk-ant-test');
    expect(storage.getProfile().reminderMinutesSinceMidnight, 540);
    expect(storage.getProfile().weeklyReportReminderEnabled, isTrue);
    // 추천이 함께 사라졌으므로 24시간 간격을 기다리지 않고 재생성돼야 한다.
    expect(storage.getProfile().lastQuestRefresh, isNull);
    // 게임 데이터를 새로 시작하는 의미이므로 온보딩도 다시 볼 수 있어야 한다.
    expect(storage.getProfile().onboardingCompleted, isFalse);
    expect(storage.getProfile().preferredStatId, isNull);
  });

  testWidgets('데이터 초기화 후에는 재시작 없이도 HumanStatusApp이 온보딩으로 전환된다', (tester) async {
    setScreenSize(tester, const Size(400, 800));
    final storage = await createTestStorage();
    final profile = storage.getProfile();
    profile.onboardingCompleted = true;
    await storage.saveProfile(profile);
    await storage.saveQuest(
      Quest(
        id: 'q1',
        title: '지울 퀘스트',
        description: '',
        statRewards: {'health': 10},
        createdAt: DateTime(2026, 7, 1),
      ),
    );

    final container = ProviderContainer(
      overrides: [storageServiceProvider.overrideWithValue(storage)],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const HumanStatusApp(),
      ),
    );
    await tester.pump();
    expect(find.byType(HomeShell), findsOneWidget);

    // 홈 → 더보기 → 설정 → 데이터 초기화, 실제 UI 경로를 그대로 밟는다.
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.byIcon(Icons.more_horiz_outlined),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('설정'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('데이터 초기화'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('초기화'));
    await tester.pumpAndSettle();

    // 별도의 재시작/재생성 없이, 같은 실행 중에 온보딩 화면으로 전환된다.
    // (설정 화면까지 push된 상태에서 전환되므로, 이전 push 스택이 남지
    // 않고 깨끗하게 교체되는지도 함께 검증한다.)
    expect(find.byType(OnboardingScreen), findsOneWidget);
    expect(find.byType(HomeShell), findsNothing);
    expect(find.byType(SettingsScreen), findsNothing);
  });

  group('Claude API 키 편집', () {
    testWidgets('키를 입력하고 저장하면 보안 저장소에 저장되고 상태 텍스트가 바뀐다', (tester) async {
      final storage = await createTestStorage();
      await pumpApp(tester, storage, const SettingsScreen());
      expect(find.text('설정 안 됨 — 로컬 규칙 기반 추천 사용 중'), findsOneWidget);

      await tester.tap(find.text('Claude API 키'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'sk-ant-new-key');
      await tester.tap(find.text('저장'));
      await tester.pumpAndSettle();

      expect(find.text('API 키가 저장되었습니다.'), findsOneWidget);
      expect(find.text('설정됨 — AI 추천 사용 중'), findsOneWidget);
      expect(storage.claudeApiKey, 'sk-ant-new-key');
    });

    testWidgets('키 삭제를 누르면 보안 저장소에서 삭제되고 상태 텍스트가 바뀐다', (tester) async {
      final storage = await createTestStorage();
      await storage.saveClaudeApiKey('sk-ant-existing');
      await pumpApp(tester, storage, const SettingsScreen());
      expect(find.text('설정됨 — AI 추천 사용 중'), findsOneWidget);

      await tester.tap(find.text('Claude API 키'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('키 삭제'));
      await tester.pumpAndSettle();

      expect(find.text('API 키가 삭제되었습니다.'), findsOneWidget);
      expect(find.text('설정 안 됨 — 로컬 규칙 기반 추천 사용 중'), findsOneWidget);
      expect(storage.claudeApiKey, isNull);
    });

    testWidgets('보안 저장소 저장 실패 시 일반화된 오류만 보여주고 이전 상태를 유지한다', (tester) async {
      final secretStore = FakeSecretStore()
        ..values['claude_api_key'] = 'sk-ant-existing';
      final storage = StorageService(inMemory: true, secretStore: secretStore);
      await storage.init();
      addTearDown(Hive.close);

      await pumpApp(tester, storage, const SettingsScreen());
      expect(find.text('설정됨 — AI 추천 사용 중'), findsOneWidget);

      secretStore.failWrite = true;
      await tester.tap(find.text('Claude API 키'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'sk-ant-should-not-save');
      await tester.tap(find.text('저장'));
      await tester.pumpAndSettle();

      expect(find.text('API 키를 저장하지 못했습니다. 잠시 후 다시 시도해주세요.'), findsOneWidget);
      // 예외 문자열이나 키 원문이 그대로 노출되지 않는다.
      expect(find.textContaining('simulated write failure'), findsNothing);
      expect(find.textContaining('sk-ant-should-not-save'), findsNothing);
      // 이전 상태(설정됨)가 그대로 유지된다.
      expect(find.text('설정됨 — AI 추천 사용 중'), findsOneWidget);
      expect(storage.claudeApiKey, 'sk-ant-existing');
    });

    testWidgets('보안 저장소 삭제 실패 시 일반화된 오류만 보여주고 이전 상태를 유지한다', (tester) async {
      final secretStore = FakeSecretStore()
        ..values['claude_api_key'] = 'sk-ant-existing';
      final storage = StorageService(inMemory: true, secretStore: secretStore);
      await storage.init();
      addTearDown(Hive.close);

      await pumpApp(tester, storage, const SettingsScreen());

      secretStore.failDelete = true;
      await tester.tap(find.text('Claude API 키'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('키 삭제'));
      await tester.pumpAndSettle();

      expect(find.text('API 키를 저장하지 못했습니다. 잠시 후 다시 시도해주세요.'), findsOneWidget);
      expect(find.text('설정됨 — AI 추천 사용 중'), findsOneWidget);
      expect(storage.claudeApiKey, 'sk-ant-existing');
    });
  });
}
