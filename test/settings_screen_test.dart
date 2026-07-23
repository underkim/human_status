import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:human_status/main.dart';
import 'package:human_status/models/financial_plan.dart';
import 'package:human_status/models/quest.dart';
import 'package:human_status/models/stat.dart';
import 'package:human_status/providers/backup_provider.dart';
import 'package:human_status/providers/financial_planning_provider.dart';
import 'package:human_status/providers/observability_provider.dart';
import 'package:human_status/providers/profile_provider.dart';
import 'package:human_status/providers/quest_provider.dart';
import 'package:human_status/screens/home_shell.dart';
import 'package:human_status/screens/onboarding_screen.dart';
import 'package:human_status/screens/settings_screen.dart';
import 'package:human_status/services/backup_service.dart';
import 'package:human_status/services/storage_service.dart';
import 'package:human_status/theme/app_theme.dart';

import 'helpers/fake_secret_store.dart';
import 'helpers/test_app.dart';

void main() {
  testWidgets('데이터 초기화는 확인 후 스텟을 기본값으로 되돌리고 API 키/알림·온보딩 상태를 알맞게 처리한다', (
    tester,
  ) async {
    // 크래시 리포팅 토글이 추가되며 목록이 길어져, '데이터 초기화'가 기본 뷰포트의
    // 가상화(virtualization) 캐시 범위 밖으로 밀려난다 — 화면을 세로로
    // 넉넉하게 잡아 처음부터 전부 mount되도록 한다.
    setScreenSize(tester, const Size(800, 1200));
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

    await tester.ensureVisible(find.text('데이터 초기화'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('데이터 초기화'));
    await tester.pumpAndSettle();

    // 확인을 거치기 전에는 아무것도 지워지지 않는다.
    expect(find.text('취소'), findsOneWidget);
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();
    expect(storage.getQuests(), isNotEmpty);

    await tester.ensureVisible(find.text('데이터 초기화'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('데이터 초기화'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('초기화'));
    await tester.pumpAndSettle();

    expect(find.text('초기화됐어요.'), findsOneWidget);
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

  testWidgets('데이터 초기화 후에도 강제 온보딩 없이 현재 설정 흐름을 유지한다', (tester) async {
    // 너비는 좁은 레이아웃(하단 내비게이션) 검증을 위해 그대로 두고, 높이만
    // 늘려 크래시 리포팅 토글 추가로 길어진 목록이 처음부터 전부
    // mount되도록 한다 (그렇지 않으면 '데이터 초기화'가 가상화 캐시 범위
    // 밖으로 밀려나 ensureVisible이 찾지 못한다).
    setScreenSize(tester, const Size(400, 1400));
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
      overrides: [
        storageServiceProvider.overrideWithValue(storage),
        crashReporterProvider.overrideWithValue(FakeCrashReporter()),
      ],
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
    await tester.ensureVisible(find.text('데이터 초기화'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('데이터 초기화'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('초기화'));
    await tester.pumpAndSettle();

    // 데이터 초기화 뒤에도 사용자를 강제로 온보딩에 가두지 않는다.
    expect(find.byType(OnboardingScreen), findsNothing);
    expect(find.byType(SettingsScreen), findsOneWidget);
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

      expect(find.text('API 키를 저장했어요.'), findsOneWidget);
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

      expect(find.text('API 키를 삭제했어요.'), findsOneWidget);
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

      expect(find.text('API 키를 저장하지 못했어요. 잠시 후 다시 시도해주세요.'), findsOneWidget);
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

      expect(find.text('API 키를 저장하지 못했어요. 잠시 후 다시 시도해주세요.'), findsOneWidget);
      expect(find.text('설정됨 — AI 추천 사용 중'), findsOneWidget);
      expect(storage.claudeApiKey, 'sk-ant-existing');
    });
  });

  group('데이터 초기화와 레거시 전용 API 키 (Codex review 회귀)', () {
    testWidgets('보안 저장소가 계속 사용 불가능해 레거시 필드가 유일한 복사본인 상태에서도, '
        '데이터 초기화 UI를 실제로 밟은 뒤 유효 키와 레거시 복사본이 모두 살아남는다', (tester) async {
      setScreenSize(tester, const Size(800, 1200));
      final secretStore = FakeSecretStore()..failWrite = true;
      final storage = StorageService(inMemory: true, secretStore: secretStore);
      await storage.init();
      final profile = storage.getProfile();
      profile.claudeApiKey = 'sk-legacy-only-survives-reset';
      await storage.saveProfile(profile);
      // 마이그레이션이 실패한 채로 유지되도록 재초기화한다 — 이제
      // storage.claudeApiKey는 레거시 필드에서만 온 값이다.
      await storage.init();
      addTearDown(Hive.close);
      expect(storage.claudeApiKey, 'sk-legacy-only-survives-reset');

      await storage.saveQuest(
        Quest(
          id: 'q1',
          title: '지울 퀘스트',
          description: '',
          statRewards: {'health': 10},
          createdAt: DateTime(2026, 7, 1),
        ),
      );

      await pumpApp(tester, storage, const SettingsScreen());
      expect(find.text('설정됨 — AI 추천 사용 중'), findsOneWidget);

      await tester.ensureVisible(find.text('데이터 초기화'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('데이터 초기화'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('초기화'));
      await tester.pumpAndSettle();

      expect(find.text('초기화됐어요.'), findsOneWidget);
      expect(storage.getQuests(), isEmpty);
      // 유효 키(캐시)와 레거시 유일 복사본이 모두 살아남는다.
      expect(storage.claudeApiKey, 'sk-legacy-only-survives-reset');
      expect(
        storage.getProfile().claudeApiKey,
        'sk-legacy-only-survives-reset',
      );

      // 재초기화 후에도 여전히 살아남아야 한다(마이그레이션은 여전히
      // 실패하는 상태이므로 레거시 필드가 유지된다).
      await storage.init();
      expect(storage.claudeApiKey, 'sk-legacy-only-survives-reset');
    });
  });

  group('안전한 백업 가져오기 (미리보기·확인·중복 탭 방지)', () {
    // 자동 백업 섹션이 추가되며 목록이 길어져, '백업 가져오기'/'백업 내보내기' 등이
    // 기본 뷰포트의 가상화 캐시 범위 밖으로 밀려난다 — 이 그룹의 모든 테스트에서
    // 화면을 세로로 넉넉하게 잡아 처음부터 전부 mount되도록 한다.
    testWidgets('유효한 백업은 미리보기를 보여준 뒤 확인해야만 실제로 교체된다', (tester) async {
      setScreenSize(tester, const Size(800, 1200));
      final storage = await createTestStorage();
      await storage.saveQuest(
        Quest(
          id: 'q0',
          title: '원래 퀘스트',
          description: '',
          statRewards: {'health': 10},
          createdAt: DateTime(2026, 7, 1),
        ),
      );
      final incoming = _sampleBackupJson(questTitles: ['가져온 퀘스트']);

      await pumpApp(
        tester,
        storage,
        SettingsScreen(debugPickBackupSource: (_) async => incoming),
      );

      await tester.tap(find.text('백업 가져오기'));
      await tester.pumpAndSettle();

      // 미리보기 요약이 뜨고, 이 시점에는 아직 교체되지 않았다.
      expect(find.textContaining('퀘스트 1개'), findsOneWidget);
      expect(find.textContaining('스텟 1개'), findsOneWidget);
      expect(storage.getQuests().single.title, '원래 퀘스트');

      await tester.tap(find.text('취소'));
      await tester.pumpAndSettle();
      expect(storage.getQuests().single.title, '원래 퀘스트');

      // 다시 열어 이번엔 확인까지 진행한다.
      await tester.tap(find.text('백업 가져오기'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('교체'));
      await tester.pumpAndSettle();

      expect(find.text('가져오기가 완료됐어요.'), findsOneWidget);
      expect(storage.getQuests().single.title, '가져온 퀘스트');
    });

    testWidgets('유효하지 않은(malformed) 백업은 확인 없이 일반화된 오류만 보여준다', (tester) async {
      setScreenSize(tester, const Size(800, 1200));
      final storage = await createTestStorage();
      await storage.saveQuest(
        Quest(
          id: 'q0',
          title: '원래 퀘스트',
          description: '',
          statRewards: {'health': 10},
          createdAt: DateTime(2026, 7, 1),
        ),
      );

      await pumpApp(
        tester,
        storage,
        SettingsScreen(debugPickBackupSource: (_) async => '{"stats": "oops"}'),
      );

      await tester.tap(find.text('백업 가져오기'));
      await tester.pumpAndSettle();

      expect(find.text('백업 파일 형식을 확인할 수 없어요. 다른 파일을 선택해주세요.'), findsOneWidget);
      expect(find.text('교체'), findsNothing);
      expect(storage.getQuests().single.title, '원래 퀘스트');
    });

    testWidgets('지원하지 않는 schemaVersion 백업도 확인 없이 오류만 보여준다', (tester) async {
      setScreenSize(tester, const Size(800, 1200));
      final storage = await createTestStorage();
      final future = jsonEncode({
        'schemaVersion': 99,
        'stats': <Map<String, dynamic>>[],
        'quests': <Map<String, dynamic>>[],
      });

      await pumpApp(
        tester,
        storage,
        SettingsScreen(debugPickBackupSource: (_) async => future),
      );

      await tester.tap(find.text('백업 가져오기'));
      await tester.pumpAndSettle();

      expect(find.text('백업 파일 형식을 확인할 수 없어요. 다른 파일을 선택해주세요.'), findsOneWidget);
      expect(find.text('교체'), findsNothing);
    });

    testWidgets('빈 백업 내용은 확인 없이 오류만 보여준다', (tester) async {
      setScreenSize(tester, const Size(800, 1200));
      final storage = await createTestStorage();

      await pumpApp(
        tester,
        storage,
        SettingsScreen(debugPickBackupSource: (_) async => '   '),
      );

      await tester.tap(find.text('백업 가져오기'));
      await tester.pumpAndSettle();

      expect(find.text('백업 파일 형식을 확인할 수 없어요. 다른 파일을 선택해주세요.'), findsOneWidget);
      expect(find.text('교체'), findsNothing);
    });

    testWidgets('가져오기 버튼을 빠르게 두 번 눌러도 소스 선택이 한 번만 실행된다', (tester) async {
      setScreenSize(tester, const Size(800, 1200));
      final storage = await createTestStorage();
      var pickCalls = 0;
      final completer = Completer<String?>();

      await pumpApp(
        tester,
        storage,
        SettingsScreen(
          debugPickBackupSource: (_) {
            pickCalls++;
            return completer.future;
          },
        ),
      );

      await tester.tap(find.text('백업 가져오기'));
      await tester.pump();
      // 첫 번째 호출이 아직 완료되지 않은 상태에서 빠르게 다시 탭한다.
      await tester.tap(find.text('백업 가져오기'));
      await tester.pump();

      expect(pickCalls, 1);

      completer.complete(null);
      await tester.pumpAndSettle();
    });

    testWidgets('내보내기 버튼을 빠르게 두 번 눌러도 저장이 한 번만 실행된다', (tester) async {
      setScreenSize(tester, const Size(800, 1200));
      final storage = await createTestStorage();
      var saveCalls = 0;
      final completer = Completer<void>();

      await pumpApp(
        tester,
        storage,
        SettingsScreen(
          debugSaveBackupFile: (fileName, jsonStr) {
            saveCalls++;
            return completer.future;
          },
        ),
      );

      await tester.tap(find.text('백업 내보내기'));
      await tester.pump();
      await tester.tap(find.text('백업 내보내기'));
      await tester.pump();

      expect(saveCalls, 1);

      completer.complete();
      await tester.pumpAndSettle();
      expect(find.text('백업 파일을 저장했어요.'), findsOneWidget);
    });

    testWidgets(
      'apply 실패 후 rollback이 성공하면 되돌림 메시지를 보여주고 provider가 storage와 동기화된다',
      (tester) async {
        setScreenSize(tester, const Size(800, 1200));
        final storage = await createTestStorage();
        await storage.saveQuest(
          Quest(
            id: 'q0',
            title: '원래 퀘스트',
            description: '',
            statRewards: {'health': 10},
            createdAt: DateTime(2026, 7, 1),
          ),
        );

        final backupService = BackupService(storage: storage);
        backupService.debugApplyFaultInjector = () =>
            throw StateError('SENTINEL_APPLY_FAILURE');
        final incoming = _sampleBackupJson(questTitles: ['가져올 퀘스트']);

        final container = ProviderContainer(
          overrides: [
            storageServiceProvider.overrideWithValue(storage),
            backupServiceProvider.overrideWithValue(backupService),
            crashReporterProvider.overrideWithValue(FakeCrashReporter()),
          ],
        );
        addTearDown(container.dispose);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              theme: AppTheme.light,
              home: SettingsScreen(
                debugPickBackupSource: (_) async => incoming,
              ),
            ),
          ),
        );

        await tester.tap(find.text('백업 가져오기'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('교체'));
        await tester.pumpAndSettle();

        expect(
          find.text('가져오기에 실패해 기존 데이터로 되돌렸어요. 다시 시도할 수 있어요.'),
          findsOneWidget,
        );
        // 원인 예외 문자열이 그대로 노출되지 않는다.
        expect(find.textContaining('SENTINEL_APPLY_FAILURE'), findsNothing);

        // provider 상태가 실제 storage(롤백으로 원상복구된 상태)와 일치한다.
        expect(
          container.read(questsProvider).map((q) => q.toJson()).toList(),
          storage.getQuests().map((q) => q.toJson()).toList(),
        );
        expect(storage.getQuests().single.title, '원래 퀘스트');
      },
    );

    testWidgets(
      'apply와 rollback이 모두 실패하면 강한 경고를 보여주고 provider가 storage와 동기화된다',
      (tester) async {
        setScreenSize(tester, const Size(800, 1200));
        final storage = await createTestStorage();
        await storage.saveQuest(
          Quest(
            id: 'q0',
            title: '원래 퀘스트',
            description: '',
            statRewards: {'health': 10},
            createdAt: DateTime(2026, 7, 1),
          ),
        );

        final backupService = BackupService(storage: storage);
        backupService.debugApplyFaultInjector = () =>
            throw StateError('SENTINEL_APPLY_FAILURE');
        backupService.debugRollbackFaultInjector = () =>
            throw StateError('SENTINEL_ROLLBACK_FAILURE');
        final incoming = _sampleBackupJson(questTitles: ['가져올 퀘스트']);

        final container = ProviderContainer(
          overrides: [
            storageServiceProvider.overrideWithValue(storage),
            backupServiceProvider.overrideWithValue(backupService),
            crashReporterProvider.overrideWithValue(FakeCrashReporter()),
          ],
        );
        addTearDown(container.dispose);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              theme: AppTheme.light,
              home: SettingsScreen(
                debugPickBackupSource: (_) async => incoming,
              ),
            ),
          ),
        );

        await tester.tap(find.text('백업 가져오기'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('교체'));
        await tester.pumpAndSettle();

        // 강한 경고: 되돌리는 것도 실패해 상태가 불완전할 수 있음을 알린다.
        expect(find.textContaining('불완전할 수 있어요'), findsOneWidget);
        expect(find.textContaining('SENTINEL_APPLY_FAILURE'), findsNothing);
        expect(find.textContaining('SENTINEL_ROLLBACK_FAILURE'), findsNothing);

        // provider 상태가 (부분 상태일 수 있는) 실제 storage와 그대로 일치한다.
        expect(
          container.read(statsProvider).map((s) => s.toJson()).toList(),
          storage.getStats().map((s) => s.toJson()).toList(),
        );
        expect(
          container.read(questsProvider).map((q) => q.toJson()).toList(),
          storage.getQuests().map((q) => q.toJson()).toList(),
        );
      },
    );

    testWidgets('가져오기 소스 선택 중 예외가 나도 일반화된 오류만 보여주고 원문은 새지 않는다', (tester) async {
      setScreenSize(tester, const Size(800, 1200));
      final storage = await createTestStorage();
      await storage.saveQuest(
        Quest(
          id: 'q0',
          title: '원래 퀘스트',
          description: '',
          statRewards: {'health': 10},
          createdAt: DateTime(2026, 7, 1),
        ),
      );

      await pumpApp(
        tester,
        storage,
        SettingsScreen(
          debugPickBackupSource: (_) async =>
              throw StateError('SENTINEL_PICK_FAILURE'),
        ),
      );

      await tester.tap(find.text('백업 가져오기'));
      await tester.pumpAndSettle();

      expect(find.text('파일을 읽을 수 없어요. 다시 시도해주세요.'), findsOneWidget);
      expect(find.textContaining('SENTINEL_PICK_FAILURE'), findsNothing);
      expect(find.text('교체'), findsNothing);
      // 취소와 동일하게 아무것도 바뀌지 않아야 한다.
      expect(storage.getQuests().single.title, '원래 퀘스트');
    });

    testWidgets('encode() 실패 시 일반화된 오류만 보여주고 원문은 새지 않는다', (tester) async {
      setScreenSize(tester, const Size(800, 1200));
      final storage = await createTestStorage();
      final backupService = _ThrowingEncodeBackupService(storage: storage);

      final container = ProviderContainer(
        overrides: [
          storageServiceProvider.overrideWithValue(storage),
          backupServiceProvider.overrideWithValue(backupService),
          crashReporterProvider.overrideWithValue(FakeCrashReporter()),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.light,
            home: const SettingsScreen(),
          ),
        ),
      );

      await tester.tap(find.text('백업 내보내기'));
      await tester.pumpAndSettle();

      expect(find.text('백업 저장에 실패했어요. 잠시 후 다시 시도해주세요.'), findsOneWidget);
      expect(find.textContaining('SENTINEL_ENCODE_FAILURE'), findsNothing);
    });

    testWidgets('저장 단계(디스크 쓰기) 실패 시 일반화된 오류만 보여주고 원문은 새지 않는다', (tester) async {
      setScreenSize(tester, const Size(800, 1200));
      final storage = await createTestStorage();

      await pumpApp(
        tester,
        storage,
        SettingsScreen(
          debugSaveBackupFile: (fileName, jsonStr) async {
            throw StateError('SENTINEL_SAVE_FAILURE');
          },
        ),
      );

      await tester.tap(find.text('백업 내보내기'));
      await tester.pumpAndSettle();

      expect(find.text('백업 저장에 실패했어요. 잠시 후 다시 시도해주세요.'), findsOneWidget);
      expect(find.textContaining('SENTINEL_SAVE_FAILURE'), findsNothing);
    });

    testWidgets('provider reload 하나가 실패해도 나머지 reload와 실패 경고 메시지가 그대로 유지된다', (
      tester,
    ) async {
      setScreenSize(tester, const Size(800, 1200));
      final storage = _FlakyFinancialPlanStorage(inMemory: true);
      await storage.init();
      addTearDown(Hive.close);
      await storage.saveQuest(
        Quest(
          id: 'q0',
          title: '원래 퀘스트',
          description: '',
          statRewards: {'health': 10},
          createdAt: DateTime(2026, 7, 1),
        ),
      );

      final backupService = BackupService(storage: storage);
      backupService.debugApplyFaultInjector = () =>
          throw StateError('SENTINEL_APPLY_FAILURE');
      final incoming = _sampleBackupJson(questTitles: ['가져올 퀘스트']);

      final container = ProviderContainer(
        overrides: [
          storageServiceProvider.overrideWithValue(storage),
          backupServiceProvider.overrideWithValue(backupService),
          crashReporterProvider.overrideWithValue(FakeCrashReporter()),
        ],
      );
      addTearDown(container.dispose);
      // financialPlanProvider의 초기 빌드는 정상적으로 끝낸 뒤에만 reload
      // 단계에서 실패하도록 켠다 — 그래야 "reload가 실패한다"는 시나리오를
      // 정확히 재현한다.
      container.read(financialPlanProvider);
      storage.throwOnGetFinancialPlan = true;

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.light,
            home: SettingsScreen(debugPickBackupSource: (_) async => incoming),
          ),
        ),
      );

      await tester.tap(find.text('백업 가져오기'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('교체'));
      await tester.pumpAndSettle();

      // financialPlan reload가 던지더라도, 되돌림 경고는 여전히 보여야 한다.
      expect(
        find.text('가져오기에 실패해 기존 데이터로 되돌렸어요. 다시 시도할 수 있어요.'),
        findsOneWidget,
      );
      expect(find.textContaining('SENTINEL_RELOAD_FAILURE'), findsNothing);
      expect(find.textContaining('SENTINEL_APPLY_FAILURE'), findsNothing);

      // 실패한 provider 외 나머지는 여전히 storage와 동기화된다.
      expect(
        container.read(questsProvider).map((q) => q.toJson()).toList(),
        storage.getQuests().map((q) => q.toJson()).toList(),
      );
    });
  });
}

/// Minimal, schema-valid backup JSON with a single stat and the given quest
/// titles — enough to drive the preview/confirm widget flow without needing
/// a full [BackupService.encode] round trip.
String _sampleBackupJson({required List<String> questTitles}) {
  return jsonEncode({
    'schemaVersion': BackupService.currentSchemaVersion,
    'stats': [Stat(id: 'health', name: '건강', icon: '💪', level: 5).toJson()],
    'quests': questTitles
        .map(
          (t) => Quest(
            id: 'q_$t',
            title: t,
            description: '',
            statRewards: {'health': 10},
            createdAt: DateTime(2026, 7, 1),
          ).toJson(),
        )
        .toList(),
    'goals': <Map<String, dynamic>>[],
    'transactions': <Map<String, dynamic>>[],
    'assetSnapshots': <Map<String, dynamic>>[],
    'achievements': <String, dynamic>{},
  });
}

/// A [BackupService] whose `encode()` always throws — used to verify export
/// never lets a raw exception from the encode step reach the UI.
class _ThrowingEncodeBackupService extends BackupService {
  _ThrowingEncodeBackupService({required super.storage});

  @override
  String encode() => throw StateError('SENTINEL_ENCODE_FAILURE');
}

/// A [StorageService] whose `getFinancialPlan()` can be switched to throw on
/// demand — used to simulate a single provider's reload failing partway
/// through [SettingsScreen]'s post-restore reload sweep, without touching
/// the initial (successful) read providers perform at construction time.
class _FlakyFinancialPlanStorage extends StorageService {
  _FlakyFinancialPlanStorage({super.inMemory});

  bool throwOnGetFinancialPlan = false;

  @override
  FinancialPlan getFinancialPlan() {
    if (throwOnGetFinancialPlan) {
      throw StateError('SENTINEL_RELOAD_FAILURE');
    }
    return super.getFinancialPlan();
  }
}
