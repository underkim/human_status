import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'models/quest.dart';
import 'providers/financial_advisor_provider.dart';
import 'providers/profile_provider.dart';
import 'providers/quest_provider.dart';
import 'screens/home_shell.dart';
import 'services/financial_advisor_service.dart';
import 'services/notification_service.dart';
import 'services/quest_recommendation_service.dart';
import 'services/recurring_quest_service.dart';
import 'services/storage_service.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final storage = StorageService();
  await storage.init();

  // A manual container (instead of a plain ProviderScope) so the background
  // refresh below can poke the affected notifiers to reload once it finishes.
  final container = ProviderContainer(
    overrides: [storageServiceProvider.overrideWithValue(storage)],
  );

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const HumanStatusApp(),
    ),
  );

  // AI refreshes and notification scheduling run AFTER the first frame is up —
  // a slow or absent network must never delay opening the app, since the
  // daily habit loop depends on it launching instantly.
  unawaited(_refreshInBackground(container, storage));
}

Future<void> _refreshInBackground(ProviderContainer container, StorageService storage) async {
  try {
    // 어제까지 완료된 '매일 반복' 퀘스트를 오늘의 활성 퀘스트로 되살린다.
    await RecurringQuestService(storage: storage).respawnDue();
    container.read(questsProvider.notifier).reload();
  } catch (_) {}

  try {
    await QuestRecommendationService(storage: storage).refreshIfNeeded();
    container.read(questsProvider.notifier).reload();
  } catch (_) {
    // Recommendation refresh already falls back to local rules internally;
    // if even that failed, today's suggestions simply stay as they were.
  }

  try {
    await FinancialAdvisorService(storage: storage).refreshIfNeeded();
    container.read(financialAdviceProvider.notifier).reload();
  } catch (_) {}

  try {
    final notificationService = NotificationService();
    await notificationService.init();
    final profile = storage.getProfile();
    final reminderMinutes = profile.reminderMinutesSinceMidnight;
    if (reminderMinutes != null) {
      final activeQuestCount =
          storage.getQuests().where((q) => q.status == QuestStatus.active).length;
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

class HumanStatusApp extends StatelessWidget {
  const HumanStatusApp({super.key});

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
