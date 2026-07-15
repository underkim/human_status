import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:human_status/main.dart';
import 'package:human_status/models/goal.dart';
import 'package:human_status/models/quest.dart';
import 'package:human_status/models/user_profile.dart';
import 'package:human_status/providers/goal_provider.dart';
import 'package:human_status/providers/profile_provider.dart';
import 'package:human_status/screens/goal_form_screen.dart';
import 'package:human_status/screens/home_shell.dart';
import 'package:human_status/screens/onboarding_screen.dart';
import 'package:human_status/services/backup_service.dart';
import 'package:human_status/services/goal_service.dart';
import 'package:human_status/services/onboarding_gate.dart';
import 'package:human_status/services/storage_service.dart';
import 'package:human_status/theme/app_theme.dart';

import 'helpers/test_app.dart';

/// decompose가 항상 빈 리스트를 돌려주는 가짜 GoalService — "생성 실패"
/// 경로(연결 퀘스트가 하나도 안 만들어지는 경우)를 결정적으로 재현한다.
class _NoQuestGoalService extends GoalService {
  _NoQuestGoalService(StorageService storage) : super(storage: storage);

  @override
  Future<List<Quest>> decompose(Goal goal, {int count = 4}) async => [];
}

void main() {
  group('shouldShowOnboarding', () {
    test('신규 프로필은 온보딩을 보여준다', () async {
      final storage = await createTestStorage();
      expect(shouldShowOnboarding(storage), isTrue);
    });

    test('구버전 레코드(필드 없음)는 onboardingCompleted가 true로 읽혀 온보딩을 건너뛴다', () async {
      // 실제 어댑터의 필드-부재 폴백은 test/user_profile_adapter_test.dart에서
      // 진짜 Hive 바이너리 왕복으로 검증한다. 여기서는 그 폴백이 이미 적용된
      // 상태(= onboardingCompleted: true)를 게이트 함수 자체의 입력으로 써서
      // shouldShowOnboarding의 판단만 확인한다.
      final storage = await createTestStorage();
      await storage.saveProfile(UserProfile(onboardingCompleted: true));
      expect(shouldShowOnboarding(storage), isFalse);
    });

    test('이미 완료 처리된 프로필은 온보딩을 다시 보여주지 않는다', () async {
      final storage = await createTestStorage();
      final profile = storage.getProfile();
      profile.onboardingCompleted = true;
      await storage.saveProfile(profile);
      expect(shouldShowOnboarding(storage), isFalse);
    });

    test('신규 프로필이라도 기존 목표/퀘스트 데이터가 있으면(복원 등) 온보딩에 가두지 않는다', () async {
      final storage = await createTestStorage();
      await storage.saveGoal(
        Goal(
          id: 'g1',
          title: '복원된 목표',
          description: '',
          statId: 'health',
          createdAt: DateTime(2026, 1, 1),
        ),
      );
      expect(shouldShowOnboarding(storage), isFalse);
    });
  });

  group('HumanStatusApp 진입 화면', () {
    testWidgets('신규 설치는 온보딩 화면으로 시작한다', (tester) async {
      final storage = await createTestStorage();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [storageServiceProvider.overrideWithValue(storage)],
          child: const HumanStatusApp(),
        ),
      );
      await tester.pump();

      expect(find.byType(OnboardingScreen), findsOneWidget);
      expect(find.byType(HomeShell), findsNothing);
    });

    testWidgets('완료 처리된 프로필은 바로 HomeShell로 시작한다', (tester) async {
      final storage = await createTestStorage();
      final profile = storage.getProfile();
      profile.onboardingCompleted = true;
      await storage.saveProfile(profile);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [storageServiceProvider.overrideWithValue(storage)],
          child: const HumanStatusApp(),
        ),
      );
      await tester.pump();

      expect(find.byType(HomeShell), findsOneWidget);
      expect(find.byType(OnboardingScreen), findsNothing);
    });
  });

  group('OnboardingScreen 플로우', () {
    testWidgets('관심 스탯을 고르면 해당 스탯의 goal idea가 표시된다', (tester) async {
      setScreenSize(tester, const Size(400, 800));
      final storage = await createTestStorage();
      await pumpApp(tester, storage, const OnboardingScreen());

      await tester.tap(find.text('다음'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('재정'));
      await tester.pumpAndSettle();

      expect(find.text('비상금 모으기'), findsOneWidget);
      expect(find.text('불필요한 지출 줄이기'), findsOneWidget);
    });

    testWidgets('스타터 목표 완료 시 Goal 1개와 연결 active quest가 만들어지고 HomeShell로 전환된다', (
      tester,
    ) async {
      setScreenSize(tester, const Size(400, 800));
      final storage = await createTestStorage();
      // 실제 앱과 동일하게 HumanStatusApp을 통째로 pump한다 — profileProvider
      // 변화를 보고 MaterialApp의 home을 HomeShell로 바꿔치기하는 실제
      // reactive gate 경로를 검증한다.
      await tester.pumpWidget(
        ProviderScope(
          overrides: [storageServiceProvider.overrideWithValue(storage)],
          child: const HumanStatusApp(),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('다음'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('건강'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('시작하기').first);
      await tester.pumpAndSettle();

      expect(find.byType(HomeShell), findsOneWidget);
      expect(find.byType(OnboardingScreen), findsNothing);

      final goals = storage.getGoals();
      expect(goals, hasLength(1));
      final linkedActive = storage.getQuests().where(
        (q) => q.goalId == goals.single.id && q.status == QuestStatus.active,
      );
      expect(linkedActive, isNotEmpty);

      final profile = storage.getProfile();
      expect(profile.onboardingCompleted, isTrue);
      expect(profile.preferredStatId, 'health');
    });

    testWidgets('제출 중 이중 탭으로도 목표가 하나만 생성된다', (tester) async {
      setScreenSize(tester, const Size(400, 800));
      final storage = await createTestStorage();
      await pumpApp(tester, storage, const OnboardingScreen());

      await tester.tap(find.text('다음'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('건강'));
      await tester.pumpAndSettle();

      final startButton = find.text('시작하기').first;
      await tester.tap(startButton);
      // 아직 프레임을 완전히 진행시키지 않은 상태에서 다시 탭해 이중 탭을 흉내낸다.
      await tester.tap(startButton, warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(storage.getGoals(), hasLength(1));
    });

    testWidgets('생성 실패 시 완료 상태가 기록되지 않고 재시도할 수 있으며 중복 goal이 없다', (
      tester,
    ) async {
      setScreenSize(tester, const Size(400, 800));
      final storage = await createTestStorage();
      final container = ProviderContainer(
        overrides: [
          storageServiceProvider.overrideWithValue(storage),
          goalServiceProvider.overrideWithValue(_NoQuestGoalService(storage)),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.light,
            home: const OnboardingScreen(),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('다음'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('건강'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('시작하기').first);
      await tester.pumpAndSettle();

      // 실패 안내가 뜨고, 화면은 그대로라 재시도할 수 있다. 완료 상태도 기록되지 않는다.
      expect(find.byType(OnboardingScreen), findsOneWidget);
      expect(storage.getGoals(), isEmpty);
      expect(storage.getUnlockedAchievements(), isEmpty);
      expect(storage.getProfile().onboardingCompleted, isFalse);

      // 재시도해도 (다시 실패하지만) 중복 goal이 쌓이지 않는다.
      await tester.tap(find.text('시작하기').first);
      await tester.pumpAndSettle();
      expect(storage.getGoals(), isEmpty);
    });

    testWidgets('건너뛰기는 완료 상태를 저장하고 HomeShell로 전환하며, 재시작해도 온보딩이 다시 뜨지 않는다', (
      tester,
    ) async {
      setScreenSize(tester, const Size(400, 800));
      final storage = await createTestStorage();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [storageServiceProvider.overrideWithValue(storage)],
          child: const HumanStatusApp(),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('나중에 하기'));
      await tester.pumpAndSettle();

      expect(find.byType(HomeShell), findsOneWidget);
      expect(find.byType(OnboardingScreen), findsNothing);
      expect(storage.getProfile().onboardingCompleted, isTrue);

      // "재시작"을 새 HumanStatusApp 인스턴스로 흉내낸다 — 같은 storage를 그대로 사용한다.
      await tester.pumpWidget(
        ProviderScope(
          overrides: [storageServiceProvider.overrideWithValue(storage)],
          child: const HumanStatusApp(),
        ),
      );
      await tester.pump();
      expect(find.byType(OnboardingScreen), findsNothing);
      expect(find.byType(HomeShell), findsOneWidget);
    });
  });

  testWidgets('선호 스탯을 고르면 GoalFormScreen의 추천이 바뀐다', (tester) async {
    setScreenSize(tester, const Size(600, 1600));
    final storage = await createTestStorage();
    final profile = storage.getProfile();
    profile.onboardingCompleted = true;
    profile.preferredStatId = 'relationships';
    await storage.saveProfile(profile);

    await pumpApp(tester, storage, const GoalFormScreen());

    expect(find.text('추천 목표 (관심 분야 기준)'), findsOneWidget);
    expect(find.widgetWithText(ActionChip, '가족과 여행 다녀오기'), findsOneWidget);
  });

  group('preferences 백업 왕복', () {
    test('onboarding 완료/선호 스탯이 백업 → 복원 왕복에서 유지된다', () async {
      final storage = await createTestStorage();
      final profile = storage.getProfile();
      profile.onboardingCompleted = true;
      profile.preferredStatId = 'mental';
      profile.claudeApiKey = 'sk-should-not-travel';
      await storage.saveProfile(profile);

      final backup = BackupService(storage: storage).encode();

      // 다른 기기를 흉내내기 위해 프로필을 초기화한다.
      await storage.saveProfile(UserProfile());
      await BackupService(storage: storage).restore(backup);

      final restored = storage.getProfile();
      expect(restored.onboardingCompleted, isTrue);
      expect(restored.preferredStatId, 'mental');
      // 기기 설정(API 키)은 백업에 담기지 않는다.
      expect(restored.claudeApiKey, isNull);
    });
  });

  testWidgets('400x800 모바일 화면에서 온보딩 각 단계가 overflow 없이 렌더된다', (tester) async {
    setScreenSize(tester, const Size(400, 800));
    final storage = await createTestStorage();
    await pumpApp(tester, storage, const OnboardingScreen());
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('다음'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('건강'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
