import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'models/quest.dart';
import 'providers/financial_advisor_provider.dart';
import 'providers/profile_provider.dart';
import 'providers/quest_provider.dart';
import 'screens/home_shell.dart';
import 'services/daily_refresh_controller.dart';
import 'services/notification_service.dart';
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
  // daily habit loop depends on it launching instantly.
  unawaited(refreshController.refreshIfDue());
  unawaited(_scheduleNotifications(storage));
}

Future<void> _scheduleNotifications(StorageService storage) async {
  try {
    final notificationService = NotificationService();
    await notificationService.init();
    final profile = storage.getProfile();
    final reminderMinutes = profile.reminderMinutesSinceMidnight;
    if (reminderMinutes != null) {
      final activeQuestCount = storage
          .getQuests()
          .where((q) => q.status == QuestStatus.active)
          .length;
      await notificationService.scheduleDailyReminder(
        hour: reminderMinutes ~/ 60,
        minute: reminderMinutes % 60,
        activeQuestCount: activeQuestCount,
      );
    }
    if (profile.weeklyReportReminderEnabled) {
      await notificationService.scheduleWeeklyReportReminder();
    }
  } catch (_) {}
}

class HumanStatusApp extends StatefulWidget {
  const HumanStatusApp({super.key, this.refreshController});

  final DailyRefreshController? refreshController;

  @override
  State<HumanStatusApp> createState() => _HumanStatusAppState();
}

class _HumanStatusAppState extends State<HumanStatusApp>
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
    return MaterialApp(
      title: 'Human Status',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      home: const HomeShell(),
    );
  }
}
