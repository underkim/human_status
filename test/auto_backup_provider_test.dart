import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:human_status/providers/auto_backup_provider.dart';
import 'package:human_status/services/auto_backup_controller.dart';
import 'package:human_status/services/backup_service.dart';
import 'package:human_status/services/storage_service.dart';

import 'helpers/test_app.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('auto_backup_provider_');
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  AutoBackupNotifier createNotifier(
    StorageService storage, {
    DirectoryPicker? directoryPicker,
    bool Function()? isSupported,
  }) {
    return AutoBackupNotifier(
      storage: storage,
      controller: AutoBackupController(
        storage: storage,
        backupService: BackupService(storage: storage),
        isSupported: isSupported ?? () => true,
      ),
      directoryPicker: directoryPicker,
      isSupported: isSupported,
    );
  }

  group('초기 상태', () {
    test('storage 기본값을 그대로 반영한다', () async {
      final storage = await createTestStorage();
      final notifier = createNotifier(storage);

      expect(notifier.state.enabled, isFalse);
      expect(notifier.state.directoryPath, isNull);
      expect(notifier.state.isSupported, isTrue);
    });
  });

  group('setEnabled', () {
    test('폴더가 이미 있으면 picker 없이 probe 후 켜진다', () async {
      final storage = await createTestStorage();
      await storage.setAutoBackupDirectoryPath(tempDir.path);
      var pickerCalls = 0;
      final notifier = createNotifier(
        storage,
        directoryPicker: ({initialDirectory}) async {
          pickerCalls++;
          return null;
        },
      );

      final result = await notifier.setEnabled(true);

      expect(result, AutoBackupActionResult.success);
      expect(pickerCalls, 0);
      expect(notifier.state.enabled, isTrue);
      expect(storage.autoBackupEnabled, isTrue);
    });

    test('폴더가 없으면 picker를 열고, 취소하면 꺼짐을 유지한다', () async {
      final storage = await createTestStorage();
      final notifier = createNotifier(
        storage,
        directoryPicker: ({initialDirectory}) async => null,
      );

      final result = await notifier.setEnabled(true);

      expect(result, AutoBackupActionResult.cancelled);
      expect(notifier.state.enabled, isFalse);
      expect(storage.autoBackupEnabled, isFalse);
    });

    test('선택한 폴더에 쓸 수 없으면 probeFailed를 반환하고 꺼짐을 유지한다', () async {
      final storage = await createTestStorage();
      final missingPath = '${tempDir.path}${Platform.pathSeparator}missing';
      final notifier = createNotifier(
        storage,
        directoryPicker: ({initialDirectory}) async => missingPath,
      );

      final result = await notifier.setEnabled(true);

      expect(result, AutoBackupActionResult.probeFailed);
      expect(notifier.state.enabled, isFalse);
      expect(storage.autoBackupEnabled, isFalse);
      // probe 실패한 폴더 경로 자체도 저장되지 않아야 한다.
      expect(storage.autoBackupDirectoryPath, isNull);
    });

    test('끄면 폴더/주기는 그대로 두고 enabled만 false로 저장한다', () async {
      final storage = await createTestStorage();
      await storage.setAutoBackupDirectoryPath(tempDir.path);
      await storage.setAutoBackupEnabled(true);
      final notifier = createNotifier(storage);
      // 생성자에서 읽은 초기 state를 최신으로 맞춘다.
      notifier.reload();

      final result = await notifier.setEnabled(false);

      expect(result, AutoBackupActionResult.success);
      expect(storage.autoBackupEnabled, isFalse);
      expect(storage.autoBackupDirectoryPath, tempDir.path);
    });

    test('isChangingSettings 중에는 재진입 호출이 거부된다', () async {
      final storage = await createTestStorage();
      final gate = Completer<String?>();
      final notifier = createNotifier(
        storage,
        directoryPicker: ({initialDirectory}) async => gate.future,
      );

      final first = notifier.setEnabled(true);
      // picker가 아직 안 끝난 상태에서 isChangingSettings가 true여야 한다.
      expect(notifier.state.isChangingSettings, isTrue);

      final second = await notifier.setEnabled(true);
      expect(second, AutoBackupActionResult.saveFailed);

      gate.complete(null);
      await first;
    });
  });

  group('selectDirectory', () {
    test('probe 성공 시 폴더를 저장한다', () async {
      final storage = await createTestStorage();
      final notifier = createNotifier(
        storage,
        directoryPicker: ({initialDirectory}) async => tempDir.path,
      );

      final result = await notifier.selectDirectory();

      expect(result, AutoBackupActionResult.success);
      expect(storage.autoBackupDirectoryPath, tempDir.path);
      expect(notifier.state.directoryPath, tempDir.path);
    });

    test('취소하면 기존 경로를 바꾸지 않는다', () async {
      final storage = await createTestStorage();
      await storage.setAutoBackupDirectoryPath(tempDir.path);
      final notifier = createNotifier(
        storage,
        directoryPicker: ({initialDirectory}) async => null,
      );
      notifier.reload();

      final result = await notifier.selectDirectory();

      expect(result, AutoBackupActionResult.cancelled);
      expect(storage.autoBackupDirectoryPath, tempDir.path);
    });
  });

  group('setFrequency', () {
    test('주기를 저장하고 state에 반영한다', () async {
      final storage = await createTestStorage();
      final notifier = createNotifier(storage);

      final result = await notifier.setFrequency(AutoBackupFrequency.weekly);

      expect(result, AutoBackupActionResult.success);
      expect(storage.autoBackupFrequency, AutoBackupFrequency.weekly);
      expect(notifier.state.frequency, AutoBackupFrequency.weekly);
    });
  });

  group('backupNow', () {
    test('성공하면 lastSuccessAt이 reload되어 반영된다', () async {
      final storage = await createTestStorage();
      await storage.setAutoBackupDirectoryPath(tempDir.path);
      await storage.setAutoBackupEnabled(true);
      final notifier = createNotifier(storage);
      notifier.reload();

      final outcome = await notifier.backupNow();

      expect(outcome, AutoBackupRunOutcome.ran);
      expect(notifier.state.lastSuccessAt, isNotNull);
      expect(notifier.state.isBackingUp, isFalse);
    });
  });

  group('플랫폼 미지원', () {
    test('isSupported가 false면 state.isSupported도 false다', () async {
      final storage = await createTestStorage();
      final notifier = createNotifier(storage, isSupported: () => false);
      expect(notifier.state.isSupported, isFalse);
    });
  });
}
