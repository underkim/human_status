import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:human_status/providers/observability_provider.dart';
import 'package:human_status/providers/profile_provider.dart';
import 'package:human_status/services/crash_reporting_service.dart';
import 'package:human_status/services/storage_service.dart';
import 'package:human_status/theme/app_theme.dart';

/// Call-counting [CrashReporter] test double. Every method just records that
/// it was called (and, for the capture methods, always "sends" — unlike the
/// real [CrashReportingService] it does not gate on consent/init state
/// itself) so tests can assert wiring/ordering without ever touching Sentry.
/// [initializeError]/[captureThrows] let a test simulate a reporter that
/// fails, to verify callers stay safe regardless.
class FakeCrashReporter implements CrashReporter {
  int initializeCallCount = 0;
  int flutterErrorCallCount = 0;
  int errorCallCount = 0;
  int closeCallCount = 0;
  final List<bool> consentCalls = [];

  /// Awaited inside [initialize] before it resolves/throws, so a test can
  /// hold an "in flight" init open to observe intermediate state.
  Future<void>? initializeGate;
  Object? initializeError;
  Object? captureThrows;

  @override
  Future<void> initialize() async {
    initializeCallCount++;
    if (initializeGate != null) await initializeGate;
    if (initializeError != null) throw initializeError!;
  }

  @override
  void captureFlutterError(FlutterErrorDetails details) {
    flutterErrorCallCount++;
    if (captureThrows != null) throw captureThrows!;
  }

  @override
  void captureError(Object error, StackTrace stackTrace) {
    errorCallCount++;
    if (captureThrows != null) throw captureThrows!;
  }

  @override
  Future<void> setConsent(bool enabled) async {
    consentCalls.add(enabled);
  }

  @override
  Future<void> close() async {
    closeCallCount++;
  }
}

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
/// fault injectors pre-wired) alongside the storage override. A
/// [FakeCrashReporter] is always wired in by default (crash reporting is
/// unrelated to most tests using this helper) — pass an explicit
/// `crashReporterProvider.overrideWithValue(...)` in [overrides] to use a
/// specific fake instance instead. [disableAnimations] simulates the
/// platform's reduced-motion setting (`MediaQueryData.disableAnimations`) for
/// tests that need to assert the app's motion-reduced code paths; it
/// defaults to false so existing callers are unaffected.
Future<void> pumpApp(
  WidgetTester tester,
  StorageService storage,
  Widget home, {
  List<Override> overrides = const [],
  bool disableAnimations = false,
}) {
  return tester.pumpWidget(
    ProviderScope(
      overrides: [
        storageServiceProvider.overrideWithValue(storage),
        crashReporterProvider.overrideWithValue(FakeCrashReporter()),
        ...overrides,
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        home: home,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(disableAnimations: disableAnimations),
          child: child!,
        ),
      ),
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

/// Lets a just-triggered chain of real `dart:io` calls (e.g. auto-backup's
/// directory probe/write) actually run to completion, then flushes the
/// resulting widget rebuild.
///
/// `testWidgets` runs inside a `FakeAsync` zone, so `tester.pump()`/
/// `pumpAndSettle()` only ever advance a fake clock and flush that zone's own
/// microtask queue — they never give the real event loop a turn. Real
/// `dart:io` operations complete via the actual OS thread pool, and each step
/// of a multi-step chain (write → delete, or write → rename → read) needs its
/// own real event-loop turn before the *next* step even starts. A single
/// `tester.runAsync(() => Future.delayed(...))` only buys one such turn, so a
/// two-or-more-step chain stalls partway through. Alternating a short real
/// delay with a fake-zone microtask flush, inside one `runAsync` call, lets
/// each step unblock the next until the whole chain settles.
///
/// [isDone] must reflect the operation's *actual* completion — e.g.
/// `() => !notifier.state.isBackingUp` — rather than relying purely on a
/// fixed time budget, so this stays reliable on a slow/loaded CI runner
/// instead of racing an arbitrary iteration count. [timeout] is only a
/// safety net against a genuinely hung operation (a real bug), not the
/// success condition itself.
Future<void> settleRealIO(
  WidgetTester tester, {
  required bool Function() isDone,
  Duration step = const Duration(milliseconds: 20),
  Duration timeout = const Duration(seconds: 10),
}) async {
  await tester.runAsync(() async {
    final deadline = DateTime.now().add(timeout);
    while (!isDone() && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(step);
      await tester.pump();
    }
  });
  await tester.pumpAndSettle();
}
