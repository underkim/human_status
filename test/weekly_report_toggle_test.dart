import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:human_status/models/user_profile.dart';
import 'package:human_status/providers/profile_provider.dart';
import 'package:human_status/screens/settings_screen.dart';
import 'package:human_status/services/notification_service.dart';
import 'package:human_status/services/storage_service.dart';
import 'package:human_status/theme/app_theme.dart';

import 'helpers/test_app.dart';

/// 실제 플러그인은 테스트 바인딩에 없으므로 스케줄/취소 호출만 기록한다.
/// [granted]를 false로 주면 예외 없이 권한 거부(false) 결과를 돌려준다.
class _FakeNotificationService extends NotificationService {
  _FakeNotificationService({this.granted = true, this.weeklyScheduled = false});

  final bool granted;
  bool weeklyScheduled;

  int scheduleWeeklyCalls = 0;
  int cancelWeeklyCalls = 0;

  @override
  Future<bool> scheduleWeeklyReportReminder() async {
    scheduleWeeklyCalls++;
    weeklyScheduled = true;
    return granted;
  }

  @override
  Future<void> cancelWeeklyReportReminder() async {
    cancelWeeklyCalls++;
    weeklyScheduled = false;
  }
}

class _FailingProfileStorage extends StorageService {
  _FailingProfileStorage() : super(inMemory: true);

  bool failNextProfileSave = false;

  @override
  Future<void> saveProfile(UserProfile profile) {
    if (failNextProfileSave) {
      failNextProfileSave = false;
      throw StateError('SENTINEL_PROFILE_SAVE_FAILURE');
    }
    return super.saveProfile(profile);
  }
}

Future<_FailingProfileStorage> _createFailingStorage() async {
  final storage = _FailingProfileStorage();
  await storage.init();
  addTearDown(Hive.close);
  return storage;
}

/// 플랫폼/타임존 예외가 스케줄·취소 도중 발생하는 경로를 검증하기 위한 fake.
class _ThrowingNotificationService extends NotificationService {
  int scheduleWeeklyCalls = 0;
  int cancelWeeklyCalls = 0;

  @override
  Future<bool> scheduleWeeklyReportReminder() async {
    scheduleWeeklyCalls++;
    throw NotificationTimezoneException('Bogus/Zone');
  }

  @override
  Future<void> cancelWeeklyReportReminder() async {
    cancelWeeklyCalls++;
    throw NotificationTimezoneException('Bogus/Zone');
  }
}

Future<_FakeNotificationService> _pumpSettings(
  WidgetTester tester,
  StorageService storage, {
  bool granted = true,
}) async {
  final fake = _FakeNotificationService(granted: granted);
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

Future<_ThrowingNotificationService> _pumpSettingsWithThrowingService(
  WidgetTester tester,
  StorageService storage,
) async {
  final fake = _ThrowingNotificationService();
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
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
      isTrue,
    );
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

  testWidgets('주간 리포트 알림 활성화 중 예외가 나면 설정이 저장되지 않고 오류가 표시된다', (tester) async {
    final storage = await createTestStorage();
    final fake = await _pumpSettingsWithThrowingService(tester, storage);

    expect(storage.getProfile().weeklyReportReminderEnabled, isFalse);

    await tester.tap(find.text('주간 리포트 알림'));
    await tester.pumpAndSettle();

    expect(fake.scheduleWeeklyCalls, 1);
    // 스케줄링이 실패했으므로 프로필은 그대로 꺼짐 상태로 남아야 한다.
    expect(storage.getProfile().weeklyReportReminderEnabled, isFalse);
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
      isFalse,
    );
    expect(find.text('알림 설정을 변경하지 못했어요. 잠시 후 다시 시도해주세요.'), findsOneWidget);
    expect(find.text('일요일 20:00에 주간 리포트를 알려드릴게요.'), findsNothing);
  });

  testWidgets('주간 리포트 알림 비활성화 중 예외가 나면 설정이 그대로 켜진 상태로 남고 오류가 표시된다', (
    tester,
  ) async {
    final storage = await createTestStorage();
    final profile = storage.getProfile();
    profile.weeklyReportReminderEnabled = true;
    await storage.saveProfile(profile);

    final fake = await _pumpSettingsWithThrowingService(tester, storage);
    await tester.tap(find.text('주간 리포트 알림'));
    await tester.pumpAndSettle();

    expect(fake.cancelWeeklyCalls, 1);
    // 취소가 실패했으므로 이전 상태(켜짐)가 그대로 유지되어야 한다.
    expect(storage.getProfile().weeklyReportReminderEnabled, isTrue);
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
      isTrue,
    );
    expect(find.text('알림 설정을 변경하지 못했어요. 잠시 후 다시 시도해주세요.'), findsOneWidget);
  });

  testWidgets('주간 리포트 알림 권한이 거부되어도(예외 없이 false) 설정은 저장되고 권한 경고가 표시된다', (
    tester,
  ) async {
    final storage = await createTestStorage();
    final fake = await _pumpSettings(tester, storage, granted: false);

    expect(storage.getProfile().weeklyReportReminderEnabled, isFalse);

    await tester.tap(find.text('주간 리포트 알림'));
    await tester.pumpAndSettle();

    expect(fake.scheduleWeeklyCalls, 1);
    // false는 예외가 아니라 "등록은 됐지만 OS가 권한을 껐다"는 뜻이므로
    // enabled=true는 그대로 저장돼야 한다.
    expect(storage.getProfile().weeklyReportReminderEnabled, isTrue);
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
      isTrue,
    );
    expect(
      find.text('설정은 저장됐지만 알림 권한이 꺼져 있어요 — 기기 설정에서 허용해주세요.'),
      findsOneWidget,
    );
  });

  testWidgets('주간 알림 활성화의 프로필 저장이 실패하면 새 OS 일정을 취소한다', (tester) async {
    final storage = await _createFailingStorage();
    final fake = await _pumpSettings(tester, storage);
    storage.failNextProfileSave = true;

    await tester.tap(find.text('주간 리포트 알림'));
    await tester.pumpAndSettle();

    expect(storage.getProfile().weeklyReportReminderEnabled, isFalse);
    expect(fake.scheduleWeeklyCalls, 1);
    expect(fake.cancelWeeklyCalls, 1);
    expect(fake.weeklyScheduled, isFalse);
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
      isFalse,
    );
    expect(find.text('알림 설정을 변경하지 못했어요. 잠시 후 다시 시도해주세요.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('주간 알림 비활성화의 프로필 저장이 실패하면 이전 OS 일정을 복원한다', (tester) async {
    final storage = await _createFailingStorage();
    final profile = storage.getProfile();
    profile.weeklyReportReminderEnabled = true;
    await storage.saveProfile(profile);
    final fake = _FakeNotificationService(weeklyScheduled: true);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          storageServiceProvider.overrideWithValue(storage),
          notificationServiceProvider.overrideWithValue(fake),
        ],
        child: MaterialApp(theme: AppTheme.light, home: const SettingsScreen()),
      ),
    );
    storage.failNextProfileSave = true;

    await tester.tap(find.text('주간 리포트 알림'));
    await tester.pumpAndSettle();

    expect(storage.getProfile().weeklyReportReminderEnabled, isTrue);
    expect(fake.cancelWeeklyCalls, 1);
    expect(fake.scheduleWeeklyCalls, 1);
    expect(fake.weeklyScheduled, isTrue);
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
      isTrue,
    );
    expect(find.text('알림 설정을 변경하지 못했어요. 잠시 후 다시 시도해주세요.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
