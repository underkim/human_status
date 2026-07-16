import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Android는 일반 리마인더에 exact alarm 대신 inexact alarm을 권장하고,
/// SCHEDULE_EXACT_ALARM은 Android 13+ 신규 설치에 기본 허용되지 않는다.
/// NotificationService가 inexactAllowWhileIdle만 쓰므로(see
/// notification_schedule_mode_test.dart) 이 특별 권한을 선언하면 안 되고,
/// 재부팅 후 예약 복원에 필요한 RECEIVE_BOOT_COMPLETED와 boot receiver는
/// 계속 있어야 한다. 매니페스트가 수동 편집으로 다시 어긋나는 회귀를 막는다.
void main() {
  late String manifest;

  setUpAll(() {
    manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
  });

  test('SCHEDULE_EXACT_ALARM 권한을 선언하지 않는다', () {
    expect(
      manifest.contains(
        '<uses-permission android:name="android.permission.SCHEDULE_EXACT_ALARM"',
      ),
      isFalse,
    );
  });

  test('RECEIVE_BOOT_COMPLETED 권한을 선언한다', () {
    expect(
      manifest.contains(
        '<uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED"/>',
      ),
      isTrue,
    );
  });

  test('재부팅/업데이트 후 예약을 복원하는 boot receiver가 등록되어 있다', () {
    expect(
      manifest.contains(
        'android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver"',
      ),
      isTrue,
    );
    expect(manifest.contains('android.intent.action.BOOT_COMPLETED'), isTrue);
  });
}
