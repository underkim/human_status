import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:human_status/providers/observability_provider.dart';
import 'package:human_status/screens/settings_screen.dart';
import 'package:human_status/services/storage_service.dart';

import 'helpers/test_app.dart';

/// [StorageService] whose [setCrashReportingEnabled] can be made to fail
/// once — mirrors the `_FailingProfileStorage` pattern used elsewhere in
/// this suite for other boxes.
class _FailingConsentStorage extends StorageService {
  _FailingConsentStorage() : super(inMemory: true);

  bool failNextSave = false;

  @override
  Future<void> setCrashReportingEnabled(bool value) {
    if (failNextSave) {
      failNextSave = false;
      throw StateError('SENTINEL_CONSENT_SAVE_FAILURE');
    }
    return super.setCrashReportingEnabled(value);
  }
}

Future<_FailingConsentStorage> _createFailingConsentStorage() async {
  final storage = _FailingConsentStorage();
  await storage.init();
  addTearDown(Hive.close);
  return storage;
}

Finder get _crashReportingSwitch => find.widgetWithText(
  SwitchListTile,
  '익명 크래시 리포팅',
);

void main() {
  testWidgets('주간 리포트 알림 뒤, 추천 퀘스트 새로고침 앞에 렌더링되고 초기 switch는 꺼짐이다', (
    tester,
  ) async {
    final storage = await createTestStorage();
    final reporter = FakeCrashReporter();
    await pumpApp(
      tester,
      storage,
      const SettingsScreen(),
      overrides: [crashReporterProvider.overrideWithValue(reporter)],
    );

    final weeklyReport = tester.getCenter(find.text('주간 리포트 알림'));
    final crashReporting = tester.getCenter(find.text('익명 크래시 리포팅'));
    final refreshQuests = tester.getCenter(find.text('추천 퀘스트 새로고침'));

    expect(weeklyReport.dy, lessThan(crashReporting.dy));
    expect(crashReporting.dy, lessThan(refreshQuests.dy));

    final switchWidget = tester.widget<SwitchListTile>(_crashReportingSwitch);
    expect(switchWidget.value, isFalse);
    expect(reporter.initializeCallCount, 0);
  });

  testWidgets('switch를 탭한 뒤 확인 다이얼로그에서 취소하면 저장/초기화가 실행되지 않는다', (tester) async {
    final storage = await createTestStorage();
    final reporter = FakeCrashReporter();
    await pumpApp(
      tester,
      storage,
      const SettingsScreen(),
      overrides: [crashReporterProvider.overrideWithValue(reporter)],
    );

    await tester.tap(_crashReportingSwitch);
    await tester.pumpAndSettle();

    expect(find.text('익명 크래시 리포팅'), findsWidgets);
    expect(find.text('취소'), findsOneWidget);
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();

    expect(
      tester.widget<SwitchListTile>(_crashReportingSwitch).value,
      isFalse,
    );
    expect(storage.crashReportingEnabled, isFalse);
    expect(reporter.initializeCallCount, 0);
    expect(reporter.consentCalls, isEmpty);
  });

  testWidgets('동의하고 켜기 후 저장 성공 → 초기화 순서로 진행되고 subtitle이 켜짐으로 갱신된다', (
    tester,
  ) async {
    final storage = await createTestStorage();
    final reporter = FakeCrashReporter();
    await pumpApp(
      tester,
      storage,
      const SettingsScreen(),
      overrides: [crashReporterProvider.overrideWithValue(reporter)],
    );

    await tester.tap(_crashReportingSwitch);
    await tester.pumpAndSettle();
    await tester.tap(find.text('동의하고 켜기'));
    await tester.pumpAndSettle();

    expect(
      tester.widget<SwitchListTile>(_crashReportingSwitch).value,
      isTrue,
    );
    expect(find.text('켜짐 · 앱 오류와 기기·OS 정보를 Sentry로 보내요'), findsOneWidget);
    expect(storage.crashReportingEnabled, isTrue);
    expect(reporter.initializeCallCount, 1);
  });

  testWidgets('끄기 후 즉시 false로 보이고 저장/close가 호출되며 재펌프 뒤에도 false다', (tester) async {
    final storage = await createTestStorage();
    await storage.setCrashReportingEnabled(true);
    final reporter = FakeCrashReporter();
    await pumpApp(
      tester,
      storage,
      const SettingsScreen(),
      overrides: [crashReporterProvider.overrideWithValue(reporter)],
    );

    expect(
      tester.widget<SwitchListTile>(_crashReportingSwitch).value,
      isTrue,
    );

    await tester.tap(_crashReportingSwitch);
    await tester.pumpAndSettle();

    expect(
      tester.widget<SwitchListTile>(_crashReportingSwitch).value,
      isFalse,
    );
    expect(find.text('꺼짐 · 오류 정보가 외부로 전송되지 않아요'), findsOneWidget);
    expect(storage.crashReportingEnabled, isFalse);
    expect(reporter.consentCalls, [false]);

    await tester.pump();
    await tester.pump();
    expect(
      tester.widget<SwitchListTile>(_crashReportingSwitch).value,
      isFalse,
    );
  });

  testWidgets('켜기 저장 실패 시 SnackBar가 뜨고 switch는 꺼짐으로 유지된다', (tester) async {
    final storage = await _createFailingConsentStorage();
    storage.failNextSave = true;
    final reporter = FakeCrashReporter();
    await pumpApp(
      tester,
      storage,
      const SettingsScreen(),
      overrides: [crashReporterProvider.overrideWithValue(reporter)],
    );

    await tester.tap(_crashReportingSwitch);
    await tester.pumpAndSettle();
    await tester.tap(find.text('동의하고 켜기'));
    await tester.pumpAndSettle();

    expect(find.text('설정을 저장하지 못했어요. 잠시 후 다시 시도해주세요.'), findsOneWidget);
    expect(
      tester.widget<SwitchListTile>(_crashReportingSwitch).value,
      isFalse,
    );
    expect(reporter.initializeCallCount, 0);
  });

  testWidgets('켜기 저장은 성공했지만 SDK 초기화가 실패하면 세션 연결 실패 문구가 뜬다', (
    tester,
  ) async {
    final storage = await createTestStorage();
    final reporter = FakeCrashReporter()
      ..initializeError = Exception('network unavailable');
    await pumpApp(
      tester,
      storage,
      const SettingsScreen(),
      overrides: [crashReporterProvider.overrideWithValue(reporter)],
    );

    await tester.tap(_crashReportingSwitch);
    await tester.pumpAndSettle();
    await tester.tap(find.text('동의하고 켜기'));
    await tester.pumpAndSettle();

    expect(
      tester.widget<SwitchListTile>(_crashReportingSwitch).value,
      isTrue,
    );
    expect(storage.crashReportingEnabled, isTrue);
    expect(
      find.text('켜짐 · 이번 세션은 연결하지 못했어요. 다음 실행 때 다시 시도해요'),
      findsOneWidget,
    );
  });

  testWidgets('중복 탭은 무시된다(진행 중에는 switch가 비활성화)', (tester) async {
    final storage = await createTestStorage();
    final initGate = Completer<void>();
    final reporter = FakeCrashReporter()..initializeGate = initGate.future;
    await pumpApp(
      tester,
      storage,
      const SettingsScreen(),
      overrides: [crashReporterProvider.overrideWithValue(reporter)],
    );

    await tester.tap(_crashReportingSwitch);
    await tester.pumpAndSettle();
    await tester.tap(find.text('동의하고 켜기'));
    // reporter.initialize() is still gated open, so the change is
    // definitely still in flight — the switch must already be disabled and
    // a second tap must be a no-op.
    await tester.pump();

    final switchWidget = tester.widget<SwitchListTile>(_crashReportingSwitch);
    expect(switchWidget.onChanged, isNull);
    expect(reporter.initializeCallCount, 1);

    initGate.complete();
    await tester.pumpAndSettle();
    expect(reporter.initializeCallCount, 1);
    expect(
      tester.widget<SwitchListTile>(_crashReportingSwitch).onChanged,
      isNotNull,
    );
  });
}
