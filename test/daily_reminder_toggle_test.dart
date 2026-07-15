import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:human_status/providers/profile_provider.dart';
import 'package:human_status/screens/settings_screen.dart';
import 'package:human_status/services/notification_service.dart';
import 'package:human_status/services/storage_service.dart';
import 'package:human_status/theme/app_theme.dart';

import 'helpers/test_app.dart';

/// 스케줄/취소 도중 플랫폼·타임존 예외를 던지거나(기본값), 권한이 거부된
/// 스케줄 결과(false)를 돌려주는 fake. 실패 시 프로필이 이전 값 그대로
/// 유지되고 일반화된 오류만 보이는지, 권한 거부 시에는 값이 저장되면서도
/// 경고만 뜨는지 둘 다 이 fake 하나로 검증한다.
class _ThrowingNotificationService extends NotificationService {
  _ThrowingNotificationService({this.permissionDenied = false});

  /// When true, [scheduleDailyReminder] returns false (permission denied)
  /// instead of throwing.
  final bool permissionDenied;

  int scheduleCalls = 0;
  int cancelCalls = 0;

  @override
  Future<void> init() async {}

  @override
  Future<bool> scheduleDailyReminder({
    required int hour,
    required int minute,
    int activeQuestCount = 0,
  }) async {
    scheduleCalls++;
    if (permissionDenied) return false;
    throw NotificationTimezoneException('Bogus/Zone');
  }

  @override
  Future<void> cancelReminder() async {
    cancelCalls++;
    throw NotificationTimezoneException('Bogus/Zone');
  }
}

Future<_ThrowingNotificationService> _pumpSettings(
  WidgetTester tester,
  StorageService storage, {
  bool permissionDenied = false,
}) async {
  final fake = _ThrowingNotificationService(permissionDenied: permissionDenied);
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
  testWidgets('알림 시간을 새로 설정하는 중 예외가 나면 프로필이 저장되지 않고 오류가 표시된다', (tester) async {
    final storage = await createTestStorage();
    final fake = await _pumpSettings(tester, storage);

    expect(storage.getProfile().reminderMinutesSinceMidnight, isNull);

    await tester.tap(find.text('알림 시간'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('시간 설정'));
    await tester.pumpAndSettle();
    // Material 시간 선택기의 확인 버튼.
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(fake.scheduleCalls, 1);
    // 스케줄링이 실패했으므로 알림 시간은 저장되지 않아야 한다.
    expect(storage.getProfile().reminderMinutesSinceMidnight, isNull);
    expect(find.text('알림 설정을 변경하지 못했습니다. 잠시 후 다시 시도해주세요.'), findsOneWidget);
    expect(find.text('알림 시간이 저장되었습니다.'), findsNothing);
  });

  testWidgets('알림 끄기 도중 예외가 나면 기존 설정이 그대로 유지되고 오류가 표시된다', (tester) async {
    final storage = await createTestStorage();
    final profile = storage.getProfile();
    profile.reminderMinutesSinceMidnight = 9 * 60;
    await storage.saveProfile(profile);

    final fake = await _pumpSettings(tester, storage);

    await tester.tap(find.text('알림 시간'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('끄기'));
    await tester.pumpAndSettle();

    expect(fake.cancelCalls, 1);
    // 취소가 실패했으므로 이전 알림 시간이 그대로 남아 있어야 한다.
    expect(storage.getProfile().reminderMinutesSinceMidnight, 9 * 60);
    expect(find.text('알림 설정을 변경하지 못했습니다. 잠시 후 다시 시도해주세요.'), findsOneWidget);
  });

  testWidgets('알림 권한이 거부되어도(예외 없이 false) 알림 시간은 저장되고 권한 경고가 표시된다', (
    tester,
  ) async {
    final storage = await createTestStorage();
    final fake = await _pumpSettings(tester, storage, permissionDenied: true);

    expect(storage.getProfile().reminderMinutesSinceMidnight, isNull);

    await tester.tap(find.text('알림 시간'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('시간 설정'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(fake.scheduleCalls, 1);
    // false는 예외가 아니라 "등록은 됐지만 OS가 권한을 껐다"는 뜻이므로
    // 알림 시간은 그대로 저장돼야 한다.
    expect(storage.getProfile().reminderMinutesSinceMidnight, isNotNull);
    expect(
      find.text('시간은 저장됐지만 알림 권한이 꺼져 있어요 — 기기 설정에서 허용해주세요.'),
      findsOneWidget,
    );
    expect(find.text('알림 설정을 변경하지 못했습니다. 잠시 후 다시 시도해주세요.'), findsNothing);
  });
}
