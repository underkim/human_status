import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:human_status/providers/profile_provider.dart';
import 'package:human_status/screens/settings_screen.dart';
import 'package:human_status/services/notification_service.dart';
import 'package:human_status/services/storage_service.dart';
import 'package:human_status/theme/app_theme.dart';

import 'helpers/test_app.dart';

/// 실제 플러그인은 테스트 바인딩에 없으므로 스케줄/취소 호출만 기록한다.
class _FakeNotificationService extends NotificationService {
  int scheduleWeeklyCalls = 0;
  int cancelWeeklyCalls = 0;

  @override
  Future<bool> scheduleWeeklyReportReminder() async {
    scheduleWeeklyCalls++;
    return true;
  }

  @override
  Future<void> cancelWeeklyReportReminder() async {
    cancelWeeklyCalls++;
  }
}

Future<_FakeNotificationService> _pumpSettings(WidgetTester tester, StorageService storage) async {
  final fake = _FakeNotificationService();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        storageServiceProvider.overrideWithValue(storage),
        notificationServiceProvider.overrideWithValue(fake),
      ],
      child: MaterialApp(theme: AppTheme.light, home: const SettingsScreen()),
    ),
  );
  return fake;
}

void main() {
  testWidgets('주간 리포트 알림을 켜면 스케줄이 등록되고 설정이 저장된다', (tester) async {
    final storage = await createTestStorage();
    final fake = await _pumpSettings(tester, storage);

    expect(storage.getProfile().weeklyReportReminderEnabled, isFalse);

    await tester.tap(find.text('주간 리포트 알림'));
    await tester.pumpAndSettle();

    expect(storage.getProfile().weeklyReportReminderEnabled, isTrue);
    expect(fake.scheduleWeeklyCalls, 1);
    expect(find.text('일요일 20:00에 주간 리포트를 알려드릴게요.'), findsOneWidget);
    // 프로필 reload가 리스너에 실제로 전파되어 스위치 UI도 켜져야 한다.
    expect(tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value, isTrue);
  });

  testWidgets('주간 리포트 알림을 끄면 스케줄이 취소된다', (tester) async {
    final storage = await createTestStorage();
    final profile = storage.getProfile();
    profile.weeklyReportReminderEnabled = true;
    await storage.saveProfile(profile);

    final fake = await _pumpSettings(tester, storage);
    await tester.tap(find.text('주간 리포트 알림'));
    await tester.pumpAndSettle();

    expect(storage.getProfile().weeklyReportReminderEnabled, isFalse);
    expect(fake.cancelWeeklyCalls, 1);
  });
}
