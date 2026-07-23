import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:human_status/services/auto_backup_controller.dart';
import 'package:human_status/services/backup_service.dart';
import 'package:human_status/services/notification_service.dart';
import 'package:human_status/services/storage_service.dart';

import 'helpers/test_app.dart';

/// Records calls instead of touching the real notification plugin — same
/// pattern as `weekly_report_toggle_test.dart`'s fakes.
class _RecordingNotificationService extends NotificationService {
  int showAutoBackupFailedCalls = 0;

  @override
  Future<void> init({
    DidReceiveNotificationResponseCallback? onDidReceiveNotificationResponse,
    DidReceiveBackgroundNotificationResponseCallback?
    onDidReceiveBackgroundNotificationResponse,
  }) async {}

  @override
  Future<void> showAutoBackupFailed() async {
    showAutoBackupFailedCalls++;
  }
}

/// Wraps a real in-memory [StorageService] but makes
/// [recordAutoBackupSuccess] always throw, so tests can exercise "the backup
/// file itself was written successfully, but the durable success record
/// failed to save" (plan section 6.2's last row) without needing Hive
/// itself to actually fail.
class _SuccessRecordFailsStorage extends StorageService {
  _SuccessRecordFailsStorage() : super(inMemory: true);

  @override
  Future<void> recordAutoBackupSuccess(DateTime at) {
    throw Exception('SENTINEL_SUCCESS_RECORD_FAILURE');
  }
}

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('auto_backup_controller_');
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  Future<StorageService> setUpEnabledStorage({
    AutoBackupFrequency frequency = AutoBackupFrequency.daily,
  }) async {
    final storage = await createTestStorage();
    await storage.setAutoBackupDirectoryPath(tempDir.path);
    await storage.setAutoBackupFrequency(frequency);
    await storage.setAutoBackupEnabled(true);
    return storage;
  }

  Future<_SuccessRecordFailsStorage> setUpEnabledStorageWithFailingSuccessRecord({
    AutoBackupFrequency frequency = AutoBackupFrequency.daily,
  }) async {
    final storage = _SuccessRecordFailsStorage();
    await storage.init();
    addTearDown(Hive.close);
    await storage.setAutoBackupDirectoryPath(tempDir.path);
    await storage.setAutoBackupFrequency(frequency);
    await storage.setAutoBackupEnabled(true);
    return storage;
  }

  group('backupIfDue', () {
    test('비활성 상태면 실행하지 않는다', () async {
      final storage = await createTestStorage();
      await storage.setAutoBackupDirectoryPath(tempDir.path);
      final controller = AutoBackupController(
        storage: storage,
        backupService: BackupService(storage: storage),
        isSupported: () => true,
      );

      await controller.backupIfDue();

      expect(await tempDir.list().toList(), isEmpty);
      expect(storage.autoBackupLastAttemptAt, isNull);
    });

    test('미지원 플랫폼이면 활성화돼 있어도 실행하지 않는다', () async {
      final storage = await setUpEnabledStorage();
      final controller = AutoBackupController(
        storage: storage,
        backupService: BackupService(storage: storage),
        isSupported: () => false,
      );

      await controller.backupIfDue();

      expect(await tempDir.list().toList(), isEmpty);
    });

    test('폴더 미지정이면 실행하지 않는다', () async {
      final storage = await createTestStorage();
      await storage.setAutoBackupEnabled(true);
      final controller = AutoBackupController(
        storage: storage,
        backupService: BackupService(storage: storage),
        isSupported: () => true,
      );

      await controller.backupIfDue();

      expect(storage.autoBackupLastAttemptAt, isNull);
    });

    test('성공 이력이 없으면 즉시 실행하고 성공 시각을 기록한다', () async {
      final storage = await setUpEnabledStorage();
      final now = DateTime.utc(2026, 7, 23, 9);
      final controller = AutoBackupController(
        storage: storage,
        backupService: BackupService(storage: storage),
        isSupported: () => true,
        clock: () => now,
      );

      await controller.backupIfDue();

      expect(storage.autoBackupLastSuccessAt, now);
      expect(storage.autoBackupLastAttemptAt, now);
      final files = await tempDir.list().toList();
      expect(files, hasLength(1));
    });

    test('마지막 성공이 24시간 미만이면 daily 주기에서 실행하지 않는다', () async {
      final storage = await setUpEnabledStorage();
      final lastSuccess = DateTime.utc(2026, 7, 23, 9);
      await storage.recordAutoBackupSuccess(lastSuccess);
      final controller = AutoBackupController(
        storage: storage,
        backupService: BackupService(storage: storage),
        isSupported: () => true,
        clock: () => lastSuccess.add(const Duration(hours: 23)),
      );

      await controller.backupIfDue();

      expect(storage.autoBackupLastAttemptAt, lastSuccess);
      expect(await tempDir.list().toList(), isEmpty);
    });

    test('마지막 성공이 24시간 이상 지나면 daily 주기에서 다시 실행한다', () async {
      final storage = await setUpEnabledStorage();
      final lastSuccess = DateTime.utc(2026, 7, 23, 9);
      await storage.recordAutoBackupSuccess(lastSuccess);
      final now = lastSuccess.add(const Duration(hours: 24));
      final controller = AutoBackupController(
        storage: storage,
        backupService: BackupService(storage: storage),
        isSupported: () => true,
        clock: () => now,
      );

      await controller.backupIfDue();

      expect(storage.autoBackupLastSuccessAt, now);
      final files = await tempDir.list().toList();
      expect(files, hasLength(1));
    });

    test('weekly 주기는 7일 미만이면 실행하지 않는다', () async {
      final storage = await setUpEnabledStorage(
        frequency: AutoBackupFrequency.weekly,
      );
      final lastSuccess = DateTime.utc(2026, 7, 1);
      await storage.recordAutoBackupSuccess(lastSuccess);
      final controller = AutoBackupController(
        storage: storage,
        backupService: BackupService(storage: storage),
        isSupported: () => true,
        clock: () => lastSuccess.add(const Duration(days: 6)),
      );

      await controller.backupIfDue();

      expect(await tempDir.list().toList(), isEmpty);
    });

    test('실패 후 1시간 이내에는 자동 재시도하지 않는다', () async {
      final storage = await setUpEnabledStorage();
      final failAt = DateTime.utc(2026, 7, 23, 9);
      await storage.recordAutoBackupFailure(
        attemptAt: failAt,
        code: AutoBackupFailureCode.writeFailed,
      );
      final controller = AutoBackupController(
        storage: storage,
        backupService: BackupService(storage: storage),
        isSupported: () => true,
        clock: () => failAt.add(const Duration(minutes: 30)),
      );

      await controller.backupIfDue();

      // backoff 중이라 시도 자체가 일어나지 않아야 하므로 lastAttemptAt이
      // 그대로 failAt이어야 한다(새 attempt로 갱신되지 않음).
      expect(storage.autoBackupLastAttemptAt, failAt);
    });

    test('실패 후 1시간이 지나면 다시 시도한다', () async {
      final storage = await setUpEnabledStorage();
      final failAt = DateTime.utc(2026, 7, 23, 9);
      await storage.recordAutoBackupFailure(
        attemptAt: failAt,
        code: AutoBackupFailureCode.writeFailed,
      );
      final retryAt = failAt.add(const Duration(hours: 1));
      final controller = AutoBackupController(
        storage: storage,
        backupService: BackupService(storage: storage),
        isSupported: () => true,
        clock: () => retryAt,
      );

      await controller.backupIfDue();

      expect(storage.autoBackupLastAttemptAt, retryAt);
      expect(storage.autoBackupLastSuccessAt, retryAt);
    });

    test('동시 호출은 한 번만 실행되고 같은 in-flight future를 공유한다', () async {
      final storage = await setUpEnabledStorage();
      final controller = AutoBackupController(
        storage: storage,
        backupService: BackupService(storage: storage),
        isSupported: () => true,
      );

      final f1 = controller.backupIfDue();
      final f2 = controller.backupIfDue();
      await Future.wait([f1, f2]);

      final files = await tempDir.list().toList();
      expect(files, hasLength(1));
    });

    test('폴더가 사라지면 directoryMissing으로 기록하고 마지막 성공은 보존한다', () async {
      final storage = await setUpEnabledStorage();
      final firstRun = DateTime.utc(2026, 7, 20);
      var now = firstRun;
      final controller = AutoBackupController(
        storage: storage,
        backupService: BackupService(storage: storage),
        isSupported: () => true,
        clock: () => now,
      );
      await controller.backupIfDue();
      expect(storage.autoBackupLastSuccessAt, firstRun);

      await tempDir.delete(recursive: true);
      now = firstRun.add(const Duration(hours: 25));
      await controller.backupIfDue();

      expect(storage.autoBackupLastSuccessAt, firstRun);
      expect(
        storage.autoBackupLastFailureCode,
        AutoBackupFailureCode.directoryMissing,
      );
    });
  });

  group('backupNow', () {
    test('backoff을 무시하고 즉시 실행한다', () async {
      final storage = await setUpEnabledStorage();
      final failAt = DateTime.utc(2026, 7, 23, 9);
      await storage.recordAutoBackupFailure(
        attemptAt: failAt,
        code: AutoBackupFailureCode.writeFailed,
      );
      final controller = AutoBackupController(
        storage: storage,
        backupService: BackupService(storage: storage),
        isSupported: () => true,
        clock: () => failAt.add(const Duration(minutes: 5)),
      );

      final outcome = await controller.backupNow();

      expect(outcome, AutoBackupRunOutcome.ran);
      expect(storage.autoBackupLastSuccessAt, isNotNull);
    });

    test('비활성 상태면 disabled를 반환하고 아무 것도 쓰지 않는다', () async {
      final storage = await createTestStorage();
      await storage.setAutoBackupDirectoryPath(tempDir.path);
      final controller = AutoBackupController(
        storage: storage,
        backupService: BackupService(storage: storage),
        isSupported: () => true,
      );

      final outcome = await controller.backupNow();

      expect(outcome, AutoBackupRunOutcome.disabled);
      expect(await tempDir.list().toList(), isEmpty);
    });

    test('미지원 플랫폼이면 unsupported를 반환한다', () async {
      final storage = await setUpEnabledStorage();
      final controller = AutoBackupController(
        storage: storage,
        backupService: BackupService(storage: storage),
        isSupported: () => false,
      );

      expect(await controller.backupNow(), AutoBackupRunOutcome.unsupported);
    });

    test('폴더 미지정이면 noDirectory를 반환한다', () async {
      final storage = await createTestStorage();
      await storage.setAutoBackupEnabled(true);
      final controller = AutoBackupController(
        storage: storage,
        backupService: BackupService(storage: storage),
        isSupported: () => true,
      );

      expect(await controller.backupNow(), AutoBackupRunOutcome.noDirectory);
    });
  });

  group('실패 알림 throttle', () {
    test('실패하면 알림을 한 번 보낸다', () async {
      final storage = await createTestStorage();
      await storage.setAutoBackupEnabled(true);
      await storage.setAutoBackupDirectoryPath(
        '${tempDir.path}${Platform.pathSeparator}missing',
      );
      final notifications = _RecordingNotificationService();
      final controller = AutoBackupController(
        storage: storage,
        backupService: BackupService(storage: storage),
        notificationService: notifications,
        isSupported: () => true,
      );

      await controller.backupIfDue();

      expect(notifications.showAutoBackupFailedCalls, 1);
      expect(storage.autoBackupLastFailureNotifiedAt, isNotNull);
    });

    test('같은 실패가 24시간 내에 반복되면 알림을 다시 보내지 않는다', () async {
      final storage = await createTestStorage();
      await storage.setAutoBackupEnabled(true);
      final missingPath = '${tempDir.path}${Platform.pathSeparator}missing';
      await storage.setAutoBackupDirectoryPath(missingPath);
      final notifications = _RecordingNotificationService();
      var now = DateTime.utc(2026, 7, 23, 9);
      final controller = AutoBackupController(
        storage: storage,
        backupService: BackupService(storage: storage),
        notificationService: notifications,
        isSupported: () => true,
        clock: () => now,
      );

      await controller.backupIfDue();
      expect(notifications.showAutoBackupFailedCalls, 1);

      // 1시간 backoff을 지나 재시도했지만 여전히 실패 — 24시간 이내이므로
      // 알림은 다시 가지 않아야 한다.
      now = now.add(const Duration(hours: 2));
      await controller.backupIfDue();

      expect(notifications.showAutoBackupFailedCalls, 1);
    });

    test('24시간이 지난 뒤 같은 실패가 반복되면 알림을 다시 보낸다', () async {
      final storage = await createTestStorage();
      await storage.setAutoBackupEnabled(true);
      final missingPath = '${tempDir.path}${Platform.pathSeparator}missing';
      await storage.setAutoBackupDirectoryPath(missingPath);
      final notifications = _RecordingNotificationService();
      var now = DateTime.utc(2026, 7, 23, 9);
      final controller = AutoBackupController(
        storage: storage,
        backupService: BackupService(storage: storage),
        notificationService: notifications,
        isSupported: () => true,
        clock: () => now,
      );

      await controller.backupIfDue();
      expect(notifications.showAutoBackupFailedCalls, 1);

      now = now.add(const Duration(hours: 25));
      await controller.backupIfDue();

      expect(notifications.showAutoBackupFailedCalls, 2);
    });
  });

  group('성공 상태 저장 실패', () {
    test(
      '백업 파일은 만들어졌지만 성공 상태 저장이 실패하면 실패로 기록하고 알린다',
      () async {
        final storage = await setUpEnabledStorageWithFailingSuccessRecord();
        final notifications = _RecordingNotificationService();
        final attemptAt = DateTime.utc(2026, 7, 23, 9);
        final controller = AutoBackupController(
          storage: storage,
          backupService: BackupService(storage: storage),
          notificationService: notifications,
          isSupported: () => true,
          clock: () => attemptAt,
        );

        await controller.backupIfDue();

        // 파일 쓰기 자체는 실제로 성공해야 한다 — 이 테스트가 검증하는 건
        // "쓰기 실패"가 아니라 "쓰기 성공 후 상태 저장 실패"다.
        final files = await tempDir.list().toList();
        expect(files, hasLength(1));

        expect(storage.autoBackupLastSuccessAt, isNull);
        expect(storage.autoBackupLastAttemptAt, attemptAt);
        expect(storage.autoBackupLastFailureAt, attemptAt);
        expect(
          storage.autoBackupLastFailureCode,
          AutoBackupFailureCode.stateSaveFailed,
        );
        expect(notifications.showAutoBackupFailedCalls, 1);
      },
    );

    test(
      '"지금 백업"은 ran을 반환하지만 실패로 기록되어 있어 성공 SnackBar로 이어지지 않는다',
      () async {
        final storage = await setUpEnabledStorageWithFailingSuccessRecord();
        final controller = AutoBackupController(
          storage: storage,
          backupService: BackupService(storage: storage),
          isSupported: () => true,
        );

        final outcome = await controller.backupNow();

        expect(outcome, AutoBackupRunOutcome.ran);
        // SettingsScreen._backupNow()는 outcome == ran일 때
        // AutoBackupState.hasUnresolvedFailure(= lastFailureAt이
        // lastSuccessAt보다 최근인지)로 성공/실패 SnackBar를 고른다. 성공 상태
        // 저장이 실패했는데도 이 값들이 비어 있으면 실패를 성공으로 잘못
        // 안내하게 된다.
        expect(storage.autoBackupLastSuccessAt, isNull);
        expect(storage.autoBackupLastFailureAt, isNotNull);
      },
    );
  });
}
