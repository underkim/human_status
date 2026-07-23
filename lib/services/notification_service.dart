import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;
import 'package:uuid/uuid.dart';

import '../models/quest.dart';
import '../utils/formatters.dart';
import 'notification_action_payload.dart';
import 'storage_service.dart';

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
      String? payload,
    });

/// The single active quest a daily reminder should offer an immediate
/// "complete" action for. Only ever built when exactly one quest is active
/// at schedule time — see plan section 2.3 — and folds in
/// [StorageService.installationId] so [scheduleDailyReminderCall] has
/// everything it needs to build a [DailyQuestNotificationPayload] without
/// also depending on [StorageService] itself.
class DailyReminderQuestTarget {
  const DailyReminderQuestTarget({
    required this.questId,
    required this.questTitle,
    required this.installationId,
  });

  final String questId;
  final String questTitle;
  final String installationId;
}

/// Builds the [DailyReminderQuestTarget] a daily reminder should carry for
/// [activeQuests] — non-null only when there's exactly one, per plan section
/// 2.3 ("0개: 액션 없음. 1개: 완료 액션 노출. 2개 이상: 액션 없음, 앱에서 선택하도록 안내").
///
/// [actionsEnabled] gates the whole feature (see
/// [kQuestCompletionNotificationActionEnabled]) — while `false`, this always
/// returns `null` regardless of the active-quest count, so
/// `scheduleDailyReminderCall` never attaches an action/category/payload.
/// Defaults to the compile-time flag; tests override it explicitly to
/// exercise both states without flipping the production default.
DailyReminderQuestTarget? buildDailyReminderCompletionTarget(
  StorageService storage,
  List<Quest> activeQuests, {
  bool actionsEnabled = kQuestCompletionNotificationActionEnabled,
}) {
  if (!actionsEnabled) return null;
  if (activeQuests.length != 1) return null;
  final quest = activeQuests.single;
  return DailyReminderQuestTarget(
    questId: quest.id,
    questTitle: quest.title,
    installationId: storage.installationId,
  );
}

// ============================================================================
// WARNING — DO NOT flip this to `true` without first passing the real-device
// cross-isolate Go/No-Go check required by
// docs/plans/phase4_notification_action_plan.md section 4.4 (two Flutter
// engines/isolates writing the same Hive files, verified on an actual
// Android and iOS device/emulator — never available in this environment).
// Until that check has passed, this MUST stay `false`.
// ============================================================================
/// Master switch for the whole Phase 4 "complete quest from notification"
/// feature: attaching the completion action/category/payload to the daily
/// reminder ([buildDailyReminderCompletionTarget]) and processing that
/// action in the background/foreground dispatcher
/// (`dispatchNotificationResponse`). Fail-closed default — while `false`,
/// the daily reminder only ever gets the existing count-based body, no
/// action/category/payload is ever attached, and the dispatcher no-ops
/// immediately without touching storage. See plan section 11 ("롤백") for
/// the rollback story this flag exists to support.
const bool kQuestCompletionNotificationActionEnabled = false;

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

  /// Public (not `_`-prefixed) — shared with `notification_action_handler.dart`
  /// and its tests, which need to know exactly which id the daily reminder
  /// uses to cancel/reschedule it. See plan section 3.1.
  static const dailyReminderNotificationId = 1;
  static const _weeklyReportId = 2;
  static const _budgetExceededId = 3;
  static const _autoBackupFailedId = 4;
  /// A result notification for a notification-action quest completion. Never
  /// collides with the four ids above.
  static const questCompletionConfirmationNotificationId = 5;
  static const _windowsGuid = 'f6f4d1a0-6b7a-4b0e-9c8a-6b2b6a2e0e01';

  /// The Android notification action id for "오늘의 퀘스트 완료", shared by the
  /// scheduler (which attaches it to a single-target daily reminder) and the
  /// handler (which checks `NotificationResponse.actionId` against it).
  static const completeQuestActionId = 'complete_quest';

  /// The Darwin (iOS/macOS) notification category carrying
  /// [completeQuestActionId] — see plan section 3.3.
  static const dailyQuestCategoryId = 'daily_quest_single';

  /// 주간 리포트 알림이 울리는 요일·시각 — 한 주를 마감하는 일요일 저녁.
  static const weeklyReportWeekday = DateTime.sunday;
  static const weeklyReportHour = 20;

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  final TimezoneIdentifierResolver _timezoneIdentifierResolver;
  final ZonedScheduleCall? _zonedScheduleCall;
  // `static`, not per-instance: the underlying [FlutterLocalNotificationsPlugin]
  // is itself a process-wide singleton (see its `factory` constructor), so a
  // second `NotificationService()` instance calling `init()` again must still
  // be recognized as "already initialized" — otherwise a bare, callback-less
  // `init()` call from an unrelated code path (e.g. `showBudgetExceeded` on a
  // fresh instance) could silently re-run `_plugin.initialize()` and drop the
  // background/foreground notification-response callbacks registered by the
  // first, real init.
  static bool _initialized = false;

  ZonedScheduleCall get _scheduleCall =>
      _zonedScheduleCall ?? _plugin.zonedSchedule;

  /// Throws [NotificationTimezoneException] if the device's timezone
  /// identifier can't be resolved — never silently schedules in UTC or the
  /// wrong zone. Does not request the notification permission; that only
  /// happens when actually scheduling a reminder.
  ///
  /// [onDidReceiveNotificationResponse]/[onDidReceiveBackgroundNotificationResponse]
  /// are only ever actually registered on the *first* call to reach this
  /// point (see [_initialized]'s doc comment) — production wires the real
  /// dispatcher/background entry point from `main.dart`'s startup sequence,
  /// which always runs before any other code path can call [init] with no
  /// callbacks and win the race. Both default to `null` (no dispatch), which
  /// is what every existing call site that doesn't care about notification
  /// actions continues to get.
  Future<void> init({
    DidReceiveNotificationResponseCallback? onDidReceiveNotificationResponse,
    DidReceiveBackgroundNotificationResponseCallback?
    onDidReceiveBackgroundNotificationResponse,
  }) async {
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
    // The single-active-quest daily reminder is the only notification that
    // ever attaches `dailyQuestCategoryId` (see scheduleDailyReminderCall) —
    // registering it here is required by the plugin regardless (Darwin
    // categories/actions must be declared up front at init time, see
    // DarwinInitializationSettings.notificationCategories's doc comment on
    // immutability). `DarwinNotificationActionOption.foreground` is
    // deliberately never included, so tapping the action never brings the
    // app to the foreground (plan section 3.3).
    // Not `const`: DarwinNotificationAction.plain is a factory constructor.
    final darwinSettings = DarwinInitializationSettings(
      notificationCategories: [
        DarwinNotificationCategory(
          dailyQuestCategoryId,
          actions: [
            DarwinNotificationAction.plain(
              completeQuestActionId,
              '오늘의 퀘스트 완료',
            ),
          ],
        ),
      ],
    );
    const linuxSettings = LinuxInitializationSettings(
      defaultActionName: 'Open',
    );
    const windowsSettings = WindowsInitializationSettings(
      appName: 'Human Status',
      appUserModelId: 'com.humanstatus.app',
      guid: _windowsGuid,
    );

    await _plugin.initialize(
      settings: InitializationSettings(
        android: androidSettings,
        iOS: darwinSettings,
        macOS: darwinSettings,
        linux: linuxSettings,
        windows: windowsSettings,
      ),
      onDidReceiveNotificationResponse: onDidReceiveNotificationResponse,
      onDidReceiveBackgroundNotificationResponse:
          onDidReceiveBackgroundNotificationResponse,
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
  /// notification body reflects how many quests are currently active, and —
  /// only when [completionTarget] is given (exactly one active quest, see
  /// [buildDailyReminderCompletionTarget]) — offers a "오늘의 퀘스트 완료" action
  /// that completes it without opening the app (plan section 2.3).
  ///
  /// Returns false when the user denied the notification permission — the
  /// alarm is still registered, but the OS will silently swallow it, so
  /// callers should surface a warning instead of claiming success.
  Future<bool> scheduleDailyReminder({
    required int hour,
    required int minute,
    int activeQuestCount = 0,
    DailyReminderQuestTarget? completionTarget,
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
      completionTarget: completionTarget,
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
    DailyReminderQuestTarget? completionTarget,
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

    final String body;
    String? payload;
    List<AndroidNotificationAction> actions = const [];
    String? categoryIdentifier;

    if (completionTarget != null) {
      body = '${completionTarget.questTitle}을 완료했나요?';
      payload = DailyQuestNotificationPayload(
        actionToken: const Uuid().v4(),
        installationId: completionTarget.installationId,
        questId: completionTarget.questId,
        questTitle: completionTarget.questTitle,
        scheduledAt: DateTime.now().toUtc(),
      ).toJsonString();
      actions = const [
        AndroidNotificationAction(
          completeQuestActionId,
          '오늘의 퀘스트 완료',
          showsUserInterface: false,
          cancelNotification: true,
        ),
      ];
      categoryIdentifier = dailyQuestCategoryId;
    } else if (activeQuestCount > 0) {
      body = '진행중인 퀘스트가 $activeQuestCount개 있어요!';
    } else {
      body = '오늘의 퀘스트를 확인해보세요!';
    }

    await _scheduleCall(
      id: dailyReminderNotificationId,
      title: 'Human Status',
      body: body,
      scheduledDate: scheduled,
      payload: payload,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          'daily_reminder',
          '일일 리마인더',
          channelDescription: '매일 정해진 시간에 퀘스트를 알려드려요.',
          actions: actions,
        ),
        iOS: DarwinNotificationDetails(categoryIdentifier: categoryIdentifier),
        macOS: const DarwinNotificationDetails(),
        linux: const LinuxNotificationDetails(),
      ),
      androidScheduleMode: androidNotificationScheduleMode,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  Future<void> cancelReminder() async {
    if (kIsWeb) return;
    await _plugin.cancel(id: dailyReminderNotificationId);
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

  /// Fires immediately when an automatic backup attempt fails. This is an
  /// at-the-moment-of-failure ping, not a scheduled task — it has nothing to
  /// do with `zonedSchedule()` and never runs the backup itself.
  /// [AutoBackupController] throttles repeat calls (at most once per 24h per
  /// plan section 3.3), so this method itself fires unconditionally each
  /// time it's called.
  Future<void> showAutoBackupFailed() async {
    if (kIsWeb) return;
    await init();
    await _plugin.show(
      id: _autoBackupFailedId,
      title: '자동 백업 실패',
      body: '자동 백업에 실패했어요. 설정에서 백업 폴더를 확인해주세요.',
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'auto_backup_failed',
          '자동 백업 실패',
          channelDescription: '자동 백업이 실패하면 알려드려요.',
        ),
        iOS: DarwinNotificationDetails(),
        macOS: DarwinNotificationDetails(),
        linux: LinuxNotificationDetails(),
      ),
    );
  }

  /// Reports the outcome of a notification-action quest completion — see
  /// plan section 5. [title]/[body] are fully pre-formatted by the caller
  /// (`notification_action_handler.dart`, which knows about stats/
  /// achievements/goals); this method only renders them, deliberately
  /// without ever attaching [completeQuestActionId]/[dailyQuestCategoryId] —
  /// a result notification must never itself offer a completion action.
  Future<void> showQuestCompletionResult({
    required String title,
    required String body,
  }) async {
    if (kIsWeb) return;
    await init();
    await _plugin.show(
      id: questCompletionConfirmationNotificationId,
      title: title,
      body: body,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'quest_action_result',
          '퀘스트 액션 결과',
          channelDescription: '알림에서 완료한 퀘스트의 처리 결과를 알려드려요.',
        ),
        iOS: DarwinNotificationDetails(),
        macOS: DarwinNotificationDetails(),
        linux: LinuxNotificationDetails(),
      ),
    );
  }
}

/// Rebuilds the daily reminder's active-quest snapshot from current storage
/// and reschedules it under the same [NotificationService.dailyReminderNotificationId],
/// or leaves it alone if no reminder time is configured. Never throws — a
/// reschedule (whether after a background completion or at app startup) must
/// never surface as a user-facing error for something already successful.
///
/// Shared by `main.dart`'s startup sequence and
/// `notification_action_handler.dart`'s post-completion reschedule (plan
/// section 2.4 point 3), so both build the exact same snapshot the same way.
///
/// [actionsEnabled] is forwarded to [buildDailyReminderCompletionTarget] —
/// defaults to the compile-time [kQuestCompletionNotificationActionEnabled]
/// flag, so a reschedule triggered while the feature is disabled never
/// re-attaches the completion action either.
Future<void> rescheduleDailyReminderFromStorage(
  StorageService storage, {
  NotificationService? notificationService,
  bool actionsEnabled = kQuestCompletionNotificationActionEnabled,
}) async {
  try {
    final profile = storage.getProfile();
    final reminderMinutes = profile.reminderMinutesSinceMidnight;
    if (reminderMinutes == null) return;

    final service = notificationService ?? NotificationService();
    final activeQuests = storage
        .getQuests()
        .where((q) => q.status == QuestStatus.active)
        .toList();
    await service.scheduleDailyReminder(
      hour: reminderMinutes ~/ 60,
      minute: reminderMinutes % 60,
      activeQuestCount: activeQuests.length,
      completionTarget: buildDailyReminderCompletionTarget(
        storage,
        activeQuests,
        actionsEnabled: actionsEnabled,
      ),
    );
  } catch (_) {
    // Best-effort — see doc comment above.
  }
}
