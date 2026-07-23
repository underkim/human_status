import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:human_status/models/user_profile.dart';
import 'package:human_status/providers/observability_provider.dart';
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

class _StatefulNotificationService extends NotificationService {
  _StatefulNotificationService({this.scheduledMinutes});

  int? scheduledMinutes;
  final scheduleHistory = <int>[];
  int cancelCalls = 0;

  @override
  Future<void> init() async {}

  @override
  Future<bool> scheduleDailyReminder({
    required int hour,
    required int minute,
    int activeQuestCount = 0,
  }) async {
    scheduledMinutes = hour * 60 + minute;
    scheduleHistory.add(scheduledMinutes!);
    return true;
  }

  @override
  Future<void> cancelReminder() async {
    cancelCalls++;
    scheduledMinutes = null;
  }
}

Future<_FailingProfileStorage> _createFailingStorage() async {
  final storage = _FailingProfileStorage();
  await storage.init();
  addTearDown(Hive.close);
  return storage;
}

/// A [StorageService] whose [saveProfile] blocks on [gate] until released —
/// lets a test observe SettingsScreen mid-save (button disabled, screen
/// still poppable) without a real async race. Same shape as
/// finance_transaction_ui_robustness_test.dart's `_GatedTransactionsNotifier`.
class _GatedProfileStorage extends StorageService {
  _GatedProfileStorage() : super(inMemory: true);

  Completer<void>? gate;
  int saveCalls = 0;

  @override
  Future<void> saveProfile(UserProfile profile) async {
    saveCalls++;
    if (gate != null) await gate!.future;
    await super.saveProfile(profile);
  }
}

Future<_GatedProfileStorage> _createGatedStorage() async {
  final storage = _GatedProfileStorage();
  await storage.init();
  addTearDown(Hive.close);
  return storage;
}

/// Pumps a host screen that pushes [SettingsScreen] on demand and separately
/// displays the live `profileProvider` reminder value — lets a test verify
/// that *other* still-mounted widgets see the reload even after the screen
/// that triggered the save has been popped.
Future<void> _pumpHostWithSettingsPush(
  WidgetTester tester,
  StorageService storage,
  NotificationService fake,
) {
  return tester.pumpWidget(
    ProviderScope(
      overrides: [
        storageServiceProvider.overrideWithValue(storage),
        notificationServiceProvider.overrideWithValue(fake),
        crashReporterProvider.overrideWithValue(FakeCrashReporter()),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        home: Builder(
          builder: (context) => Scaffold(
            body: Column(
              children: [
                Consumer(
                  builder: (context, ref, _) => Text(
                    '리마인더: ${ref.watch(profileProvider).reminderMinutesSinceMidnight}',
                  ),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SettingsScreen()),
                  ),
                  child: const Text('설정 열기'),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

Future<void> _pumpWithStatefulScheduler(
  WidgetTester tester,
  StorageService storage,
  _StatefulNotificationService fake,
) {
  return tester.pumpWidget(
    ProviderScope(
      overrides: [
        storageServiceProvider.overrideWithValue(storage),
        notificationServiceProvider.overrideWithValue(fake),
        crashReporterProvider.overrideWithValue(FakeCrashReporter()),
      ],
      child: MaterialApp(theme: AppTheme.light, home: const SettingsScreen()),
    ),
  );
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
        crashReporterProvider.overrideWithValue(FakeCrashReporter()),
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
    expect(find.text('알림 설정을 변경하지 못했어요. 잠시 후 다시 시도해주세요.'), findsOneWidget);
    expect(find.text('알림 시간이 저장됐어요.'), findsNothing);
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
    expect(find.text('알림 설정을 변경하지 못했어요. 잠시 후 다시 시도해주세요.'), findsOneWidget);
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
    expect(find.text('알림 설정을 변경하지 못했어요. 잠시 후 다시 시도해주세요.'), findsNothing);
  });

  testWidgets('새 알림의 프로필 저장이 실패하면 등록한 OS 알림을 취소하고 이전 상태를 유지한다', (tester) async {
    final storage = await _createFailingStorage();
    final fake = _StatefulNotificationService();
    await _pumpWithStatefulScheduler(tester, storage, fake);
    storage.failNextProfileSave = true;

    await tester.tap(find.text('알림 시간'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('시간 설정'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(storage.getProfile().reminderMinutesSinceMidnight, isNull);
    expect(fake.scheduleHistory, hasLength(1));
    expect(fake.cancelCalls, 1);
    expect(fake.scheduledMinutes, isNull);
    expect(find.text('알림 설정을 변경하지 못했어요. 잠시 후 다시 시도해주세요.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('알림 끄기의 프로필 저장이 실패하면 이전 시간의 OS 알림을 복원한다', (tester) async {
    final storage = await _createFailingStorage();
    final profile = storage.getProfile();
    profile.reminderMinutesSinceMidnight = 9 * 60;
    await storage.saveProfile(profile);
    final fake = _StatefulNotificationService(scheduledMinutes: 9 * 60);
    await _pumpWithStatefulScheduler(tester, storage, fake);
    storage.failNextProfileSave = true;

    await tester.tap(find.text('알림 시간'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('끄기'));
    await tester.pumpAndSettle();

    expect(storage.getProfile().reminderMinutesSinceMidnight, 9 * 60);
    expect(fake.cancelCalls, 1);
    expect(fake.scheduleHistory, [9 * 60]);
    expect(fake.scheduledMinutes, 9 * 60);
    expect(find.text('알림 설정을 변경하지 못했어요. 잠시 후 다시 시도해주세요.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('알림 시간 변경의 프로필 저장이 실패하면 이전 시간으로 다시 예약한다', (tester) async {
    final storage = await _createFailingStorage();
    final profile = storage.getProfile();
    profile.reminderMinutesSinceMidnight = 9 * 60;
    await storage.saveProfile(profile);
    final fake = _StatefulNotificationService(scheduledMinutes: 9 * 60);
    await _pumpWithStatefulScheduler(tester, storage, fake);
    storage.failNextProfileSave = true;

    await tester.tap(find.text('알림 시간'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('시간 설정'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.keyboard_outlined));
    await tester.pumpAndSettle();
    final timeFields = find.byType(TextField);
    expect(timeFields, findsNWidgets(2));
    await tester.enterText(timeFields.at(0), '10');
    await tester.enterText(timeFields.at(1), '00');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(storage.getProfile().reminderMinutesSinceMidnight, 9 * 60);
    expect(fake.scheduleHistory, [10 * 60, 9 * 60]);
    expect(fake.scheduledMinutes, 9 * 60);
    expect(find.text('알림 설정을 변경하지 못했어요. 잠시 후 다시 시도해주세요.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('저장이 대기 중일 때 화면을 벗어나도 예외가 없고, 다른 화면의 프로필 상태는 그대로 최신화된다', (
    tester,
  ) async {
    final storage = await _createGatedStorage();
    final gate = Completer<void>();
    storage.gate = gate;
    final fake = _StatefulNotificationService();

    await _pumpHostWithSettingsPush(tester, storage, fake);
    expect(find.text('리마인더: null'), findsOneWidget);

    await tester.tap(find.text('설정 열기'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('알림 시간'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('시간 설정'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pump();
    expect(storage.saveCalls, 1);

    // Back out of Settings while storage.saveProfile is still gated — the
    // coroutine keeps running detached from the (soon-to-be-disposed) State.
    Navigator.of(tester.element(find.byType(SettingsScreen))).pop();
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsNothing);

    gate.complete();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    // The write landed...
    expect(storage.getProfile().reminderMinutesSinceMidnight, isNotNull);
    // ...and the *host* screen's still-mounted profileProvider watcher
    // picked up the reload, proving it wasn't skipped just because the
    // screen that started the save is gone.
    expect(find.text('리마인더: null'), findsNothing);
  });

  testWidgets('알림 시간 저장이 진행 중일 때는 알림 관련 컨트롤이 비활성화된다 (직렬화)', (tester) async {
    final storage = await _createGatedStorage();
    final gate = Completer<void>();
    storage.gate = gate;
    final fake = _StatefulNotificationService();

    await _pumpWithStatefulScheduler(tester, storage, fake);

    await tester.tap(find.text('알림 시간'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('시간 설정'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pump();

    expect(storage.saveCalls, 1);
    // Both the reminder tile and the weekly-report switch are locked while
    // this save is in flight, so a second notification-mutating operation
    // can never interleave with it.
    expect(
      tester.widget<ListTile>(find.widgetWithText(ListTile, '알림 시간')).enabled,
      isFalse,
    );
    expect(
      tester
          .widget<SwitchListTile>(
            find.widgetWithText(SwitchListTile, '주간 리포트 알림'),
          )
          .onChanged,
      isNull,
    );

    gate.complete();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    // Controls re-enable once the save settles, so the next change isn't
    // permanently locked out.
    expect(
      tester.widget<ListTile>(find.widgetWithText(ListTile, '알림 시간')).enabled,
      isTrue,
    );
    expect(
      tester
          .widget<SwitchListTile>(
            find.widgetWithText(SwitchListTile, '주간 리포트 알림'),
          )
          .onChanged,
      isNotNull,
    );
  });
}
