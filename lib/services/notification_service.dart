import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../utils/formatters.dart';

/// Thrown when the device's timezone identifier can't be resolved to a
/// known IANA location. Callers must not fall back to scheduling in
/// UTC/some arbitrary zone when this happens — [NotificationService.init]
/// throws it instead, so the failure has to be handled explicitly.
class NotificationTimezoneException implements Exception {
  NotificationTimezoneException(this.identifier, [this.cause]);

  /// The (possibly malformed/unknown) identifier resolution returned.
  final String identifier;

  /// The underlying error, if any (e.g. the exception thrown by the
  /// timezone package or the platform channel lookup).
  final Object? cause;

  @override
  String toString() =>
      'NotificationTimezoneException: unknown timezone identifier "$identifier"'
      '${cause != null ? ' ($cause)' : ''}';
}

/// Resolves an IANA timezone identifier (e.g. the value returned by
/// `FlutterTimezone.getLocalTimezone().identifier`) to a timezone database
/// [tz.Location]. Pure — takes the identifier as a plain string, so tests
/// can exercise real IANA ids, including DST zones, without touching the
/// platform channel that resolving the *device's* timezone requires.
///
/// Throws [NotificationTimezoneException] for an unknown identifier
/// instead of silently falling back, so callers never end up scheduling in
/// the wrong zone.
tz.Location resolveTimezoneLocation(String identifier) {
  try {
    return tz.getLocation(identifier);
  } on Object catch (e) {
    throw NotificationTimezoneException(identifier, e);
  }
}

/// Resolves the device's current IANA timezone identifier. Injectable on
/// [NotificationService] so tests can substitute a fixed identifier instead
/// of invoking the `flutter_timezone` platform channel.
typedef TimezoneIdentifierResolver = Future<String> Function();

Future<String> _defaultTimezoneIdentifierResolver() async {
  final info = await FlutterTimezone.getLocalTimezone();
  return info.identifier;
}

/// The Android schedule mode used for every notification this service
/// schedules. Centralized so the daily reminder and the weekly report can
/// never drift apart.
///
/// `inexactAllowWhileIdle` needs no special permission — unlike
/// `exactAllowWhileIdle`, which requires `SCHEDULE_EXACT_ALARM`, a
/// permission Android 13+ does *not* grant by default to new installs, so
/// scheduling with it can silently fail. Neither the daily quest nudge nor
/// the weekly report is time-critical, so trading a little delivery slack
/// for a reminder that reliably fires without extra permissions is the
/// right call. See Android's own guidance to prefer inexact alarms for
/// anything that isn't an alarm clock or a calendar event.
const AndroidScheduleMode androidNotificationScheduleMode =
    AndroidScheduleMode.inexactAllowWhileIdle;

/// Matches [FlutterLocalNotificationsPlugin.zonedSchedule]'s signature so
/// the real method can be passed directly. Injectable so tests can record
/// the arguments a real schedule call would receive — in particular
/// [AndroidScheduleMode] — without touching platform channels.
typedef ZonedScheduleCall =
    Future<void> Function({
      required int id,
      required String title,
      required String body,
      required tz.TZDateTime scheduledDate,
      required NotificationDetails notificationDetails,
      required AndroidScheduleMode androidScheduleMode,
      DateTimeComponents? matchDateTimeComponents,
    });

/// Local (on-device) daily reminder notifications. No-op on web, where the
/// underlying plugin has no native scheduling support.
class NotificationService {
  // Deliberately not `this._timezoneIdentifierResolver`: the field is
  // private, but the constructor parameter needs a public external name so
  // tests outside this library can inject a resolver.
  NotificationService({
    TimezoneIdentifierResolver timezoneIdentifierResolver =
        _defaultTimezoneIdentifierResolver,
    @visibleForTesting ZonedScheduleCall? zonedScheduleCall,
    // ignore: prefer_initializing_formals
  }) : _timezoneIdentifierResolver = timezoneIdentifierResolver,
       // ignore: prefer_initializing_formals
       _zonedScheduleCall = zonedScheduleCall;

  static const _dailyReminderId = 1;
  static const _weeklyReportId = 2;
  static const _budgetExceededId = 3;
  static const _windowsGuid = 'f6f4d1a0-6b7a-4b0e-9c8a-6b2b6a2e0e01';

  /// 주간 리포트 알림이 울리는 요일·시각 — 한 주를 마감하는 일요일 저녁.
  static const weeklyReportWeekday = DateTime.sunday;
  static const weeklyReportHour = 20;

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  final TimezoneIdentifierResolver _timezoneIdentifierResolver;
  final ZonedScheduleCall? _zonedScheduleCall;
  bool _initialized = false;

  ZonedScheduleCall get _scheduleCall =>
      _zonedScheduleCall ?? _plugin.zonedSchedule;

  /// Throws [NotificationTimezoneException] if the device's timezone
  /// identifier can't be resolved — never silently schedules in UTC or the
  /// wrong zone. Does not request the notification permission; that only
  /// happens when actually scheduling a reminder.
  Future<void> init() async {
    if (kIsWeb || _initialized) return;

    tz_data.initializeTimeZones();
    final String identifier;
    try {
      identifier = await _timezoneIdentifierResolver();
    } on Object catch (e) {
      // The resolver (e.g. the flutter_timezone platform channel) failed
      // outright rather than returning an unresolvable identifier — still
      // surface it as a NotificationTimezoneException so callers never have
      // to distinguish "bad identifier" from "resolver blew up", and never
      // silently fall back to UTC.
      throw NotificationTimezoneException('<resolver-failed>', e);
    }
    tz.setLocalLocation(resolveTimezoneLocation(identifier));

    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const darwinSettings = DarwinInitializationSettings();
    const linuxSettings = LinuxInitializationSettings(
      defaultActionName: 'Open',
    );
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
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
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
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestNotificationsPermission();

    await scheduleDailyReminderCall(
      hour: hour,
      minute: minute,
      activeQuestCount: activeQuestCount,
    );

    // null means the platform can't report permission (iOS/desktop) — assume
    // granted rather than alarming the user for nothing.
    return granted ?? true;
  }

  /// The [_scheduleCall] invocation half of [scheduleDailyReminder], split
  /// out so tests can exercise the real scheduling logic — including the
  /// [androidNotificationScheduleMode] policy actually reaching the plugin
  /// call — without going through the OS permission-request API, which has
  /// no working platform channel in a unit-test binding.
  @visibleForTesting
  Future<void> scheduleDailyReminderCall({
    required int hour,
    required int minute,
    int activeQuestCount = 0,
  }) async {
    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    );
    if (scheduled.isBefore(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }

    final body = activeQuestCount > 0
        ? '진행중인 퀘스트가 $activeQuestCount개 있어요!'
        : '오늘의 퀘스트를 확인해보세요!';

    await _scheduleCall(
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
      androidScheduleMode: androidNotificationScheduleMode,
      matchDateTimeComponents: DateTimeComponents.time,
    );
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
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestNotificationsPermission();

    await scheduleWeeklyReportReminderCall();

    return granted ?? true;
  }

  /// The [_scheduleCall] invocation half of [scheduleWeeklyReportReminder] —
  /// see [scheduleDailyReminderCall] for why this is split out.
  @visibleForTesting
  Future<void> scheduleWeeklyReportReminderCall() async {
    final now = tz.TZDateTime.now(tz.local);
    // 다음 일요일 20:00 — DST 경계에서 시각이 밀리지 않도록 Duration 덧셈 대신
    // 달력 필드로 하루씩 재구성한다.
    var scheduled = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      weeklyReportHour,
    );
    while (scheduled.weekday != weeklyReportWeekday ||
        scheduled.isBefore(now)) {
      scheduled = tz.TZDateTime(
        tz.local,
        scheduled.year,
        scheduled.month,
        scheduled.day + 1,
        weeklyReportHour,
      );
    }

    await _scheduleCall(
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
      androidScheduleMode: androidNotificationScheduleMode,
      matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
    );
  }

  Future<void> cancelWeeklyReportReminder() async {
    if (kIsWeb) return;
    await _plugin.cancel(id: _weeklyReportId);
  }

  /// Fires immediately when this month's spending first crosses the budget.
  Future<void> showBudgetExceeded({
    required double spent,
    required double budget,
  }) async {
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
