import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:human_status/models/quest.dart';
import 'package:human_status/services/notification_action_payload.dart';
import 'package:human_status/services/notification_service.dart';
import 'package:human_status/services/storage_service.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

/// Android는 SCHEDULE_EXACT_ALARM 없이도 예약이 실제로 등록되도록
/// inexactAllowWhileIdle 정책을 써야 한다 — 이 테스트는 그 정책 상수가
/// 실제 zonedSchedule 호출 인자로 흘러가는지, 일일/주간 두 경로 모두
/// 같은 정책을 쓰는지를 (문자열 검색이 아니라) 서비스 코드 실행으로 검증한다.
///
/// 활성 퀘스트 0/1/N개에 따른 문구·액션·payload·Darwin category 분기(plan 섹션
/// 2.3/3.3)도 같은 방식(실제 `zonedSchedule` 호출 인자 캡처)으로 여기서 검증한다.
void main() {
  setUpAll(() {
    tz_data.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Seoul'));
  });

  test(
    'androidNotificationScheduleMode는 특별 권한이 필요 없는 inexactAllowWhileIdle이다',
    () {
      expect(
        androidNotificationScheduleMode,
        AndroidScheduleMode.inexactAllowWhileIdle,
      );
    },
  );

  test('일일 리마인더 스케줄 호출은 공유 정책을 실제 zonedSchedule 인자로 전달한다', () async {
    AndroidScheduleMode? capturedMode;
    final service = NotificationService(
      zonedScheduleCall:
          ({
            required int id,
            required String title,
            required String body,
            required tz.TZDateTime scheduledDate,
            required NotificationDetails notificationDetails,
            required AndroidScheduleMode androidScheduleMode,
            DateTimeComponents? matchDateTimeComponents,
            String? payload,
          }) async {
            capturedMode = androidScheduleMode;
          },
    );

    await service.scheduleDailyReminderCall(hour: 9, minute: 0);

    expect(capturedMode, androidNotificationScheduleMode);
  });

  test('주간 리포트 스케줄 호출도 동일한 공유 정책을 실제 zonedSchedule 인자로 전달한다', () async {
    AndroidScheduleMode? capturedMode;
    final service = NotificationService(
      zonedScheduleCall:
          ({
            required int id,
            required String title,
            required String body,
            required tz.TZDateTime scheduledDate,
            required NotificationDetails notificationDetails,
            required AndroidScheduleMode androidScheduleMode,
            DateTimeComponents? matchDateTimeComponents,
            String? payload,
          }) async {
            capturedMode = androidScheduleMode;
          },
    );

    await service.scheduleWeeklyReportReminderCall();

    expect(capturedMode, androidNotificationScheduleMode);
  });

  group('활성 퀘스트 개수에 따른 일일 리마인더 분기', () {
    Future<
      ({
        String body,
        String? payload,
        List<AndroidNotificationAction>? androidActions,
        String? darwinCategoryId,
      })
    >
    schedule({
      int activeQuestCount = 0,
      DailyReminderQuestTarget? completionTarget,
    }) async {
      late String capturedBody;
      String? capturedPayload;
      List<AndroidNotificationAction>? capturedActions;
      String? capturedCategoryId;

      final service = NotificationService(
        zonedScheduleCall:
            ({
              required int id,
              required String title,
              required String body,
              required tz.TZDateTime scheduledDate,
              required NotificationDetails notificationDetails,
              required AndroidScheduleMode androidScheduleMode,
              DateTimeComponents? matchDateTimeComponents,
              String? payload,
            }) async {
              capturedBody = body;
              capturedPayload = payload;
              capturedActions = notificationDetails.android?.actions;
              capturedCategoryId = notificationDetails.iOS?.categoryIdentifier;
            },
      );

      await service.scheduleDailyReminderCall(
        hour: 9,
        minute: 0,
        activeQuestCount: activeQuestCount,
        completionTarget: completionTarget,
      );

      return (
        body: capturedBody,
        payload: capturedPayload,
        androidActions: capturedActions,
        darwinCategoryId: capturedCategoryId,
      );
    }

    test('활성 퀘스트 0개: 액션/payload/category 없음', () async {
      final captured = await schedule(activeQuestCount: 0);

      expect(captured.body, '오늘의 퀘스트를 확인해보세요!');
      expect(captured.payload, isNull);
      expect(captured.androidActions, isEmpty);
      expect(captured.darwinCategoryId, isNull);
    });

    test('활성 퀘스트 2개 이상: 액션/payload/category 없음, 개수만 안내', () async {
      final captured = await schedule(activeQuestCount: 3);

      expect(captured.body, '진행중인 퀘스트가 3개 있어요!');
      expect(captured.payload, isNull);
      expect(captured.androidActions, isEmpty);
      expect(captured.darwinCategoryId, isNull);
    });

    test('활성 퀘스트 정확히 1개: 완료 액션·payload·Darwin category가 모두 붙는다', () async {
      final target = DailyReminderQuestTarget(
        questId: 'q1',
        questTitle: '아침 스트레칭',
        installationId: 'install-1',
      );
      final captured = await schedule(
        activeQuestCount: 1,
        completionTarget: target,
      );

      expect(captured.body, '아침 스트레칭을 완료했나요?');
      expect(captured.darwinCategoryId, NotificationService.dailyQuestCategoryId);

      final actions = captured.androidActions!;
      expect(actions, hasLength(1));
      expect(actions.single.id, NotificationService.completeQuestActionId);
      expect(actions.single.showsUserInterface, isFalse);
      expect(actions.single.cancelNotification, isTrue);

      final payload = DailyQuestNotificationPayload.tryParse(
        captured.payload,
      );
      expect(payload, isNotNull);
      expect(payload!.questId, 'q1');
      expect(payload.questTitle, '아침 스트레칭');
      expect(payload.installationId, 'install-1');
    });

    test('매 스케줄 호출마다 actionToken은 새로 발급된다', () async {
      final target = DailyReminderQuestTarget(
        questId: 'q1',
        questTitle: '아침 스트레칭',
        installationId: 'install-1',
      );

      final first = await schedule(activeQuestCount: 1, completionTarget: target);
      final second = await schedule(
        activeQuestCount: 1,
        completionTarget: target,
      );

      final firstToken = DailyQuestNotificationPayload.tryParse(
        first.payload,
      )!.actionToken;
      final secondToken = DailyQuestNotificationPayload.tryParse(
        second.payload,
      )!.actionToken;
      expect(firstToken, isNot(secondToken));
    });
  });

  group('kQuestCompletionNotificationActionEnabled 플래그', () {
    test('기본값은 false다 (실기기 cross-isolate 검증 전까지 fail-closed)', () {
      expect(kQuestCompletionNotificationActionEnabled, isFalse);
    });

    test('플래그가 꺼져 있으면 활성 퀘스트가 정확히 1개여도 target을 만들지 않는다', () async {
      final storage = StorageService(inMemory: true);
      await storage.init();
      addTearDown(Hive.close);
      final quest = Quest(
        id: 'q1',
        title: '아침 스트레칭',
        description: '',
        statRewards: const {'health': 10},
        createdAt: DateTime(2026, 7, 20),
      );

      final target = buildDailyReminderCompletionTarget(
        storage,
        [quest],
        actionsEnabled: false,
      );

      expect(target, isNull);
    });

    test('플래그를 켠 상태에서는 종전처럼 활성 퀘스트 1개일 때 target을 만든다', () async {
      final storage = StorageService(inMemory: true);
      await storage.init();
      addTearDown(Hive.close);
      final quest = Quest(
        id: 'q1',
        title: '아침 스트레칭',
        description: '',
        statRewards: const {'health': 10},
        createdAt: DateTime(2026, 7, 20),
      );

      final target = buildDailyReminderCompletionTarget(
        storage,
        [quest],
        actionsEnabled: true,
      );

      expect(target, isNotNull);
      expect(target!.questId, 'q1');
    });
  });
}
