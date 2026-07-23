import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/widgets.dart' show WidgetsFlutterBinding;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/profile_provider.dart' show storageServiceProvider;
import '../providers/quest_provider.dart';
import 'notification_action_payload.dart';
import 'notification_service.dart';
import 'quest_completion_execution_lock.dart';
import 'storage_service.dart';

/// Creates and initializes the [StorageService] a background/foreground
/// notification-action dispatch uses. Injectable so tests can substitute an
/// in-memory instance instead of touching real Hive/plugin state — mirrors
/// `main.dart`'s `StorageInitializer` pattern.
typedef NotificationActionStorageFactory = Future<StorageService> Function();

Future<StorageService> _defaultCreateStorage() async {
  final storage = StorageService();
  await storage.init();
  return storage;
}

/// The real Android/iOS entry point registered as
/// `onDidReceiveBackgroundNotificationResponse` in
/// `NotificationService.init()`. Must stay a top-level function (not a
/// closure/instance method) and keep this exact `@pragma` — the plugin looks
/// this callback up by a persistent handle that only works for a top-level
/// or static function, and release builds would otherwise tree-shake it away
/// since nothing else appears to call it directly.
///
/// This can only ever be exercised for real on an Android/iOS device or
/// emulator running two Flutter engines — not available in this
/// environment. See `dispatchNotificationResponse`, which contains the
/// actual, unit-testable logic; this wrapper only adds the
/// binding-initialization step a background isolate needs and that
/// `dispatchNotificationResponse` itself must not assume has already
/// happened (plan section 4.2 step 1).
@pragma('vm:entry-point')
Future<void> notificationTapBackground(NotificationResponse response) async {
  WidgetsFlutterBinding.ensureInitialized();
  await dispatchNotificationResponse(response);
}

/// The single dispatch point for a notification action response, shared by
/// the background entry point above and the foreground
/// `onDidReceiveNotificationResponse` callback wired in `main.dart` — see
/// plan section 4.1's "동일 dispatcher를 거치게 해 테스트 가능한 단일 분기점으로
/// 만든다".
///
/// Every branch below is a deliberate no-op rather than an error for a large
/// class of "nothing to do" cases (plan section 4.5/7): a response for a
/// different action, an unparseable/foreign/stale payload, an
/// already-completed or deleted quest, or a duplicate delivery of an
/// already-processed or still-in-flight action token. Storage is never even
/// opened for the fast no-ops (wrong actionId, unparseable payload) — see
/// plan section 4.1.
///
/// **Storage ownership differs by call site.** [StorageService.close] closes
/// every Hive box open in the current isolate ([Hive.close] — see that
/// method's doc comment), not just the boxes this particular instance
/// opened, because Hive's box registry is a single isolate-wide singleton.
/// The background entry point above runs in its own throwaway isolate, so
/// this is harmless there. But `main.dart`'s foreground callback runs in the
/// *same* isolate as the already-running app, sharing that isolate's Hive
/// singleton with the app's own long-lived `StorageService` — if this
/// function opened a fresh instance there and closed it as usual, it would
/// close the boxes the live app UI is still holding references to,
/// corrupting the running app. So the foreground call site passes
/// `createStorage: () async => <the app's existing StorageService>` (never
/// opening a second one) together with `closeStorage: false` (never closing
/// an instance it doesn't own). Only the background path uses the defaults.
Future<void> dispatchNotificationResponse(
  NotificationResponse response, {
  NotificationActionStorageFactory createStorage = _defaultCreateStorage,
  NotificationService? notificationService,
  // Lets tests force a completion failure (e.g. a statsProvider override
  // that throws) without needing a seam into every provider individually —
  // same purpose as completion_reward_integrity_test.dart's overrides, just
  // reachable from this headless entry point too.
  @visibleForTesting List<Override> containerOverrides = const [],
  // Master switch (see [kQuestCompletionNotificationActionEnabled]) — while
  // `false`, this is an immediate no-op: no storage is opened, no payload is
  // inspected further, nothing is scheduled or completed. Both the
  // background entry point and main.dart's foreground callback stay wired
  // unconditionally; this flag is what actually keeps them inert until the
  // feature has passed its real-device Go/No-Go check.
  bool actionsEnabled = kQuestCompletionNotificationActionEnabled,
  // Whether this call owns [createStorage]'s result and must close it when
  // done. Must be `false` when [createStorage] hands back a StorageService
  // someone else still owns (e.g. main.dart's foreground callback reusing
  // the app's single long-lived instance) — see this file's foreground vs.
  // background doc comment above. Defaults to `true`, matching the
  // background entry point, which always opens its own throwaway instance.
  bool closeStorage = true,
}) async {
  if (!actionsEnabled) return;
  if (response.actionId != NotificationService.completeQuestActionId) return;

  final payload = DailyQuestNotificationPayload.tryParse(response.payload);
  if (payload == null) return;

  final service = notificationService ?? NotificationService();
  StorageService? storage;
  try {
    storage = await createStorage();

    // A payload scheduled by a previous install (e.g. a lingering OS
    // notification surviving an uninstall/reinstall) must never act on this
    // install's data.
    if (storage.installationId != payload.installationId) return;

    final now = DateTime.now().toUtc();
    final existing = storage.getActionTokenRecord(payload.actionToken);
    if (existing != null) {
      if (existing.status == ActionTokenStatus.completed) return;
      if (existing.status == ActionTokenStatus.processing &&
          now.difference(existing.at) <
              StorageService.actionTokenProcessingExpiry) {
        // Still (probably) being handled by another in-flight delivery of
        // the same action token — ignore this redelivery rather than racing
        // it. A genuinely expired `processing` mark (the earlier attempt
        // died without ever recording an outcome) falls through instead, so
        // the quest's *current* status still gets re-validated below rather
        // than being silently ignored forever.
        return;
      }
    }

    await storage.recordActionToken(
      payload.actionToken,
      ActionTokenStatus.processing,
      now,
    );

    QuestCompletionResult result;
    try {
      // Reuses QuestsNotifier.completeQuest() verbatim in a headless
      // container — see plan section 4.3. completeQuest() itself acquires
      // questCompletionExecutionLockProvider before rewardLockProvider, so
      // this call is already subject to the same cross-entry-point
      // execution lock as the UI path; nothing extra is needed here.
      final container = ProviderContainer(
        overrides: [
          storageServiceProvider.overrideWithValue(storage),
          ...containerOverrides,
        ],
      );
      try {
        result = await container
            .read(questsProvider.notifier)
            .completeQuest(payload.questId);
      } finally {
        container.dispose();
      }
    } catch (error) {
      await storage.recordActionToken(
        payload.actionToken,
        ActionTokenStatus.failed,
        DateTime.now().toUtc(),
      );
      await _showFailure(
        service,
        lockTimedOut: error is QuestCompletionLockTimeoutException,
      );
      return;
    }

    await storage.recordActionToken(
      payload.actionToken,
      ActionTokenStatus.completed,
      DateTime.now().toUtc(),
    );

    if (!result.didComplete) {
      await service.showQuestCompletionResult(
        title: '퀘스트 상태를 확인했어요',
        body: '이미 완료되었거나 삭제된 퀘스트예요.',
      );
      return;
    }

    final content = buildQuestCompletionNotificationContent(
      storage: storage,
      questId: payload.questId,
      questTitleFallback: payload.questTitle,
      result: result,
    );
    await service.showQuestCompletionResult(
      title: content.title,
      body: content.body,
    );

    await rescheduleDailyReminderFromStorage(
      storage,
      notificationService: service,
      actionsEnabled: actionsEnabled,
    );
  } catch (_) {
    await _showFailure(service, lockTimedOut: false);
  } finally {
    if (closeStorage) await storage?.close();
  }
}

Future<void> _showFailure(
  NotificationService service, {
  required bool lockTimedOut,
}) async {
  try {
    await service.showQuestCompletionResult(
      title: '완료 처리하지 못했어요',
      body: lockTimedOut
          ? '처리하지 못했습니다. 앱에서 확인해 주세요.'
          : '데이터는 임의로 변경하지 않았습니다. 앱에서 다시 시도해 주세요.',
    );
  } catch (_) {
    // Feedback delivery failing must never be treated as the completion
    // transaction itself failing (plan section 4.5's edge case table) — it
    // already either committed or didn't, above; there is nothing left to
    // roll back here.
  }
}

/// Pre-formatted title/body for [NotificationService.showQuestCompletionResult].
class QuestCompletionNotificationContent {
  const QuestCompletionNotificationContent({
    required this.title,
    required this.body,
  });

  final String title;
  final String body;
}

/// Maps a successful [QuestCompletionResult] to the result-notification text
/// described in plan section 5. Re-reads the quest's *current* title from
/// [storage] by [questId] (it may have been renamed since this notification
/// was scheduled) and only falls back to [questTitleFallback] — the
/// payload's display-only snapshot — if the record can no longer be read at
/// all (defensive; shouldn't happen right after `didComplete: true`).
QuestCompletionNotificationContent buildQuestCompletionNotificationContent({
  required StorageService storage,
  required String questId,
  required String questTitleFallback,
  required QuestCompletionResult result,
}) {
  final currentTitle = storage.getQuest(questId)?.title ?? questTitleFallback;

  final levelUpEntries = result.levelUps.entries
      .where((e) => e.value.levelsGained > 0)
      .toList();
  final goalLevelUpGained =
      (result.goalCompletion?.levelUp.levelsGained ?? 0) > 0;
  final hasLevelUp = levelUpEntries.isNotEmpty || goalLevelUpGained;
  final hasAchievement = result.newAchievements.isNotEmpty;
  final hasGoal = result.goalCompletion != null;

  final eventCount = [
    hasLevelUp,
    hasAchievement,
    hasGoal,
  ].where((b) => b).length;

  if (eventCount == 0) {
    return QuestCompletionNotificationContent(
      title: '퀘스트 완료!',
      body: '"$currentTitle"을 완료하고 XP를 받았어요.',
    );
  }

  if (eventCount == 1 && hasLevelUp) {
    final summary = levelUpEntries
        .map((e) {
          final name = storage.getStat(e.key)?.name ?? e.key;
          return '$name 레벨 ${e.value.newLevel}';
        })
        .join(', ');
    return QuestCompletionNotificationContent(
      title: '퀘스트 완료 · 레벨업!',
      body: '${summary.isEmpty ? '레벨업했어요.' : '$summary.'} 앱을 열어 확인하세요.',
    );
  }

  if (eventCount == 1 && hasAchievement) {
    final summary = result.newAchievements.length == 1
        ? result.newAchievements.single.title
        : '새 업적 ${result.newAchievements.length}개';
    return QuestCompletionNotificationContent(
      title: '퀘스트 완료 · 새 업적!',
      body: '$summary. 앱을 열어 확인하세요.',
    );
  }

  if (eventCount == 1 && hasGoal) {
    return const QuestCompletionNotificationContent(
      title: '퀘스트 완료 · 목표 달성!',
      body: '연결된 목표를 달성했어요. 앱을 열어 확인하세요.',
    );
  }

  final parts = <String>[];
  if (hasLevelUp) {
    final count = levelUpEntries.length + (goalLevelUpGained ? 1 : 0);
    parts.add('레벨업 $count개');
  }
  if (hasAchievement) parts.add('새 업적 ${result.newAchievements.length}개');
  if (hasGoal) parts.add('목표 완료');
  return QuestCompletionNotificationContent(
    title: '퀘스트 완료!',
    body: parts.join(' · '),
  );
}
