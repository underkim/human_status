import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:human_status/providers/profile_provider.dart';
import 'package:human_status/services/storage_service.dart';
import 'package:human_status/theme/app_theme.dart';

/// Opens a StorageService on hive's in-memory backend: the real disk
/// backend's file IO never completes inside the widget-test FakeAsync zone,
/// and in-memory writes behave identically from the app code's perspective.
Future<StorageService> createTestStorage() async {
  final storage = StorageService(inMemory: true);
  await storage.init();
  // Closing drops the in-memory boxes so the next test starts empty.
  addTearDown(Hive.close);
  return storage;
}

/// Pumps [home] inside a MaterialApp with the app theme and the given
/// storage wired into Riverpod — the same setup main() performs.
/// [overrides] adds further provider overrides (e.g. a BackupService with
/// fault injectors pre-wired) alongside the storage override.
Future<void> pumpApp(
  WidgetTester tester,
  StorageService storage,
  Widget home, {
  List<Override> overrides = const [],
}) {
  return tester.pumpWidget(
    ProviderScope(
      overrides: [
        storageServiceProvider.overrideWithValue(storage),
        ...overrides,
      ],
      child: MaterialApp(theme: AppTheme.light, home: home),
    ),
  );
}

/// Fixes the logical screen size for the duration of the test, so
/// breakpoint-dependent layouts (bottom nav vs rail) are deterministic.
void setScreenSize(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}
