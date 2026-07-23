import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:human_status/models/quest.dart';
import 'package:human_status/services/storage_service.dart';

import 'helpers/test_app.dart';

/// Real (non-`inMemory`) [StorageService] use goes through
/// `Hive.initFlutter()`, which calls path_provider's platform channel — not
/// implemented in a bare `test()`/no-widget-binding run. Mocking the channel
/// (the officially supported way to test plugin-backed code, see
/// https://docs.flutter.dev/testing/plugins-in-tests) lets
/// [StorageService.init] resolve both `getApplicationDocumentsDirectory`
/// (used by `hive_flutter`) and `getApplicationSupportDirectory` (used by
/// `FileQuestCompletionLockBackend`) to the same temp directory without
/// touching a real device path.
Future<void> _mockPathProviderChannel(String directoryPath) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (call) async => directoryPath);
}

void main() {
  group('installationId', () {
    test('처음 읽으면 새로 생성되고 이후 읽기는 같은 값을 돌려준다', () async {
      final storage = await createTestStorage();

      final first = storage.installationId;
      expect(first, isNotEmpty);
      final second = storage.installationId;
      expect(second, first);
    });

    test('디스크에 저장된 뒤에는 스토리지를 다시 열어도(재시작 시뮬레이션) 같은 값을 유지한다', () async {
      final dir = await Directory.systemTemp.createTemp(
        'storage_installation_id_test_',
      );
      addTearDown(() => dir.delete(recursive: true));
      await _mockPathProviderChannel(dir.path);
      addTearDown(Hive.close);

      final storage = StorageService();
      await storage.init();
      final id = storage.installationId;
      // installationId's persist is fire-and-forget (see its doc comment) —
      // give the write a turn to actually land before simulating restart.
      await Future<void>.delayed(Duration.zero);

      await storage.close();

      final restarted = StorageService();
      await restarted.init();
      expect(restarted.installationId, id);
    });
  });

  group('action token record', () {
    test('기록된 적 없는 토큰은 null이다', () async {
      final storage = await createTestStorage();
      expect(storage.getActionTokenRecord('never-seen'), isNull);
    });

    test('processing으로 기록한 뒤 completed로 갱신할 수 있다', () async {
      final storage = await createTestStorage();
      final processingAt = DateTime(2026, 7, 23, 9);
      await storage.recordActionToken(
        'tok-1',
        ActionTokenStatus.processing,
        processingAt,
      );

      final processingRecord = storage.getActionTokenRecord('tok-1');
      expect(processingRecord!.status, ActionTokenStatus.processing);
      expect(processingRecord.at, processingAt);

      final completedAt = DateTime(2026, 7, 23, 9, 0, 5);
      await storage.recordActionToken(
        'tok-1',
        ActionTokenStatus.completed,
        completedAt,
      );

      final completedRecord = storage.getActionTokenRecord('tok-1');
      expect(completedRecord!.status, ActionTokenStatus.completed);
      expect(completedRecord.at, completedAt);
    });

    test('실패 상태도 기록/조회할 수 있다', () async {
      final storage = await createTestStorage();
      await storage.recordActionToken(
        'tok-2',
        ActionTokenStatus.failed,
        DateTime(2026, 7, 23),
      );

      expect(
        storage.getActionTokenRecord('tok-2')!.status,
        ActionTokenStatus.failed,
      );
    });

    test('알 수 없는 형태로 저장된 값은 null로 처리된다', () async {
      final storage = await createTestStorage();
      await storage.settingsBox.put('notificationActionToken:corrupt', 'nope');

      expect(storage.getActionTokenRecord('corrupt'), isNull);
    });
  });

  group('reopenForExternalChanges', () {
    test('inMemory 스토리지에서는 아무 것도 하지 않는다 (no-op)', () async {
      final storage = await createTestStorage();
      await storage.saveQuest(
        Quest(
          id: 'q1',
          title: '퀘스트',
          description: '',
          statRewards: const {'health': 10},
          createdAt: DateTime(2026, 7, 23),
        ),
      );

      // Would throw if it tried to close/reopen in-memory (bytes-backed)
      // boxes, since there is no real file behind them to reopen from.
      await storage.reopenForExternalChanges();

      expect(storage.getQuest('q1'), isNotNull);
    });

    test('디스크 기반 스토리지에서는 박스를 닫았다 다시 열어 최신 상태를 읽는다', () async {
      final dir = await Directory.systemTemp.createTemp(
        'storage_reopen_test_',
      );
      addTearDown(() async {
        await dir.delete(recursive: true);
      });
      await _mockPathProviderChannel(dir.path);
      addTearDown(Hive.close);

      final storage = StorageService();
      await storage.init();

      await storage.saveQuest(
        Quest(
          id: 'q1',
          title: '원래 제목',
          description: '',
          statRewards: const {'health': 10},
          createdAt: DateTime(2026, 7, 23),
        ),
      );

      // Simulate another isolate/process writing to the same on-disk box:
      // close this instance's box, mutate the file through a second,
      // separately-opened box instance, then close that one too.
      await storage.questsBox.close();
      final externalWriterBox = await Hive.openBox<Quest>(
        StorageService.questsBoxName,
      );
      final quest = externalWriterBox.get('q1')!;
      quest.title = '외부에서 바뀐 제목';
      await externalWriterBox.put('q1', quest);
      await externalWriterBox.close();

      await storage.reopenForExternalChanges();

      expect(storage.getQuest('q1')!.title, '외부에서 바뀐 제목');
    });
  });
}
