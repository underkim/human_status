import 'dart:convert';

/// Payload `type` value for the single-active-quest daily reminder. The only
/// type this schema currently defines — see
/// `docs/plans/phase4_notification_action_plan.md` section 3.2.
const dailyQuestNotificationPayloadType = 'dailyQuest';

/// Current payload schema version. Bump this (and add a migration/rejection
/// branch in [DailyQuestNotificationPayload.tryParse]) before ever changing
/// the JSON shape below — an old, still-pending OS-scheduled notification can
/// carry an old-version payload long after an app update.
const dailyQuestNotificationPayloadVersion = 1;

/// The typed, validated contents of a single-active-quest daily reminder's
/// notification payload.
///
/// Only [questId] (cross-checked against current Hive state) and
/// [installationId] (cross-checked against the current install) are trusted
/// for anything that mutates state. [questTitle] is a display-only fallback
/// snapshot — never a storage key — because the quest may have been renamed
/// or deleted since this payload was scheduled. This type deliberately never
/// carries XP/reward values or a completion flag: those are always
/// recomputed from current storage, never taken from the payload.
class DailyQuestNotificationPayload {
  const DailyQuestNotificationPayload({
    required this.actionToken,
    required this.installationId,
    required this.questId,
    required this.questTitle,
    required this.scheduledAt,
  });

  /// Identifies one specific delivery of this action, so a redelivered or
  /// double-tapped OS notification can be recognized and deduped by the
  /// handler instead of re-running the completion transaction.
  final String actionToken;

  /// Must match [StorageService.installationId] at handling time. A payload
  /// scheduled by a previous install (rare: an old lingering OS notification
  /// surviving an uninstall/reinstall) is discarded rather than acted on.
  final String installationId;

  /// The only value ever used to look up and mutate storage.
  final String questId;

  /// Display-only fallback for a result notification if the quest can no
  /// longer be read from storage by the time this is handled.
  final String questTitle;

  /// When this payload was built (UTC) — diagnostic only, never used to
  /// gate/validate completion.
  final DateTime scheduledAt;

  String toJsonString() => jsonEncode({
    'v': dailyQuestNotificationPayloadVersion,
    'type': dailyQuestNotificationPayloadType,
    'actionToken': actionToken,
    'installationId': installationId,
    'questId': questId,
    'questTitle': questTitle,
    'scheduledAt': scheduledAt.toUtc().toIso8601String(),
  });

  /// Parses and validates [raw]. Returns `null` — never throws — for
  /// anything that doesn't match this exact schema: malformed JSON, a
  /// non-object root, an unrecognized/missing `v`/`type`, or a blank
  /// `actionToken`/`installationId`/`questId`. Callers must treat a `null`
  /// result as "do nothing", not as an error to surface loudly — a stale or
  /// foreign payload is an expected, unremarkable case (see plan section
  /// 3.2's edge cases), not a bug.
  static DailyQuestNotificationPayload? tryParse(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return null;
    }
    if (decoded is! Map) return null;

    if (decoded['v'] != dailyQuestNotificationPayloadVersion) return null;
    if (decoded['type'] != dailyQuestNotificationPayloadType) return null;

    final actionToken = decoded['actionToken'];
    final installationId = decoded['installationId'];
    final questId = decoded['questId'];
    final questTitle = decoded['questTitle'];
    final scheduledAtRaw = decoded['scheduledAt'];
    if (actionToken is! String || actionToken.isEmpty) return null;
    if (installationId is! String || installationId.isEmpty) return null;
    if (questId is! String || questId.isEmpty) return null;
    if (questTitle is! String) return null;
    if (scheduledAtRaw is! String) return null;

    final scheduledAt = DateTime.tryParse(scheduledAtRaw);
    if (scheduledAt == null) return null;

    return DailyQuestNotificationPayload(
      actionToken: actionToken,
      installationId: installationId,
      questId: questId,
      questTitle: questTitle,
      scheduledAt: scheduledAt,
    );
  }
}
