import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:human_status/services/backup_service.dart';
import 'package:human_status/services/storage_service.dart';

Future<StorageService> _openStorage() async {
  final storage = StorageService(inMemory: true);
  await storage.init();
  addTearDown(Hive.close);
  return storage;
}

void main() {
  group('기본값', () {
    test('새 설치는 비활성/매일/이력 없음이다', () async {
      final storage = await _openStorage();

      expect(storage.autoBackupEnabled, isFalse);
      expect(storage.autoBackupDirectoryPath, isNull);
      expect(storage.autoBackupFrequency, AutoBackupFrequency.daily);
      expect(storage.autoBackupLastSuccessAt, isNull);
      expect(storage.autoBackupLastAttemptAt, isNull);
      expect(storage.autoBackupLastFailureCode, isNull);
      expect(storage.autoBackupLastFailureAt, isNull);
      expect(storage.autoBackupLastFailureNotifiedAt, isNull);
    });
  });

  group('round-trip', () {
    test('활성화/경로/주기 설정이 그대로 읽힌다', () async {
      final storage = await _openStorage();

      await storage.setAutoBackupEnabled(true);
      await storage.setAutoBackupDirectoryPath('/home/user/backups');
      await storage.setAutoBackupFrequency(AutoBackupFrequency.weekly);

      expect(storage.autoBackupEnabled, isTrue);
      expect(storage.autoBackupDirectoryPath, '/home/user/backups');
      expect(storage.autoBackupFrequency, AutoBackupFrequency.weekly);
    });

    test('디렉터리 경로를 null로 지우면 다시 선택되지 않음 상태가 된다', () async {
      final storage = await _openStorage();
      await storage.setAutoBackupDirectoryPath('/some/path');
      expect(storage.autoBackupDirectoryPath, '/some/path');

      await storage.setAutoBackupDirectoryPath(null);
      expect(storage.autoBackupDirectoryPath, isNull);
    });

    test('recordAutoBackupSuccess는 성공/시도 시각을 함께 기록하고 실패 상태를 지운다', () async {
      final storage = await _openStorage();
      await storage.recordAutoBackupFailure(
        attemptAt: DateTime.utc(2026, 7, 1),
        code: AutoBackupFailureCode.writeFailed,
      );
      expect(storage.autoBackupLastFailureCode, AutoBackupFailureCode.writeFailed);

      final successAt = DateTime.utc(2026, 7, 23, 6, 20);
      await storage.recordAutoBackupSuccess(successAt);

      expect(storage.autoBackupLastSuccessAt, successAt);
      expect(storage.autoBackupLastAttemptAt, successAt);
      expect(storage.autoBackupLastFailureCode, isNull);
      expect(storage.autoBackupLastFailureAt, isNull);
    });

    test('recordAutoBackupFailure는 마지막 성공 시각을 보존한다', () async {
      final storage = await _openStorage();
      final successAt = DateTime.utc(2026, 7, 20);
      await storage.recordAutoBackupSuccess(successAt);

      final failAt = DateTime.utc(2026, 7, 23);
      await storage.recordAutoBackupFailure(
        attemptAt: failAt,
        code: AutoBackupFailureCode.directoryMissing,
      );

      expect(storage.autoBackupLastSuccessAt, successAt);
      expect(storage.autoBackupLastAttemptAt, failAt);
      expect(storage.autoBackupLastFailureAt, failAt);
      expect(
        storage.autoBackupLastFailureCode,
        AutoBackupFailureCode.directoryMissing,
      );
    });

    test('recordAutoBackupFailureNotified는 알림 시각을 저장한다', () async {
      final storage = await _openStorage();
      final at = DateTime.utc(2026, 7, 23, 8);
      await storage.recordAutoBackupFailureNotified(at);
      expect(storage.autoBackupLastFailureNotifiedAt, at);
    });
  });

  group('fail-closed', () {
    test('잘못된 타입이 저장돼 있으면 enabled는 false로 취급한다', () async {
      final storage = await _openStorage();
      await storage.settingsBox.put('autoBackupEnabled', 'not-a-bool');
      expect(storage.autoBackupEnabled, isFalse);
    });

    test('알 수 없는 frequency 문자열은 daily로 정규화한다', () async {
      final storage = await _openStorage();
      await storage.settingsBox.put('autoBackupFrequency', 'monthly');
      expect(storage.autoBackupFrequency, AutoBackupFrequency.daily);
    });

    test('알 수 없는 failureCode 문자열은 null로 취급한다', () async {
      final storage = await _openStorage();
      await storage.settingsBox.put(
        'autoBackupLastFailureCode',
        'somethingFromAFutureVersion',
      );
      expect(storage.autoBackupLastFailureCode, isNull);
    });

    test('directoryPath에 잘못된 타입이 저장돼 있으면 null로 취급한다', () async {
      final storage = await _openStorage();
      await storage.settingsBox.put('autoBackupDirectoryPath', 12345);
      expect(storage.autoBackupDirectoryPath, isNull);
    });

    test('타임스탬프 키에 잘못된 타입이 저장돼 있으면 null로 취급한다', () async {
      final storage = await _openStorage();
      await storage.settingsBox.put('autoBackupLastSuccessAt', 12345);
      expect(storage.autoBackupLastSuccessAt, isNull);
    });

    test('ISO-8601 문자열로 저장된 타임스탬프도 읽힌다', () async {
      final storage = await _openStorage();
      final at = DateTime.utc(2026, 7, 23, 9, 30);
      await storage.settingsBox.put(
        'autoBackupLastSuccessAt',
        at.toIso8601String(),
      );
      expect(storage.autoBackupLastSuccessAt, at);
    });
  });

  group('백업 스키마와의 분리', () {
    test('자동 백업 설정은 BackupService.encode() 결과에 포함되지 않는다', () async {
      final storage = await _openStorage();
      await storage.setAutoBackupEnabled(true);
      await storage.setAutoBackupDirectoryPath('/private/backups');
      await storage.setAutoBackupFrequency(AutoBackupFrequency.weekly);
      await storage.recordAutoBackupSuccess(DateTime.utc(2026, 7, 23));

      final jsonStr = BackupService(storage: storage).encode();
      expect(jsonStr, isNot(contains('/private/backups')));
      expect(jsonStr, isNot(contains('autoBackup')));

      final decoded = jsonDecode(jsonStr) as Map<String, dynamic>;
      expect(decoded.containsKey('autoBackupEnabled'), isFalse);
      final preferences = decoded['preferences'] as Map<String, dynamic>;
      expect(preferences.containsKey('autoBackupEnabled'), isFalse);
    });

    test('백업 restore()는 자동 백업 설정을 바꾸지 않는다', () async {
      final storage = await _openStorage();
      await storage.setAutoBackupEnabled(true);
      await storage.setAutoBackupDirectoryPath('/private/backups');
      await storage.setAutoBackupFrequency(AutoBackupFrequency.weekly);

      final backupService = BackupService(storage: storage);
      final jsonStr = backupService.encode();
      await backupService.restore(jsonStr);

      expect(storage.autoBackupEnabled, isTrue);
      expect(storage.autoBackupDirectoryPath, '/private/backups');
      expect(storage.autoBackupFrequency, AutoBackupFrequency.weekly);
    });
  });
}
