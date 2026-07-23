import 'dart:async';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../services/auto_backup_controller.dart';
import '../services/daily_refresh_controller.dart';
import '../services/notification_action_handler.dart';
import '../services/notification_service.dart';
import '../services/storage_service.dart';

/// Runs the startup refresh to completion before scheduling notifications,
/// so the reminder's active-quest count reflects post-respawn state rather
/// than a stale pre-refresh snapshot. [notificationService] is injectable
/// so tests can substitute a fake instead of hitting the real platform
/// plugin (mirrors [DailyRefreshController]'s pattern for its own steps).
///
/// [autoBackupController] runs an automatic backup here (opportunistically,
/// only if one is due) right after the refresh — the one of the plan's two
/// trigger points that happens at app startup; the other is
/// `AppLifecycleState.resumed`, handled directly in
/// `_HumanStatusAppState.didChangeAppLifecycleState`. A failure here is
/// already handled internally by the controller (recorded, optionally
/// notified) and must never fail startup, so it's deliberately not wrapped
/// in a try/catch that would swallow a *different* real bug — the
/// controller itself guarantees it never throws.
Future<void> runStartupSequence(
  DailyRefreshController refreshController,
  StorageService storage, {
  required AutoBackupController autoBackupController,
  NotificationService? notificationService,
}) async {
  await refreshController.refreshIfDue();
  await autoBackupController.backupIfDue();
  await scheduleNotifications(
    storage,
    notificationService: notificationService,
  );
}

/// Routes a foreground notification tap/action through the same
/// `dispatchNotificationResponse` the background entry point uses (plan
/// section 4.1) — a plain body tap (no `actionId`) is a no-op here exactly
/// like the background path, since opening the app is already the OS's
/// default behavior for tapping a notification and needs no extra code.
/// Fire-and-forget: the plugin's callback type is synchronous (`void
/// Function(NotificationResponse)`), so the dispatch's own `Future` is
/// intentionally not awaited here.
///
/// Unlike the background entry point, this reuses [storage] — the single
/// long-lived instance the running app is already built on — instead of
/// opening a new one, and never closes it. This callback fires in the same
/// isolate as the rest of the running app, so a fresh `StorageService` that
/// later called `close()` (as the background path does) would tear down the
/// Hive singleton the live app UI still depends on. See
/// `dispatchNotificationResponse`'s doc comment for the full explanation.
void _dispatchForegroundNotificationResponse(
  NotificationResponse response,
  StorageService storage,
) {
  unawaited(
    dispatchNotificationResponse(
      response,
      createStorage: () async => storage,
      closeStorage: false,
    ),
  );
}

/// Registers the notification-action dispatcher (both the foreground
/// callback and the background entry point, see
/// `notification_action_handler.dart`) and (re)schedules the daily reminder
/// and weekly report from current storage. This is always the first code
/// path to call [NotificationService.init] each app run — see that method's
/// doc comment on why callback registration depends on that ordering.
Future<void> scheduleNotifications(
  StorageService storage, {
  NotificationService? notificationService,
}) async {
  try {
    final service = notificationService ?? NotificationService();
    await service.init(
      onDidReceiveNotificationResponse: (response) =>
          _dispatchForegroundNotificationResponse(response, storage),
      onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
    );
    await rescheduleDailyReminderFromStorage(
      storage,
      notificationService: service,
    );
    final profile = storage.getProfile();
    if (profile.weeklyReportReminderEnabled) {
      await service.scheduleWeeklyReportReminder();
    }
  } catch (_) {}
}
