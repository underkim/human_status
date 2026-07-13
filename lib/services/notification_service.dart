import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

/// Local (on-device) daily reminder notifications. No-op on web, where the
/// underlying plugin has no native scheduling support.
class NotificationService {
  static const _dailyReminderId = 1;
  static const _windowsGuid = 'f6f4d1a0-6b7a-4b0e-9c8a-6b2b6a2e0e01';

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> init() async {
    if (kIsWeb || _initialized) return;

    tz_data.initializeTimeZones();
    tz.setLocalLocation(tz.local);

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwinSettings = DarwinInitializationSettings();
    const linuxSettings = LinuxInitializationSettings(defaultActionName: 'Open');
    const windowsSettings = WindowsInitializationSettings(
      appName: 'Human Status',
      appUserModelId: 'com.humanstatus.app',
      guid: _windowsGuid,
    );

    await _plugin.initialize(
      settings: const InitializationSettings(
        android: androidSettings,
        iOS: darwinSettings,
        macOS: darwinSettings,
        linux: linuxSettings,
        windows: windowsSettings,
      ),
    );
    _initialized = true;
  }

  /// Whether the OS will actually deliver our notifications. Returns null on
  /// platforms where this can't be queried (treat as "probably fine").
  Future<bool?> areNotificationsEnabled() async {
    if (kIsWeb) return false;
    await init();
    return _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.areNotificationsEnabled();
  }

  /// Schedules (or reschedules) a daily reminder at [hour]:[minute]. The
  /// notification body reflects how many quests are currently active.
  ///
  /// Returns false when the user denied the notification permission — the
  /// alarm is still registered, but the OS will silently swallow it, so
  /// callers should surface a warning instead of claiming success.
  Future<bool> scheduleDailyReminder({
    required int hour,
    required int minute,
    int activeQuestCount = 0,
  }) async {
    if (kIsWeb) return false;
    await init();
    final granted = await _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();

    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    if (scheduled.isBefore(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }

    final body = activeQuestCount > 0
        ? '진행중인 퀘스트가 $activeQuestCount개 있어요!'
        : '오늘의 퀘스트를 확인해보세요!';

    await _plugin.zonedSchedule(
      id: _dailyReminderId,
      title: 'Human Status',
      body: body,
      scheduledDate: scheduled,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'daily_reminder',
          '일일 리마인더',
          channelDescription: '매일 정해진 시간에 퀘스트를 알려드려요.',
        ),
        iOS: DarwinNotificationDetails(),
        macOS: DarwinNotificationDetails(),
        linux: LinuxNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
    );

    // null means the platform can't report permission (iOS/desktop) — assume
    // granted rather than alarming the user for nothing.
    return granted ?? true;
  }

  Future<void> cancelReminder() async {
    if (kIsWeb) return;
    await _plugin.cancel(id: _dailyReminderId);
  }
}
