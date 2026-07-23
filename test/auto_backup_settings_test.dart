import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:human_status/providers/auto_backup_provider.dart';
import 'package:human_status/screens/settings_screen.dart';
import 'package:human_status/services/auto_backup_controller.dart';
import 'package:human_status/services/backup_service.dart';
import 'package:human_status/services/storage_service.dart';

import 'helpers/test_app.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('auto_backup_widget_');
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  AutoBackupNotifier buildNotifier(
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
      isSupported: isSupported ?? () => true,
    );
  }

  /// Builds the notifier up front (rather than inside the override
  /// callback) and returns it, so tests can poll its `state.isBackingUp`/
  /// `isChangingSettings` flags in [settleRealIO] instead of waiting on an
  /// arbitrary fixed time budget.
  Future<AutoBackupNotifier> pumpSettings(
    WidgetTester tester,
    StorageService storage, {
    DirectoryPicker? directoryPicker,
    bool Function()? isSupported,
  }) async {
    final notifier = buildNotifier(
      storage,
      directoryPicker: directoryPicker,
      isSupported: isSupported,
    );
    await pumpApp(
      tester,
      storage,
      const SettingsScreen(),
      overrides: [autoBackupProvider.overrideWith((ref) => notifier)],
    );
    await tester.pump();
    return notifier;
  }

  group('지원 플랫폼', () {
    testWidgets('기본 상태에서 자동 백업 섹션이 표시된다', (tester) async {
      setScreenSize(tester, const Size(800, 1400));
      final storage = await createTestStorage();
      await pumpSettings(tester, storage);

      expect(find.text('자동 백업'), findsOneWidget);
      expect(find.text('꺼짐 · 폴더를 선택하면 앱을 열 때 주기적으로 백업해요'), findsOneWidget);
      expect(find.text('백업 폴더'), findsOneWidget);
      expect(find.text('선택되지 않음'), findsOneWidget);
      expect(find.text('백업 주기'), findsOneWidget);
      expect(find.text('매일'), findsOneWidget);
      expect(find.text('마지막 백업'), findsOneWidget);
      expect(find.text('아직 자동 백업하지 않았어요'), findsOneWidget);
      expect(find.text('지금 백업'), findsOneWidget);
    });

    testWidgets('폴더 없이 토글을 켜면 picker를 호출하고, 취소하면 꺼짐을 유지한다', (tester) async {
      setScreenSize(tester, const Size(800, 1400));
      final storage = await createTestStorage();
      var pickerCalls = 0;
      await pumpSettings(
        tester,
        storage,
        directoryPicker: ({initialDirectory}) async {
          pickerCalls++;
          return null;
        },
      );

      await tester.tap(find.text('자동 백업'));
      await tester.pumpAndSettle();
      // 확인 대화상자에서 켜기를 선택해야 picker가 호출된다.
      await tester.tap(find.text('폴더 선택하고 켜기'));
      await tester.pumpAndSettle();

      expect(pickerCalls, 1);
      expect(storage.autoBackupEnabled, isFalse);
      expect(
        tester
            .widget<SwitchListTile>(
              find.widgetWithText(SwitchListTile, '자동 백업'),
            )
            .value,
        isFalse,
      );
    });

    testWidgets('probe에 성공한 폴더를 고르면 토글이 켜지고 성공 SnackBar가 표시된다', (tester) async {
      setScreenSize(tester, const Size(800, 1400));
      final storage = await createTestStorage();
      final notifier = await pumpSettings(
        tester,
        storage,
        directoryPicker: ({initialDirectory}) async => tempDir.path,
      );

      await tester.tap(find.text('자동 백업'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('폴더 선택하고 켜기'));
      await settleRealIO(
        tester,
        isDone: () => !notifier.state.isChangingSettings,
      );

      expect(storage.autoBackupEnabled, isTrue);
      expect(storage.autoBackupDirectoryPath, tempDir.path);
      expect(find.text('자동 백업을 켰어요.'), findsOneWidget);
      expect(
        tester
            .widget<SwitchListTile>(
              find.widgetWithText(SwitchListTile, '자동 백업'),
            )
            .value,
        isTrue,
      );
    });

    testWidgets('쓸 수 없는 폴더를 고르면 토글이 켜지지 않고 오류가 표시된다', (tester) async {
      setScreenSize(tester, const Size(800, 1400));
      final storage = await createTestStorage();
      final missingPath = '${tempDir.path}${Platform.pathSeparator}missing';
      final notifier = await pumpSettings(
        tester,
        storage,
        directoryPicker: ({initialDirectory}) async => missingPath,
      );

      await tester.tap(find.text('자동 백업'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('폴더 선택하고 켜기'));
      await settleRealIO(
        tester,
        isDone: () => !notifier.state.isChangingSettings,
      );

      expect(storage.autoBackupEnabled, isFalse);
      expect(find.text('선택한 폴더에 쓸 수 없어요. 다른 폴더를 선택해주세요.'), findsOneWidget);
      expect(
        tester
            .widget<SwitchListTile>(
              find.widgetWithText(SwitchListTile, '자동 백업'),
            )
            .value,
        isFalse,
      );
    });

    testWidgets('백업 폴더 경로는 축약되어 표시되고 정보 버튼으로 전체 경로를 볼 수 있다', (tester) async {
      setScreenSize(tester, const Size(800, 1400));
      final storage = await createTestStorage();
      final nestedDir = Directory(
        '${tempDir.path}${Platform.pathSeparator}a${Platform.pathSeparator}b${Platform.pathSeparator}very_long_backup_folder_name',
      );
      await tester.runAsync(() => nestedDir.create(recursive: true));
      await storage.setAutoBackupDirectoryPath(nestedDir.path);

      await pumpSettings(tester, storage);

      expect(find.text('선택되지 않음'), findsNothing);
      expect(find.textContaining('very_long_backup_folder_name'), findsWidgets);
      expect(find.text(nestedDir.path), findsNothing);

      await tester.tap(find.byIcon(Icons.info_outline));
      await tester.pumpAndSettle();

      expect(find.text(nestedDir.path), findsOneWidget);
    });

    testWidgets('백업 주기를 매주로 바꿀 수 있다', (tester) async {
      setScreenSize(tester, const Size(800, 1400));
      final storage = await createTestStorage();
      await pumpSettings(tester, storage);

      await tester.tap(find.text('백업 주기'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('매주'));
      await tester.pumpAndSettle();

      expect(storage.autoBackupFrequency, AutoBackupFrequency.weekly);
    });

    testWidgets('마지막 성공과 최근 실패가 함께 표시된다', (tester) async {
      setScreenSize(tester, const Size(800, 1400));
      final storage = await createTestStorage();
      final successAt = DateTime(2026, 7, 20, 15, 20);
      await storage.recordAutoBackupSuccess(successAt);
      await storage.recordAutoBackupFailure(
        attemptAt: DateTime(2026, 7, 23, 9),
        code: AutoBackupFailureCode.directoryMissing,
      );
      await storage.setAutoBackupEnabled(true);
      await storage.setAutoBackupDirectoryPath(tempDir.path);

      await pumpSettings(tester, storage);

      expect(find.textContaining('마지막 성공'), findsOneWidget);
      expect(find.textContaining('최근 시도 실패'), findsOneWidget);
      expect(find.text('백업 실패 · 폴더 접근을 확인해주세요'), findsOneWidget);
    });

    testWidgets('지금 백업을 누르면 즉시 실행되고 성공 SnackBar가 표시된다', (tester) async {
      setScreenSize(tester, const Size(800, 1400));
      final storage = await createTestStorage();
      await storage.setAutoBackupEnabled(true);
      await storage.setAutoBackupDirectoryPath(tempDir.path);

      final notifier = await pumpSettings(tester, storage);
      await tester.tap(find.text('지금 백업'));
      await settleRealIO(tester, isDone: () => !notifier.state.isBackingUp);

      expect(find.text('지금 백업했어요.'), findsOneWidget);
      expect(storage.autoBackupLastSuccessAt, isNotNull);
    });

    testWidgets('지금 백업 중에는 버튼이 "백업하는 중..."으로 바뀌고 중복 탭이 차단된다', (tester) async {
      setScreenSize(tester, const Size(800, 1400));
      final storage = await createTestStorage();
      await storage.setAutoBackupEnabled(true);
      await storage.setAutoBackupDirectoryPath(tempDir.path);

      final notifier = await pumpSettings(tester, storage);
      // pump 없이 tap만 걸어 backupNow()가 아직 끝나지 않은 프레임을 관찰한다.
      await tester.tap(find.text('지금 백업'));
      await tester.pump();

      expect(find.text('백업하는 중...'), findsOneWidget);
      expect(find.text('지금 백업'), findsNothing);

      await settleRealIO(tester, isDone: () => !notifier.state.isBackingUp);
      expect(find.text('지금 백업'), findsOneWidget);
    });
  });

  group('미지원 플랫폼', () {
    testWidgets('토글이 비활성화되고 안내 문구가 표시되며 수동 백업은 그대로 사용 가능하다', (tester) async {
      setScreenSize(tester, const Size(800, 1400));
      final storage = await createTestStorage();
      await pumpSettings(tester, storage, isSupported: () => false);

      final switchTile = tester.widget<SwitchListTile>(
        find.widgetWithText(SwitchListTile, '자동 백업'),
      );
      expect(switchTile.value, isFalse);
      expect(switchTile.onChanged, isNull);
      expect(
        find.text('이 플랫폼에서는 폴더 자동 백업을 지원하지 않아요. 아래 수동 백업을 사용해주세요.'),
        findsOneWidget,
      );
      expect(find.text('백업 폴더'), findsNothing);
      expect(find.text('백업 주기'), findsNothing);
      expect(find.text('마지막 백업'), findsNothing);
      expect(find.text('백업 내보내기'), findsOneWidget);
      expect(find.text('백업 가져오기'), findsOneWidget);
    });
  });
}
