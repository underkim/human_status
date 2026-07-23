import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:human_status/models/quest.dart';
import 'package:human_status/services/auto_backup_service.dart';
import 'package:human_status/services/backup_service.dart';
import 'package:human_status/services/storage_service.dart';

import 'helpers/test_app.dart';

/// Forces [BackupService.encode] to throw, to exercise the
/// "encode 실패" path in [AutoBackupService.backupToDirectory] without
/// needing a genuinely malformed storage box.
class _EncodeThrowsStorage extends StorageService {
  _EncodeThrowsStorage() : super(inMemory: true);

  @override
  List<Quest> getQuests() => throw StateError('SENTINEL_ENCODE_FAILURE');
}

/// Forces the post-rename [BackupService.inspect] verification step to fail,
/// so a real file gets written and renamed but the backup is still reported
/// as a failure per plan section 6.1 step 7.
class _InspectThrowsBackupService extends BackupService {
  _InspectThrowsBackupService(StorageService storage) : super(storage: storage);

  @override
  BackupPreview inspect(String jsonStr) =>
      throw const FormatException('SENTINEL_INSPECT_FAILURE');
}

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('auto_backup_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('backupToDirectory', () {
    test('BackupService.encode() 결과를 지정 폴더에 UTF-8 JSON 파일로 저장한다', () async {
      final storage = await createTestStorage();
      final backupService = BackupService(storage: storage);
      const service = AutoBackupService();
      final attemptAt = DateTime.utc(2026, 7, 23, 6, 20, 1, 234);

      final result = await service.backupToDirectory(
        directoryPath: tempDir.path,
        backupService: backupService,
        attemptAt: attemptAt,
      );

      expect(result.success, isTrue);
      expect(result.failureCode, isNull);
      expect(result.completedAt, attemptAt);

      final files = await tempDir.list().toList();
      expect(files, hasLength(1));
      final written = files.single as File;
      expect(
        written.path.replaceAll('\\', '/'),
        endsWith(
          '/${AutoBackupService.filePrefix}20260723_062001_234${AutoBackupService.fileSuffix}',
        ),
      );

      final contents = await written.readAsString();
      final preview = backupService.inspect(contents);
      expect(preview.statsCount, StorageService.defaultStats.length);
    });

    test('임시 파일을 쓴 뒤 최종 파일로 rename하며 성공 후 .tmp가 남지 않는다', () async {
      final storage = await createTestStorage();
      final backupService = BackupService(storage: storage);
      const service = AutoBackupService();

      await service.backupToDirectory(
        directoryPath: tempDir.path,
        backupService: backupService,
        attemptAt: DateTime.utc(2026, 7, 23, 6, 20, 1),
      );

      final names = (await tempDir.list().toList())
          .map((e) => e.path.replaceAll('\\', '/').split('/').last)
          .toList();
      expect(names.any((n) => n.endsWith('.tmp')), isFalse);
      expect(
        names.any(
          (n) =>
              n.startsWith(AutoBackupService.filePrefix) &&
              n.endsWith(AutoBackupService.fileSuffix),
        ),
        isTrue,
      );
    });

    test('파일명은 millisecond까지 고유하고 자동 백업 패턴을 따른다', () async {
      final storage = await createTestStorage();
      final backupService = BackupService(storage: storage);
      const service = AutoBackupService();

      await service.backupToDirectory(
        directoryPath: tempDir.path,
        backupService: backupService,
        attemptAt: DateTime.utc(2026, 1, 2, 3, 4, 5, 6),
      );
      await service.backupToDirectory(
        directoryPath: tempDir.path,
        backupService: backupService,
        attemptAt: DateTime.utc(2026, 1, 2, 3, 4, 5, 7),
      );

      final names = (await tempDir.list().toList())
          .map((e) => e.path.replaceAll('\\', '/').split('/').last)
          .toSet();
      expect(names, hasLength(2));
      expect(names, contains('human_status_auto_backup_20260102_030405_006.json'));
      expect(names, contains('human_status_auto_backup_20260102_030405_007.json'));
    });

    test('디렉터리가 존재하지 않으면 directoryMissing으로 실패하고 아무 파일도 만들지 않는다', () async {
      final storage = await createTestStorage();
      final backupService = BackupService(storage: storage);
      const service = AutoBackupService();
      final missingDir = '${tempDir.path}${Platform.pathSeparator}does_not_exist';

      final result = await service.backupToDirectory(
        directoryPath: missingDir,
        backupService: backupService,
        attemptAt: DateTime.utc(2026, 7, 23),
      );

      expect(result.success, isFalse);
      expect(result.failureCode, AutoBackupFailureCode.directoryMissing);
      expect(await tempDir.list().toList(), isEmpty);
    });

    test('BackupService.encode() 실패 시 writeFailed로 실패하고 파일을 만들지 않는다', () async {
      final storage = _EncodeThrowsStorage();
      await storage.init();
      addTearDown(Hive.close);
      final backupService = BackupService(storage: storage);
      const service = AutoBackupService();

      final result = await service.backupToDirectory(
        directoryPath: tempDir.path,
        backupService: backupService,
        attemptAt: DateTime.utc(2026, 7, 23),
      );

      expect(result.success, isFalse);
      expect(result.failureCode, AutoBackupFailureCode.writeFailed);
      expect(await tempDir.list().toList(), isEmpty);
    });

    test('최종 검증(inspect) 실패 시 실패로 보고하고 파일을 남기지 않는다', () async {
      final storage = await createTestStorage();
      final backupService = _InspectThrowsBackupService(storage);
      const service = AutoBackupService();

      final result = await service.backupToDirectory(
        directoryPath: tempDir.path,
        backupService: backupService,
        attemptAt: DateTime.utc(2026, 7, 23),
      );

      expect(result.success, isFalse);
      expect(result.failureCode, AutoBackupFailureCode.writeFailed);
      // rename까지는 성공했지만 검증 실패로 최종 파일도 정리되어야 한다 —
      // 검증되지 않은 파일이 정상 백업으로 오인되면 안 된다.
      expect(await tempDir.list().toList(), isEmpty);
    });
  });

  group('probeDirectory', () {
    test('쓰기 가능한 폴더는 ok를 반환하고 흔적을 남기지 않는다', () async {
      const service = AutoBackupService();
      final result = await service.probeDirectory(tempDir.path);
      expect(result.ok, isTrue);
      expect(await tempDir.list().toList(), isEmpty);
    });

    test('존재하지 않는 폴더는 directoryMissing으로 실패한다', () async {
      const service = AutoBackupService();
      final result = await service.probeDirectory(
        '${tempDir.path}${Platform.pathSeparator}nope',
      );
      expect(result.ok, isFalse);
      expect(result.failureCode, AutoBackupFailureCode.directoryMissing);
    });
  });

  group('pruneOldBackups', () {
    test('최근 7개 자동 백업만 남기고 나머지를 삭제하며 수동 백업/무관한 파일은 건드리지 않는다', () async {
      const service = AutoBackupService();
      for (var i = 0; i < 10; i++) {
        final f = File(
          '${tempDir.path}${Platform.pathSeparator}'
          'human_status_auto_backup_2026010${i}_000000_000.json',
        );
        await f.writeAsString('{}');
      }
      final manual = File(
        '${tempDir.path}${Platform.pathSeparator}human_status_backup_2026-01-01.json',
      );
      await manual.writeAsString('{}');
      final unrelated = File(
        '${tempDir.path}${Platform.pathSeparator}notes.json',
      );
      await unrelated.writeAsString('{}');

      await service.pruneOldBackups(tempDir.path, keep: 7);

      final remaining = (await tempDir.list().toList())
          .map((e) => e.path.replaceAll('\\', '/').split('/').last)
          .toSet();
      final remainingAuto = remaining.where(
        (n) => n.startsWith(AutoBackupService.filePrefix),
      );
      expect(remainingAuto, hasLength(7));
      // 가장 오래된 3개(인덱스 0~2)가 삭제되고 최신 7개(3~9)만 남아야 한다.
      for (var i = 0; i < 3; i++) {
        expect(
          remaining,
          isNot(contains('human_status_auto_backup_2026010${i}_000000_000.json')),
        );
      }
      for (var i = 3; i < 10; i++) {
        expect(
          remaining,
          contains('human_status_auto_backup_2026010${i}_000000_000.json'),
        );
      }
      expect(remaining, contains('human_status_backup_2026-01-01.json'));
      expect(remaining, contains('notes.json'));
    });

    test('개수가 keep 이하면 아무 것도 삭제하지 않는다', () async {
      const service = AutoBackupService();
      final f = File(
        '${tempDir.path}${Platform.pathSeparator}'
        'human_status_auto_backup_20260101_000000_000.json',
      );
      await f.writeAsString('{}');

      await service.pruneOldBackups(tempDir.path, keep: 7);

      expect(await tempDir.list().toList(), hasLength(1));
    });

    test('디렉터리 목록 조회 실패는 예외를 던지지 않고 조용히 무시된다', () async {
      const service = AutoBackupService();
      await expectLater(
        service.pruneOldBackups(
          '${tempDir.path}${Platform.pathSeparator}does_not_exist',
        ),
        completes,
      );
    });
  });

  group('classifyAutoBackupFileSystemException', () {
    test('POSIX ENOSPC(28)을 noSpace로 분류한다', () {
      final e = FileSystemException(
        'write failed',
        '/tmp/x',
        const OSError('No space left on device', 28),
      );
      expect(
        classifyAutoBackupFileSystemException(e),
        AutoBackupFailureCode.noSpace,
      );
    });

    test('Windows ERROR_ACCESS_DENIED(5)을 permissionDenied로 분류한다', () {
      final e = FileSystemException(
        'write failed',
        r'C:\x',
        const OSError('Access is denied', 5),
      );
      expect(
        classifyAutoBackupFileSystemException(e),
        AutoBackupFailureCode.permissionDenied,
      );
    });

    test('알 수 없는 오류 코드는 writeFailed로 분류한다', () {
      final e = FileSystemException(
        'write failed',
        '/tmp/x',
        const OSError('mystery failure', 9999),
      );
      expect(
        classifyAutoBackupFileSystemException(e),
        AutoBackupFailureCode.writeFailed,
      );
    });

    test('오류 코드가 없어도 메시지로 no space/permission을 분류한다', () {
      final noSpace = FileSystemException('disk full while writing');
      expect(
        classifyAutoBackupFileSystemException(noSpace),
        AutoBackupFailureCode.noSpace,
      );
      final denied = FileSystemException('permission denied for path');
      expect(
        classifyAutoBackupFileSystemException(denied),
        AutoBackupFailureCode.permissionDenied,
      );
    });
  });

  group('isDue', () {
    const service = AutoBackupService();

    test('마지막 성공 이력이 없으면 항상 due다', () {
      expect(
        service.isDue(
          now: DateTime.utc(2026, 7, 23),
          lastSuccessAt: null,
          frequency: AutoBackupFrequency.daily,
        ),
        isTrue,
      );
    });

    test('daily: 24시간 미만이면 due가 아니고, 24시간 이상이면 due다', () {
      final last = DateTime.utc(2026, 7, 22, 12);
      expect(
        service.isDue(
          now: last.add(const Duration(hours: 23, minutes: 59)),
          lastSuccessAt: last,
          frequency: AutoBackupFrequency.daily,
        ),
        isFalse,
      );
      expect(
        service.isDue(
          now: last.add(const Duration(hours: 24)),
          lastSuccessAt: last,
          frequency: AutoBackupFrequency.daily,
        ),
        isTrue,
      );
    });

    test('weekly: 7일 미만이면 due가 아니고, 7일 이상이면 due다', () {
      final last = DateTime.utc(2026, 7, 1);
      expect(
        service.isDue(
          now: last.add(const Duration(days: 6, hours: 23)),
          lastSuccessAt: last,
          frequency: AutoBackupFrequency.weekly,
        ),
        isFalse,
      );
      expect(
        service.isDue(
          now: last.add(const Duration(days: 7)),
          lastSuccessAt: last,
          frequency: AutoBackupFrequency.weekly,
        ),
        isTrue,
      );
    });

    test('시계가 소폭(24시간 이내) 뒤로 이동하면 due가 아니다', () {
      final last = DateTime.utc(2026, 7, 23, 12);
      expect(
        service.isDue(
          now: last.subtract(const Duration(hours: 1)),
          lastSuccessAt: last,
          frequency: AutoBackupFrequency.daily,
        ),
        isFalse,
      );
    });

    test('lastSuccessAt이 24시간 넘게 미래인 비정상 값이면 구성 오류로 보고 강제로 due 처리한다', () {
      final last = DateTime.utc(2026, 7, 23, 12);
      expect(
        service.isDue(
          now: last.subtract(const Duration(hours: 25)),
          lastSuccessAt: last,
          frequency: AutoBackupFrequency.daily,
        ),
        isTrue,
      );
    });
  });
}
