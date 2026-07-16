import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:human_status/services/notification_service.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

/// Android는 SCHEDULE_EXACT_ALARM 없이도 예약이 실제로 등록되도록
/// inexactAllowWhileIdle 정책을 써야 한다 — 이 테스트는 그 정책 상수가
/// 실제 zonedSchedule 호출 인자로 흘러가는지, 일일/주간 두 경로 모두
/// 같은 정책을 쓰는지를 (문자열 검색이 아니라) 서비스 코드 실행으로 검증한다.
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
          }) async {
            capturedMode = androidScheduleMode;
          },
    );

    await service.scheduleWeeklyReportReminderCall();

    expect(capturedMode, androidNotificationScheduleMode);
  });
}
