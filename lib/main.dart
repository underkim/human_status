import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'models/quest.dart';
import 'providers/profile_provider.dart';
import 'screens/home_shell.dart';
import 'services/financial_advisor_service.dart';
import 'services/notification_service.dart';
import 'services/quest_recommendation_service.dart';
import 'services/storage_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final storage = StorageService();
  await storage.init();
  await QuestRecommendationService(storage: storage).refreshIfNeeded();
  await FinancialAdvisorService(storage: storage).refreshIfNeeded();

  final notificationService = NotificationService();
  await notificationService.init();
  final reminderMinutes = storage.getProfile().reminderMinutesSinceMidnight;
  if (reminderMinutes != null) {
    final activeQuestCount = storage.getQuests().where((q) => q.status == QuestStatus.active).length;
    await notificationService.scheduleDailyReminder(
      hour: reminderMinutes ~/ 60,
      minute: reminderMinutes % 60,
      activeQuestCount: activeQuestCount,
    );
  }

  runApp(
    ProviderScope(
      overrides: [storageServiceProvider.overrideWithValue(storage)],
      child: const HumanStatusApp(),
    ),
  );
}

class HumanStatusApp extends StatelessWidget {
  const HumanStatusApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Human Status',
      theme: ThemeData(colorSchemeSeed: Colors.deepPurple, useMaterial3: true),
      darkTheme: ThemeData(
        colorSchemeSeed: Colors.deepPurple,
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      home: const HomeShell(),
    );
  }
}
