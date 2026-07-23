import 'package:flutter_test/flutter_test.dart';
import 'package:human_status/services/notification_action_payload.dart';

void main() {
  DailyQuestNotificationPayload sample() => DailyQuestNotificationPayload(
    actionToken: 'token-1',
    installationId: 'install-1',
    questId: 'quest-1',
    questTitle: '아침 스트레칭',
    scheduledAt: DateTime.utc(2026, 7, 23, 9),
  );

  test('직렬화 후 역직렬화하면 원래 값과 동일하다 (round-trip)', () {
    final payload = sample();
    final parsed = DailyQuestNotificationPayload.tryParse(
      payload.toJsonString(),
    );

    expect(parsed, isNotNull);
    expect(parsed!.actionToken, payload.actionToken);
    expect(parsed.installationId, payload.installationId);
    expect(parsed.questId, payload.questId);
    expect(parsed.questTitle, payload.questTitle);
    expect(parsed.scheduledAt, payload.scheduledAt);
  });

  test('null이나 빈 문자열은 null을 반환한다', () {
    expect(DailyQuestNotificationPayload.tryParse(null), isNull);
    expect(DailyQuestNotificationPayload.tryParse(''), isNull);
  });

  test('깨진 JSON은 null을 반환한다', () {
    expect(DailyQuestNotificationPayload.tryParse('{not json'), isNull);
  });

  test('JSON이지만 객체가 아니면 null을 반환한다', () {
    expect(DailyQuestNotificationPayload.tryParse('[1,2,3]'), isNull);
    expect(DailyQuestNotificationPayload.tryParse('"just a string"'), isNull);
    expect(DailyQuestNotificationPayload.tryParse('42'), isNull);
  });

  test('알 수 없는 스키마 버전은 거부한다', () {
    final json =
        '{"v":2,"type":"dailyQuest","actionToken":"t","installationId":"i","questId":"q","questTitle":"제목","scheduledAt":"2026-07-23T00:00:00.000Z"}';
    expect(DailyQuestNotificationPayload.tryParse(json), isNull);
  });

  test('v 필드가 없으면 거부한다', () {
    final json =
        '{"type":"dailyQuest","actionToken":"t","installationId":"i","questId":"q","questTitle":"제목","scheduledAt":"2026-07-23T00:00:00.000Z"}';
    expect(DailyQuestNotificationPayload.tryParse(json), isNull);
  });

  test('알 수 없는 type은 거부한다', () {
    final json =
        '{"v":1,"type":"weeklyReport","actionToken":"t","installationId":"i","questId":"q","questTitle":"제목","scheduledAt":"2026-07-23T00:00:00.000Z"}';
    expect(DailyQuestNotificationPayload.tryParse(json), isNull);
  });

  test('actionToken이 빈 문자열이면 거부한다', () {
    final json =
        '{"v":1,"type":"dailyQuest","actionToken":"","installationId":"i","questId":"q","questTitle":"제목","scheduledAt":"2026-07-23T00:00:00.000Z"}';
    expect(DailyQuestNotificationPayload.tryParse(json), isNull);
  });

  test('installationId가 빈 문자열이면 거부한다', () {
    final json =
        '{"v":1,"type":"dailyQuest","actionToken":"t","installationId":"","questId":"q","questTitle":"제목","scheduledAt":"2026-07-23T00:00:00.000Z"}';
    expect(DailyQuestNotificationPayload.tryParse(json), isNull);
  });

  test('questId가 빈 문자열이면 거부한다', () {
    final json =
        '{"v":1,"type":"dailyQuest","actionToken":"t","installationId":"i","questId":"","questTitle":"제목","scheduledAt":"2026-07-23T00:00:00.000Z"}';
    expect(DailyQuestNotificationPayload.tryParse(json), isNull);
  });

  test('questId가 누락되면 거부한다', () {
    final json =
        '{"v":1,"type":"dailyQuest","actionToken":"t","installationId":"i","questTitle":"제목","scheduledAt":"2026-07-23T00:00:00.000Z"}';
    expect(DailyQuestNotificationPayload.tryParse(json), isNull);
  });

  test('scheduledAt이 파싱 불가능한 문자열이면 거부한다', () {
    final json =
        '{"v":1,"type":"dailyQuest","actionToken":"t","installationId":"i","questId":"q","questTitle":"제목","scheduledAt":"not-a-date"}';
    expect(DailyQuestNotificationPayload.tryParse(json), isNull);
  });

  test('필드 타입이 문자열이 아니면 거부한다 (예: questId가 숫자)', () {
    final json =
        '{"v":1,"type":"dailyQuest","actionToken":"t","installationId":"i","questId":123,"questTitle":"제목","scheduledAt":"2026-07-23T00:00:00.000Z"}';
    expect(DailyQuestNotificationPayload.tryParse(json), isNull);
  });

  test('직렬화된 JSON은 스키마 필드를 그대로 담는다', () {
    final payload = sample();
    final json = payload.toJsonString();

    expect(json, contains('"v":1'));
    expect(json, contains('"type":"dailyQuest"'));
    expect(json, contains('"questId":"quest-1"'));
  });
}
