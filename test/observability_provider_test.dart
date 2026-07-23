import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:human_status/providers/observability_provider.dart';
import 'package:human_status/services/storage_service.dart';

import 'helpers/test_app.dart';

/// [StorageService] whose [setCrashReportingEnabled] can be made to fail
/// once (mirrors the existing `_FailingProfileStorage` pattern used across
/// this test suite for other boxes).
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

Future<T> _init<T extends StorageService>(T storage) async {
  await storage.init();
  addTearDown(Hive.close);
  return storage;
}

void main() {
  test('기본 동의 값은 키가 없어도 false이고 reporter는 건드리지 않는다', () async {
    final storage = await createTestStorage();
    final reporter = FakeCrashReporter();
    final notifier = ObservabilityConsentNotifier(storage, reporter);

    expect(notifier.state.enabled, isFalse);
    expect(notifier.state.isChanging, isFalse);
    expect(reporter.initializeCallCount, 0);
    expect(reporter.consentCalls, isEmpty);
  });

  test('잘못된 타입의 저장 값은 fail-closed로 false를 반환한다', () async {
    final storage = await createTestStorage();
    // Simulates a corrupted/foreign value landing in the settings box.
    await storage.settingsBox.put('crashReportingEnabled', 'yes');

    expect(storage.crashReportingEnabled, isFalse);
  });

  test('켜기: 저장 성공 후 초기화가 정확히 한 번 실행되고 상태가 true로 갱신된다', () async {
    final storage = await createTestStorage();
    final reporter = FakeCrashReporter();
    final notifier = ObservabilityConsentNotifier(storage, reporter);

    final result = await notifier.setEnabled(true);

    expect(result, ConsentChangeResult.saved);
    expect(notifier.state.enabled, isTrue);
    expect(notifier.state.isChanging, isFalse);
    expect(storage.crashReportingEnabled, isTrue);
    expect(reporter.initializeCallCount, 1);
  });

  test('켜기: 저장 실패 시 false로 유지되고 초기화는 시도되지 않는다', () async {
    final storage = await _init(_FailingConsentStorage())
      ..failNextSave = true;
    final reporter = FakeCrashReporter();
    final notifier = ObservabilityConsentNotifier(storage, reporter);

    final result = await notifier.setEnabled(true);

    expect(result, ConsentChangeResult.saveFailed);
    expect(notifier.state.enabled, isFalse);
    expect(notifier.state.isChanging, isFalse);
    expect(storage.crashReportingEnabled, isFalse);
    expect(reporter.initializeCallCount, 0);
  });

  test('켜기: 초기화가 실패해도 동의는 유지된다(동의와 SDK 가용성 분리)', () async {
    final storage = await createTestStorage();
    final reporter = FakeCrashReporter()
      ..initializeError = Exception('network unavailable');
    final notifier = ObservabilityConsentNotifier(storage, reporter);

    final result = await notifier.setEnabled(true);

    expect(result, ConsentChangeResult.saved);
    expect(notifier.state.enabled, isTrue);
    expect(storage.crashReportingEnabled, isTrue);
    expect(reporter.initializeCallCount, 1);
    // The failure must still be visible to the UI even though consent
    // persisted and the change is reported as "saved".
    expect(notifier.state.sessionInitFailed, isTrue);
  });

  test('켜기: 초기화 성공 시 sessionInitFailed는 false다', () async {
    final storage = await createTestStorage();
    final reporter = FakeCrashReporter();
    final notifier = ObservabilityConsentNotifier(storage, reporter);

    await notifier.setEnabled(true);

    expect(notifier.state.sessionInitFailed, isFalse);
  });

  test('켜기: 실패했던 이전 시도 뒤 재시도가 성공하면 sessionInitFailed가 false로 리셋된다', () async {
    final storage = await createTestStorage();
    final reporter = FakeCrashReporter()
      ..initializeError = Exception('network unavailable');
    final notifier = ObservabilityConsentNotifier(storage, reporter);
    await notifier.setEnabled(true);
    expect(notifier.state.sessionInitFailed, isTrue);

    reporter.initializeError = null;
    await notifier.setEnabled(false);
    await notifier.setEnabled(true);

    expect(notifier.state.sessionInitFailed, isFalse);
  });

  test('끄기: gate가 저장/close보다 먼저 닫힌다', () async {
    final storage = await createTestStorage();
    await storage.setCrashReportingEnabled(true);
    final reporter = FakeCrashReporter();
    final notifier = ObservabilityConsentNotifier(storage, reporter);
    expect(notifier.state.enabled, isTrue);

    final result = await notifier.setEnabled(false);

    expect(result, ConsentChangeResult.saved);
    expect(notifier.state.enabled, isFalse);
    expect(storage.crashReportingEnabled, isFalse);
    // setConsent(false) is the gate-close call; it must happen exactly once
    // and never be followed by a re-open on the success path.
    expect(reporter.consentCalls, [false]);
  });

  test('끄기: 저장 실패 시 gate와 상태가 켜진 상태로 복원된다', () async {
    final storage = await _init(_FailingConsentStorage());
    await storage.setCrashReportingEnabled(true);
    storage.failNextSave = true;
    final reporter = FakeCrashReporter();
    final notifier = ObservabilityConsentNotifier(storage, reporter);
    expect(notifier.state.enabled, isTrue);

    final result = await notifier.setEnabled(false);

    expect(result, ConsentChangeResult.saveFailed);
    expect(notifier.state.enabled, isTrue);
    expect(notifier.state.isChanging, isFalse);
    // Storage save failed, so the persisted value never actually changed.
    expect(storage.crashReportingEnabled, isTrue);
    // Gate closed first, then reopened as compensation once the storage
    // write failed.
    expect(reporter.consentCalls, [false, true]);
  });

  test('isChanging 중에는 재진입 호출이 거부된다', () async {
    final storage = await createTestStorage();
    final gate = Completer<void>();
    final reporter = FakeCrashReporter()..initializeGate = gate.future;
    final notifier = ObservabilityConsentNotifier(storage, reporter);

    final first = notifier.setEnabled(true);
    // The first call is still awaiting reporter.initialize() (gated), so
    // state.isChanging must already be true.
    expect(notifier.state.isChanging, isTrue);
    final second = await notifier.setEnabled(true);
    expect(second, ConsentChangeResult.saveFailed);

    gate.complete();
    await first;
    expect(notifier.state.isChanging, isFalse);
  });
}
