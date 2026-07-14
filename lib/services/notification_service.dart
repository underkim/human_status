import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../utils/formatters.dart';

/// Local (on-device) daily reminder notifications. No-op on web, where the
/// underlying plugin has no native scheduling support.
class NotificationService {
  static const _dailyReminderId = 1;
  static const _weeklyReportId = 2;
  static const _budgetExceededId = 3;
  static const _windowsGuid = 'f6f4d1a0-6b7a-4b0e-9c8a-6b2b6a2e0e01';

  /// 주간 리포트 알림이 울리는 요일·시각 — 한 주를 마감하는 일요일 저녁.
  static const weeklyReportWeekday = DateTime.sunday;
  static const weeklyReportHour = 20;

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

  /// Schedules (or reschedules) the weekly report notification for Sunday
  /// 20:00. Same permission semantics as [scheduleDailyReminder]: false
  /// means the alarm is registered but the OS will swallow it.
  Future<bool> scheduleWeeklyReportReminder() async {
    if (kIsWeb) return false;
    await init();
    final granted = await _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();

    final now = tz.TZDateTime.now(tz.local);
    // 다음 일요일 20:00 — DST 경계에서 시각이 밀리지 않도록 Duration 덧셈 대신
    // 달력 필드로 하루씩 재구성한다.
    var scheduled =
        tz.TZDateTime(tz.local, now.year, now.month, now.day, weeklyReportHour);
    while (scheduled.weekday != weeklyReportWeekday || scheduled.isBefore(now)) {
      scheduled = tz.TZDateTime(
          tz.local, scheduled.year, scheduled.month, scheduled.day + 1, weeklyReportHour);
    }

    await _plugin.zonedSchedule(
      id: _weeklyReportId,
      title: '주간 리포트',
      body: '이번 주 퀘스트·재무 요약이 준비됐어요. 더보기 → 리포트에서 확인해보세요.',
      scheduledDate: scheduled,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'weekly_report',
          '주간 리포트',
          channelDescription: '일요일 저녁에 한 주 활동 요약을 알려드려요.',
        ),
        iOS: DarwinNotificationDetails(),
        macOS: DarwinNotificationDetails(),
        linux: LinuxNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
    );

    return granted ?? true;
  }

  Future<void> cancelWeeklyReportReminder() async {
    if (kIsWeb) return;
    await _plugin.cancel(id: _weeklyReportId);
  }

  /// Fires immediately when this month's spending first crosses the budget.
  Future<void> showBudgetExceeded({required double spent, required double budget}) async {
    if (kIsWeb) return;
    await init();
    await _plugin.show(
      id: _budgetExceededId,
      title: '예산 초과',
      body: '이번 달 지출 ${formatWon(spent)} — 예산 ${formatWon(budget)}을 넘었어요.',
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'budget_alert',
          '예산 알림',
          channelDescription: '월 지출이 예산을 넘으면 알려드려요.',
        ),
        iOS: DarwinNotificationDetails(),
        macOS: DarwinNotificationDetails(),
        linux: LinuxNotificationDetails(),
      ),
    );
  }
}
