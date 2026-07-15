import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'models/quest.dart';
import 'providers/financial_advisor_provider.dart';
import 'providers/profile_provider.dart';
import 'providers/quest_provider.dart';
import 'screens/home_shell.dart';
import 'screens/onboarding_screen.dart';
import 'services/daily_refresh_controller.dart';
import 'services/notification_service.dart';
import 'services/onboarding_gate.dart';
import 'services/storage_service.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final storage = StorageService();
  await storage.init();

  // A manual container (instead of a plain ProviderScope) so the daily
  // refresh below can poke the affected notifiers to reload once it finishes.
  final container = ProviderContainer(
    overrides: [storageServiceProvider.overrideWithValue(storage)],
  );

  // 최초 시작과, 자정을 넘긴 뒤의 resume 모두 이 컨트롤러 하나를 거친다 —
  // 같은 날짜 안에서는 반복 호출돼도 한 번만 실제로 갱신한다.
  final refreshController = DailyRefreshController(
    storage: storage,
    onQuestsChanged: () => container.read(questsProvider.notifier).reload(),
    onAdviceChanged: () =>
        container.read(financialAdviceProvider.notifier).reload(),
  );

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: HumanStatusApp(refreshController: refreshController),
    ),
  );

  // AI refreshes and notification scheduling run AFTER the first frame is up —
  // a slow or absent network must never delay opening the app, since the
  // daily habit loop depends on it launching instantly. Notifications are
  // scheduled only once the startup refresh has settled, so the active-quest
  // count they read isn't a stale pre-respawn snapshot.
  unawaited(runStartupSequence(refreshController, storage));
}

/// Runs the startup refresh to completion before scheduling notifications,
/// so the reminder's active-quest count reflects post-respawn state rather
/// than a stale pre-refresh snapshot. [notificationService] is injectable
/// so tests can substitute a fake instead of hitting the real platform
/// plugin (mirrors [DailyRefreshController]'s pattern for its own steps).
Future<void> runStartupSequence(
  DailyRefreshController refreshController,
  StorageService storage, {
  NotificationService? notificationService,
}) async {
  await refreshController.refreshIfDue();
  await scheduleNotifications(
    storage,
    notificationService: notificationService,
  );
}

Future<void> scheduleNotifications(
  StorageService storage, {
  NotificationService? notificationService,
}) async {
  try {
    final service = notificationService ?? NotificationService();
    await service.init();
    final profile = storage.getProfile();
    final reminderMinutes = profile.reminderMinutesSinceMidnight;
    if (reminderMinutes != null) {
      final activeQuestCount = storage
          .getQuests()
          .where((q) => q.status == QuestStatus.active)
          .length;
      await service.scheduleDailyReminder(
        hour: reminderMinutes ~/ 60,
        minute: reminderMinutes % 60,
        activeQuestCount: activeQuestCount,
      );
    }
    if (profile.weeklyReportReminderEnabled) {
      await service.scheduleWeeklyReportReminder();
    }
  } catch (_) {}
}

class HumanStatusApp extends ConsumerStatefulWidget {
  const HumanStatusApp({super.key, this.refreshController});

  final DailyRefreshController? refreshController;

  @override
  ConsumerState<HumanStatusApp> createState() => _HumanStatusAppState();
}

class _HumanStatusAppState extends ConsumerState<HumanStatusApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 앱을 켜 둔 채 자정을 넘기고 돌아왔을 때도 반복 퀘스트/추천이 오늘
    // 기준으로 맞춰지도록 한다 — 실제로 다시 돌지 여부는 컨트롤러가 날짜
    // 경계로 판단하므로 같은 날 반복 resume는 UI를 막지 않고 그냥 끝난다.
    if (state == AppLifecycleState.resumed) {
      widget.refreshController?.refreshIfDue();
    }
  }

  @override
  Widget build(BuildContext context) {
    // profileProvider를 watch해 온보딩 게이트를 매 빌드마다 다시 평가한다
    // (시작 시 한 번만 계산하는 flag가 아님) — 온보딩 완료/건너뛰기는 물론
    // 데이터 초기화로 onboardingCompleted가 다시 false가 되는 경우에도,
    // 같은 실행 중에 즉시 반영되어 알맞은 화면으로 전환된다.
    ref.watch(profileProvider);
    final showOnboarding = shouldShowOnboarding(
      ref.read(storageServiceProvider),
    );
    return MaterialApp(
      // Navigator는 그 자체로 상태를 갖는 위젯이라, 예를 들어 설정 화면이
      // 몇 단계 push된 채로 온보딩 게이트가 바뀌면 `home`만 바꿔서는 이미
      // push된 화면들이 그대로 남는다 — showOnboarding이 바뀔 때마다 키를
      // 바꿔 앱 전체(그 안의 Navigator와 push 스택 포함)를 처음부터 다시
      // 마운트해, 항상 깨끗한 화면에서 시작하게 한다.
      key: ValueKey(showOnboarding),
      title: 'Human Status',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      home: showOnboarding ? const OnboardingScreen() : const HomeShell(),
    );
  }
}
