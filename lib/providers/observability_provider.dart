import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/crash_reporting_service.dart';
import '../services/storage_service.dart';
import 'profile_provider.dart';

/// The single [CrashReporter] instance for the app. Overridden in `main.dart`
/// with the same instance whose capture methods are already wired into the
/// global error handlers, so [ObservabilityConsentNotifier.setEnabled] and
/// the global handlers always gate/init the exact same reporter. Overridden
/// with a fake in tests.
final crashReporterProvider = Provider<CrashReporter>((ref) {
  throw UnimplementedError(
    'crashReporterProvider must be overridden in main()',
  );
});

class ObservabilityConsentState {
  const ObservabilityConsentState({
    required this.enabled,
    this.isChanging = false,
    this.sessionInitFailed = false,
  });

  final bool enabled;
  final bool isChanging;

  /// True when the most recent enable attempt persisted consent but
  /// [CrashReporter.initialize] itself failed for this session (e.g. no
  /// network at the moment of enabling). Consent and SDK availability are
  /// deliberately decoupled — see [ConsentChangeResult] — so this never
  /// blocks the toggle from showing "on"; it only lets the settings screen
  /// tell the user this session hasn't actually connected yet and a later
  /// launch will retry. Reset to `false` by any subsequent enable attempt
  /// that either succeeds or is turned off.
  final bool sessionInitFailed;

  ObservabilityConsentState copyWith({
    bool? enabled,
    bool? isChanging,
    bool? sessionInitFailed,
  }) => ObservabilityConsentState(
    enabled: enabled ?? this.enabled,
    isChanging: isChanging ?? this.isChanging,
    sessionInitFailed: sessionInitFailed ?? this.sessionInitFailed,
  );
}

/// Outcome of [ObservabilityConsentNotifier.setEnabled], for the settings
/// screen to pick the right confirmation/SnackBar copy. SDK init failures on
/// the enable path are deliberately *not* a distinct failure case here —
/// per the plan, consent persists and the reporter just retries later, so
/// from the UI's perspective enabling always "succeeds" once storage saves.
enum ConsentChangeResult { saved, saveFailed }

/// Reactive access to the anonymous crash-reporting opt-in. Initial state
/// mirrors [StorageService.crashReportingEnabled] (fail-closed to `false`).
final crashReportingConsentProvider =
    StateNotifierProvider<ObservabilityConsentNotifier, ObservabilityConsentState>((
      ref,
    ) {
      return ObservabilityConsentNotifier(
        ref.watch(storageServiceProvider),
        ref.watch(crashReporterProvider),
      );
    });

class ObservabilityConsentNotifier
    extends StateNotifier<ObservabilityConsentState> {
  ObservabilityConsentNotifier(this._storage, this._reporter)
    : super(ObservabilityConsentState(enabled: _storage.crashReportingEnabled));

  final StorageService _storage;
  final CrashReporter _reporter;

  /// Applies an explicit user choice. Callers must not invoke this again
  /// while [ObservabilityConsentState.isChanging] is true (the settings
  /// screen disables the switch for that reason); a re-entrant call is
  /// rejected as a no-op failure rather than racing the in-flight one.
  Future<ConsentChangeResult> setEnabled(bool value) async {
    if (state.isChanging) return ConsentChangeResult.saveFailed;
    state = state.copyWith(isChanging: true);

    if (value) {
      try {
        await _storage.setCrashReportingEnabled(true);
      } catch (_) {
        state = state.copyWith(isChanging: false);
        return ConsentChangeResult.saveFailed;
      }
      // Consent is now durably true regardless of what initialize() does
      // next — reflect it right away so the subtitle updates without
      // waiting for the SDK, while isChanging (and so the disabled switch)
      // stays true until the best-effort init below also finishes, so a
      // second tap can't race the in-flight change.
      state = state.copyWith(enabled: true);
      var sessionInitFailed = false;
      try {
        await _reporter.initialize();
      } catch (_) {
        // Best-effort: consent and SDK availability are deliberately
        // decoupled (see plan section 3) — a failed init here leaves the
        // reporter disabled for this session, and AppBootstrap retries on
        // the next launch since the stored consent is unaffected. The UI
        // still surfaces it via sessionInitFailed so the user isn't left
        // thinking this session is actually reporting.
        sessionInitFailed = true;
      }
      state = state.copyWith(
        isChanging: false,
        sessionInitFailed: sessionInitFailed,
      );
      return ConsentChangeResult.saved;
    }

    // Gate-first: block new events immediately, before storage or SDK
    // teardown even start.
    await _reporter.setConsent(false);
    try {
      await _storage.setCrashReportingEnabled(false);
    } catch (_) {
      // Compensate: storage still says "on", so reopen the gate and leave
      // the UI showing the unchanged (still-enabled) state.
      try {
        await _reporter.setConsent(true);
      } catch (_) {}
      state = state.copyWith(isChanging: false);
      return ConsentChangeResult.saveFailed;
    }
    state = const ObservabilityConsentState(enabled: false, isChanging: false);
    return ConsentChangeResult.saved;
  }
}
