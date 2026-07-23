import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:human_status/main.dart';
import 'package:human_status/models/quest.dart';
import 'package:human_status/services/auto_backup_controller.dart';
import 'package:human_status/services/backup_service.dart';
import 'package:human_status/services/daily_refresh_controller.dart';
import 'package:human_status/services/notification_service.dart';

import 'helpers/test_app.dart';

/// 실제 플러그인은 테스트 바인딩에 없으므로 스케줄 호출만 기록한다 —
/// weekly_report_toggle_test.dart와 동일한 패턴.
class _RecordingNotificationService extends NotificationService {
  final scheduleCalls = <int>[];

  @override
  Future<void> init() async {}

  @override
  Future<bool> scheduleDailyReminder({
    required int hour,
    required int minute,
    int activeQuestCount = 0,
  }) async {
    scheduleCalls.add(activeQuestCount);
    return true;
  }

  @override
  Future<bool> scheduleWeeklyReportReminder() async => true;
}

void main() {
  test('알림 예약은 startup daily refresh가 끝난 뒤의 activeQuestCount로 실행된다', () async {
    final storage = await createTestStorage();
    final profile = storage.getProfile();
    profile.reminderMinutesSinceMidnight = 9 * 60;
    await storage.saveProfile(profile);

    // 어제 완료된 반복 퀘스트 — refresh가 끝나야 active로 재생성된다.
    await storage.saveQuest(
      Quest(
        id: 'q1',
        title: '아침 스트레칭',
        description: '10분',
        statRewards: const {'health': 15},
        isRecurring: true,
        status: QuestStatus.completed,
        source: QuestSource.manual,
        createdAt: DateTime(2026, 7, 15),
        completedAt: DateTime(2026, 7, 15, 20),
      ),
    );

    final gate = Completer<void>();
    final controller = DailyRefreshController(
      storage: storage,
      clock: () => DateTime(2026, 7, 16, 9),
      respawnRecurringQuests: (now) async {
        // startup refresh가 알림 예약보다 먼저 끝나야 함을 검증하기 위해
        // 일부러 지연시킨다.
        await gate.future;
        for (final q in storage.getQuests()) {
          if (q.isRecurring && q.status == QuestStatus.completed) {
            q.isRecurring = false;
            await storage.saveQuest(q);
            await storage.saveQuest(
              Quest(
                id: '${q.id}-respawned',
                title: q.title,
                description: q.description,
                statRewards: Map.of(q.statRewards),
                isRecurring: true,
                status: QuestStatus.active,
                source: q.source,
                createdAt: now,
              ),
            );
          }
        }
      },
      refreshRecommendations: () async {},
      refreshFinancialAdvice: () async {},
    );

    final fakeNotifications = _RecordingNotificationService();
    // storage에 자동 백업이 꺼져 있는 기본값이라 backupIfDue()는 즉시 반환되는
    // no-op이다 — 이 테스트는 순전히 refresh → 알림 순서를 검증한다.
    final autoBackupController = AutoBackupController(
      storage: storage,
      backupService: BackupService(storage: storage),
    );
    final sequence = runStartupSequence(
      controller,
      storage,
      autoBackupController: autoBackupController,
      notificationService: fakeNotifications,
    );

    // refresh가 아직 gate에 막혀 끝나지 않았으므로 알림은 아직 예약되지 않아야 한다.
    await Future<void>.delayed(Duration.zero);
    expect(fakeNotifications.scheduleCalls, isEmpty);

    gate.complete();
    await sequence;

    // 알림은 respawn이 끝난 뒤, 새로 생긴 active 퀘스트를 반영해 한 번만 예약된다.
    expect(fakeNotifications.scheduleCalls, [1]);
  });
}
