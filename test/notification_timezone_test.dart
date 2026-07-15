import 'package:flutter_test/flutter_test.dart';
import 'package:human_status/services/notification_service.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

/// resolveTimezoneLocation is a pure function over IANA identifier strings,
/// so these tests never need to invoke the flutter_timezone platform
/// channel to prove correct device-timezone resolution.
void main() {
  late tz.Location originalLocal;

  setUpAll(() {
    tz_data.initializeTimeZones();
  });

  setUp(() {
    // Restore the global tz.local between tests so a failing/succeeding
    // case in one test can never leak into another.
    originalLocal = tz.local;
  });

  tearDown(() {
    tz.setLocalLocation(originalLocal);
  });

  test('Asia/Seoul 식별자는 tz.local을 정확히 설정한다', () {
    final location = resolveTimezoneLocation('Asia/Seoul');
    tz.setLocalLocation(location);

    expect(tz.local.name, 'Asia/Seoul');
    // KST has no DST and is a flat UTC+9.
    final date = tz.TZDateTime(tz.local, 2026, 7, 16, 9);
    expect(date.timeZoneOffset, const Duration(hours: 9));
  });

  test('DST가 있는 지역(America/New_York)도 실제 오프셋 전환과 함께 정상적으로 해석된다', () {
    final location = resolveTimezoneLocation('America/New_York');
    tz.setLocalLocation(location);

    expect(tz.local.name, 'America/New_York');
    final winter = tz.TZDateTime(tz.local, 2026, 1, 15);
    final summer = tz.TZDateTime(tz.local, 2026, 7, 15);
    expect(winter.timeZoneOffset, const Duration(hours: -5));
    expect(summer.timeZoneOffset, const Duration(hours: -4));
  });

  test('알 수 없는 식별자는 UTC/기존 지역으로 몰래 대체되지 않고 예외를 던진다', () {
    final before = tz.local;

    expect(
      () => resolveTimezoneLocation('Not/AZone'),
      throwsA(isA<NotificationTimezoneException>()),
    );
    // A failed resolution must never mutate the global default as a side
    // effect — the exception is the only thing that happens.
    expect(tz.local, same(before));
  });
}
