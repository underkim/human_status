import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/user_profile.dart';
import '../../providers/profile_provider.dart';
import '../../providers/quest_provider.dart';
import '../../theme/app_colors.dart';

/// 알림 시간 + 주간 리포트 알림. 두 토글이 같은
/// `_notificationChangeInProgress` 플래그로 직렬화되어, 한쪽이 저장 중일 때
/// 다른 쪽도 비활성화된다.
class NotificationSettingsSection extends ConsumerStatefulWidget {
  const NotificationSettingsSection({super.key});

  @override
  ConsumerState<NotificationSettingsSection> createState() =>
      _NotificationSettingsSectionState();
}

class _NotificationSettingsSectionState
    extends ConsumerState<NotificationSettingsSection> {
  bool _notificationChangeInProgress = false;

  UserProfile _copyProfile(UserProfile source) => UserProfile(
    lastQuestRefresh: source.lastQuestRefresh,
    claudeApiKey: source.claudeApiKey,
    reminderMinutesSinceMidnight: source.reminderMinutesSinceMidnight,
    lastAdviceRefresh: source.lastAdviceRefresh,
    cachedAdvice: source.cachedAdvice
        .map((entry) => Map<String, dynamic>.from(entry))
        .toList(),
    weeklyReportReminderEnabled: source.weeklyReportReminderEnabled,
    onboardingCompleted: source.onboardingCompleted,
    preferredStatId: source.preferredStatId,
  );

  Future<({bool saved, bool restored})> _saveNotificationProfile({
    required WidgetRef ref,
    required UserProfile candidate,
    required Future<void> Function() compensate,
  }) async {
    final storage = ref.read(storageServiceProvider);
    // Captured before the first await: this screen can be popped (disposed)
    // while storage.saveProfile is in flight, and a disposed ConsumerState's
    // `ref` throws on any further read. The notifier itself is a plain
    // object independent of this widget's lifecycle, so calling .reload()
    // on the captured reference still safely refreshes the *global*
    // profileProvider state for every other still-mounted screen — skipping
    // the reload via a `mounted` check here would wrongly leave that global
    // state stale just because this particular screen closed first.
    final profileNotifier = ref.read(profileProvider.notifier);
    try {
      await storage.saveProfile(candidate);
    } catch (_) {
      var restored = false;
      try {
        await compensate();
        restored = true;
      } catch (_) {
        // A stronger warning below tells the user when even compensation
        // failed; the persistence error never escapes as an unhandled future.
      }
      return (saved: false, restored: restored);
    }
    profileNotifier.reload();
    return (saved: true, restored: true);
  }

  /// Shown when scheduling/cancelling a reminder throws (e.g. a platform or
  /// timezone-resolution exception) — never leaks raw exception details,
  /// and the caller is expected to leave the prior profile value untouched.
  void _showGenericNotificationError(
    BuildContext context, {
    bool restored = true,
  }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          restored
              ? '알림 설정을 변경하지 못했어요. 잠시 후 다시 시도해주세요.'
              : '알림 설정을 저장하지 못했고 이전 알림도 복원하지 못했어요. 기기 알림 설정을 확인해주세요.',
        ),
      ),
    );
  }

  Future<void> _editReminder(BuildContext context, WidgetRef ref) async {
    if (_notificationChangeInProgress) return;
    if (kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('알림은 이 플랫폼(웹)에서는 지원되지 않아요.')),
      );
      return;
    }

    setState(() => _notificationChangeInProgress = true);
    try {
      final originalProfile = _copyProfile(ref.read(profileProvider));
      final current = originalProfile.reminderMinutesSinceMidnight;

      final action = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('알림 시간'),
          content: Text(
            current != null
                ? '매일 ${(current ~/ 60).toString().padLeft(2, '0')}:${(current % 60).toString().padLeft(2, '0')}에 알림을 보내드려요. (기기 상태에 따라 몇 분 늦을 수 있어요)'
                : '진행중인 퀘스트를 알려주는 매일 알림을 설정할 수 있어요. (기기 상태에 따라 몇 분 늦을 수 있어요)',
          ),
          actions: [
            if (current != null)
              TextButton(
                onPressed: () => Navigator.pop(context, 'off'),
                child: const Text('끄기'),
              ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, 'set'),
              child: const Text('시간 설정'),
            ),
          ],
        ),
      );
      if (action == null) return;

      final notificationService = ref.read(notificationServiceProvider);
      final activeQuestCount = ref.read(activeQuestsProvider).length;

      if (action == 'off') {
        try {
          await notificationService.cancelReminder();
        } catch (_) {
          if (context.mounted) _showGenericNotificationError(context);
          return;
        }
        final candidate = _copyProfile(originalProfile)
          ..reminderMinutesSinceMidnight = null;
        final outcome = await _saveNotificationProfile(
          ref: ref,
          candidate: candidate,
          compensate: () async {
            await notificationService.scheduleDailyReminder(
              hour: current! ~/ 60,
              minute: current % 60,
              activeQuestCount: activeQuestCount,
            );
          },
        );
        if (!outcome.saved && context.mounted) {
          _showGenericNotificationError(context, restored: outcome.restored);
        }
        return;
      }

      if (!context.mounted) return;
      final initial = current != null
          ? TimeOfDay(hour: current ~/ 60, minute: current % 60)
          : TimeOfDay.now();
      final picked = await showTimePicker(
        context: context,
        initialTime: initial,
      );
      if (picked == null) return;

      final bool granted;
      try {
        granted = await notificationService.scheduleDailyReminder(
          hour: picked.hour,
          minute: picked.minute,
          activeQuestCount: activeQuestCount,
        );
      } catch (_) {
        if (context.mounted) _showGenericNotificationError(context);
        return;
      }

      final candidate = _copyProfile(originalProfile)
        ..reminderMinutesSinceMidnight = picked.hour * 60 + picked.minute;
      final outcome = await _saveNotificationProfile(
        ref: ref,
        candidate: candidate,
        compensate: () async {
          if (current == null) {
            await notificationService.cancelReminder();
          } else {
            await notificationService.scheduleDailyReminder(
              hour: current ~/ 60,
              minute: current % 60,
              activeQuestCount: activeQuestCount,
            );
          }
        },
      );
      if (!outcome.saved) {
        if (context.mounted) {
          _showGenericNotificationError(context, restored: outcome.restored);
        }
        return;
      }

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              granted
                  ? '알림 시간이 저장됐어요.'
                  : '시간은 저장됐지만 알림 권한이 꺼져 있어요 — 기기 설정에서 허용해주세요.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _notificationChangeInProgress = false);
    }
  }

  Future<void> _toggleWeeklyReport(
    BuildContext context,
    WidgetRef ref,
    bool enabled,
  ) async {
    if (_notificationChangeInProgress) return;
    setState(() => _notificationChangeInProgress = true);
    final originalProfile = _copyProfile(ref.read(profileProvider));
    final notificationService = ref.read(notificationServiceProvider);

    try {
      var granted = true;
      try {
        if (enabled) {
          granted = await notificationService.scheduleWeeklyReportReminder();
        } else {
          await notificationService.cancelWeeklyReportReminder();
        }
      } catch (_) {
        if (context.mounted) _showGenericNotificationError(context);
        return;
      }

      final candidate = _copyProfile(originalProfile)
        ..weeklyReportReminderEnabled = enabled;
      final outcome = await _saveNotificationProfile(
        ref: ref,
        candidate: candidate,
        compensate: () async {
          if (enabled) {
            await notificationService.cancelWeeklyReportReminder();
          } else {
            await notificationService.scheduleWeeklyReportReminder();
          }
        },
      );
      if (!outcome.saved) {
        if (context.mounted) {
          _showGenericNotificationError(context, restored: outcome.restored);
        }
        return;
      }

      if (context.mounted && enabled) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              granted
                  ? '일요일 20:00에 주간 리포트를 알려드릴게요.'
                  : '설정은 저장됐지만 알림 권한이 꺼져 있어요 — 기기 설정에서 허용해주세요.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _notificationChangeInProgress = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(profileProvider);
    final reminderMinutes = profile.reminderMinutesSinceMidnight;
    final reminderSubtitle = kIsWeb
        ? '이 플랫폼(웹)에서는 지원되지 않아요'
        : reminderMinutes != null
        ? '매일 ${(reminderMinutes ~/ 60).toString().padLeft(2, '0')}:${(reminderMinutes % 60).toString().padLeft(2, '0')}'
        : '꺼짐 — 탭해서 설정';

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ListTile(
          leading: const Icon(Icons.notifications_outlined),
          title: const Text('알림 시간'),
          // 알림이 켜져 있어도 OS 권한이 거부돼 있으면 실제로는 오지 않으므로,
          // 설정 화면 표시와 실제 동작이 항상 일치하도록 권한 상태를 함께 보여준다.
          subtitle: reminderMinutes != null && !kIsWeb
              ? FutureBuilder<bool?>(
                  future: ref
                      .read(notificationServiceProvider)
                      .areNotificationsEnabled(),
                  builder: (context, snap) {
                    if (snap.hasData && snap.data == false) {
                      return Text(
                        '$reminderSubtitle · 권한 꺼짐 — 기기 설정에서 허용해주세요',
                        style: TextStyle(color: context.appColors.warning),
                      );
                    }
                    return Text(reminderSubtitle);
                  },
                )
              : Text(reminderSubtitle),
          enabled: !_notificationChangeInProgress,
          onTap: _notificationChangeInProgress
              ? null
              : () => _editReminder(context, ref),
        ),
        SwitchListTile(
          secondary: const Icon(Icons.summarize_outlined),
          title: const Text('주간 리포트 알림'),
          subtitle: Text(
            kIsWeb ? '이 플랫폼(웹)에서는 지원되지 않아요' : '일요일 20:00에 한 주 활동 요약을 알려드려요',
          ),
          value: profile.weeklyReportReminderEnabled && !kIsWeb,
          onChanged: kIsWeb || _notificationChangeInProgress
              ? null
              : (v) => _toggleWeeklyReport(context, ref, v),
        ),
      ],
    );
  }
}
