import 'package:file_selector/file_selector.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/auto_backup_controller.dart';
import '../services/auto_backup_service.dart';
import '../services/auto_backup_target_access.dart';
import '../services/storage_service.dart';
import 'backup_provider.dart';
import 'profile_provider.dart';

/// Replaces the platform folder picker in tests, the same seam pattern as
/// `SettingsScreen.debugPickBackupSource` — `file_selector`'s platform
/// channel isn't available under `flutter test`. Returns the picked
/// absolute path, or `null` if the user cancelled.
typedef DirectoryPicker = Future<String?> Function({String? initialDirectory});

Future<String?> _defaultDirectoryPicker({String? initialDirectory}) {
  return getDirectoryPath(initialDirectory: initialDirectory);
}

/// Single shared [AutoBackupController] for the app session — the same
/// instance `main.dart`'s startup/resume hooks call `backupIfDue()` on and
/// [autoBackupProvider] calls `backupNow()` on, so their in-flight guard is
/// never duplicated across two separate controller objects (plan 5.1: "한
/// 인스턴스만 구성한다").
final autoBackupControllerProvider = Provider<AutoBackupController>((ref) {
  return AutoBackupController(
    storage: ref.watch(storageServiceProvider),
    backupService: ref.watch(backupServiceProvider),
    notificationService: ref.watch(notificationServiceProvider),
  );
});

/// Outcome of a settings-driven change (toggle, folder pick, frequency
/// pick), for the settings screen to choose the right SnackBar copy.
enum AutoBackupActionResult { success, cancelled, probeFailed, saveFailed }

/// Immutable snapshot of automatic-backup state for the settings screen.
/// Mirrors [StorageService]'s auto-backup getters, refreshed by
/// [AutoBackupNotifier.reload] after any change.
class AutoBackupState {
  const AutoBackupState({
    required this.isSupported,
    required this.enabled,
    required this.directoryPath,
    required this.frequency,
    required this.lastSuccessAt,
    required this.lastAttemptAt,
    required this.lastFailureCode,
    required this.lastFailureAt,
    this.isChangingSettings = false,
    this.isBackingUp = false,
  });

  final bool isSupported;
  final bool enabled;
  final String? directoryPath;
  final AutoBackupFrequency frequency;
  final DateTime? lastSuccessAt;
  final DateTime? lastAttemptAt;
  final AutoBackupFailureCode? lastFailureCode;
  final DateTime? lastFailureAt;

  /// True while a toggle/folder/frequency change is being probed/persisted —
  /// the settings screen disables the relevant controls to prevent a
  /// re-entrant tap racing the in-flight change (same pattern as
  /// `ObservabilityConsentState.isChanging`).
  final bool isChangingSettings;

  /// True while a "지금 백업" run (or a startup/resume-triggered run
  /// observed via [AutoBackupNotifier.backupNow]) is in flight.
  final bool isBackingUp;

  /// True when the most recent attempt (successful or not) recorded a
  /// failure that hasn't since been superseded by a later success.
  bool get hasUnresolvedFailure =>
      lastFailureAt != null &&
      (lastSuccessAt == null || lastFailureAt!.isAfter(lastSuccessAt!));

  AutoBackupState copyWith({
    bool? isSupported,
    bool? enabled,
    Object? directoryPath = _unset,
    AutoBackupFrequency? frequency,
    Object? lastSuccessAt = _unset,
    Object? lastAttemptAt = _unset,
    Object? lastFailureCode = _unset,
    Object? lastFailureAt = _unset,
    bool? isChangingSettings,
    bool? isBackingUp,
  }) {
    return AutoBackupState(
      isSupported: isSupported ?? this.isSupported,
      enabled: enabled ?? this.enabled,
      directoryPath: identical(directoryPath, _unset)
          ? this.directoryPath
          : directoryPath as String?,
      frequency: frequency ?? this.frequency,
      lastSuccessAt: identical(lastSuccessAt, _unset)
          ? this.lastSuccessAt
          : lastSuccessAt as DateTime?,
      lastAttemptAt: identical(lastAttemptAt, _unset)
          ? this.lastAttemptAt
          : lastAttemptAt as DateTime?,
      lastFailureCode: identical(lastFailureCode, _unset)
          ? this.lastFailureCode
          : lastFailureCode as AutoBackupFailureCode?,
      lastFailureAt: identical(lastFailureAt, _unset)
          ? this.lastFailureAt
          : lastFailureAt as DateTime?,
      isChangingSettings: isChangingSettings ?? this.isChangingSettings,
      isBackingUp: isBackingUp ?? this.isBackingUp,
    );
  }
}

/// Sentinel distinguishing "not passed" from "explicitly passed null" for
/// the nullable fields in [AutoBackupState.copyWith].
const _unset = Object();

/// Reactive access to automatic-backup settings/status, backing the
/// settings screen's "자동 백업" section. Owns the folder picker and
/// probe/save sequencing; the actual scheduled runs (startup/resume) go
/// through the shared [autoBackupControllerProvider] instance directly, not
/// through this notifier.
final autoBackupProvider =
    StateNotifierProvider<AutoBackupNotifier, AutoBackupState>((ref) {
      return AutoBackupNotifier(
        storage: ref.watch(storageServiceProvider),
        controller: ref.watch(autoBackupControllerProvider),
      );
    });

class AutoBackupNotifier extends StateNotifier<AutoBackupState> {
  AutoBackupNotifier({
    required StorageService storage,
    required AutoBackupController controller,
    AutoBackupService? autoBackupService,
    DirectoryPicker? directoryPicker,
    bool Function()? isSupported,
    // ignore: prefer_initializing_formals
  }) : _storage = storage,
       // ignore: prefer_initializing_formals
       _controller = controller,
       _autoBackupService = autoBackupService ?? const AutoBackupService(),
       _directoryPicker = directoryPicker ?? _defaultDirectoryPicker,
       _isSupported = isSupported ?? (() => isAutoBackupSupportedPlatform),
       super(
         _readState(
           storage,
           isSupported ?? (() => isAutoBackupSupportedPlatform),
         ),
       );

  final StorageService _storage;
  final AutoBackupController _controller;
  final AutoBackupService _autoBackupService;
  final DirectoryPicker _directoryPicker;
  final bool Function() _isSupported;

  static AutoBackupState _readState(
    StorageService storage,
    bool Function() isSupported,
  ) {
    return AutoBackupState(
      isSupported: isSupported(),
      enabled: storage.autoBackupEnabled,
      directoryPath: storage.autoBackupDirectoryPath,
      frequency: storage.autoBackupFrequency,
      lastSuccessAt: storage.autoBackupLastSuccessAt,
      lastAttemptAt: storage.autoBackupLastAttemptAt,
      lastFailureCode: storage.autoBackupLastFailureCode,
      lastFailureAt: storage.autoBackupLastFailureAt,
    );
  }

  /// Re-reads every field from storage, preserving the current transient
  /// `isChangingSettings`/`isBackingUp` flags (the caller manages those
  /// around this call).
  void reload() {
    state = _readState(
      _storage,
      _isSupported,
    ).copyWith(
      isChangingSettings: state.isChangingSettings,
      isBackingUp: state.isBackingUp,
    );
  }

  /// Opens the folder picker and, on a non-cancelled pick, probes it for
  /// write access before saving — a failed probe never touches the stored
  /// path (plan 3.1: "성공한 경우에만 설정을 저장한다").
  Future<AutoBackupActionResult> selectDirectory() async {
    if (state.isChangingSettings) return AutoBackupActionResult.saveFailed;
    state = state.copyWith(isChangingSettings: true);
    try {
      final picked = await _directoryPicker(
        initialDirectory: state.directoryPath,
      );
      if (picked == null) return AutoBackupActionResult.cancelled;

      final probe = await _autoBackupService.probeDirectory(picked);
      if (!probe.ok) return AutoBackupActionResult.probeFailed;

      try {
        await _storage.setAutoBackupDirectoryPath(picked);
      } catch (_) {
        return AutoBackupActionResult.saveFailed;
      }
      state = state.copyWith(directoryPath: picked);
      return AutoBackupActionResult.success;
    } finally {
      state = state.copyWith(isChangingSettings: false);
    }
  }

  /// Turns automatic backup on/off. Turning it on with no folder selected
  /// yet opens the picker first (plan 3.1: "토글을 켤 때 폴더가 없으면 즉시
  /// 폴더 선택기를 연다"); either way, a directory must pass
  /// [AutoBackupService.probeDirectory] before `enabled` is actually
  /// persisted as `true`. Turning it off only stops future runs — existing
  /// backup files and the stored directory/frequency are left alone.
  Future<AutoBackupActionResult> setEnabled(bool value) async {
    if (state.isChangingSettings) return AutoBackupActionResult.saveFailed;
    state = state.copyWith(isChangingSettings: true);
    try {
      if (!value) {
        try {
          await _storage.setAutoBackupEnabled(false);
        } catch (_) {
          return AutoBackupActionResult.saveFailed;
        }
        state = state.copyWith(enabled: false);
        return AutoBackupActionResult.success;
      }

      var directoryPath = state.directoryPath;
      if (directoryPath == null || directoryPath.isEmpty) {
        final picked = await _directoryPicker(initialDirectory: null);
        if (picked == null) return AutoBackupActionResult.cancelled;
        directoryPath = picked;
      }

      final probe = await _autoBackupService.probeDirectory(directoryPath);
      if (!probe.ok) return AutoBackupActionResult.probeFailed;

      try {
        await _storage.setAutoBackupDirectoryPath(directoryPath);
        await _storage.setAutoBackupEnabled(true);
      } catch (_) {
        return AutoBackupActionResult.saveFailed;
      }
      state = state.copyWith(enabled: true, directoryPath: directoryPath);
      return AutoBackupActionResult.success;
    } finally {
      state = state.copyWith(isChangingSettings: false);
    }
  }

  Future<AutoBackupActionResult> setFrequency(
    AutoBackupFrequency frequency,
  ) async {
    if (state.isChangingSettings) return AutoBackupActionResult.saveFailed;
    state = state.copyWith(isChangingSettings: true);
    try {
      try {
        await _storage.setAutoBackupFrequency(frequency);
      } catch (_) {
        return AutoBackupActionResult.saveFailed;
      }
      state = state.copyWith(frequency: frequency);
      return AutoBackupActionResult.success;
    } finally {
      state = state.copyWith(isChangingSettings: false);
    }
  }

  /// The "지금 백업" action — delegates to the shared
  /// [AutoBackupController.backupNow], then reloads so the last-success/
  /// failure fields reflect the outcome immediately.
  Future<AutoBackupRunOutcome> backupNow() async {
    if (state.isBackingUp) return AutoBackupRunOutcome.disabled;
    state = state.copyWith(isBackingUp: true);
    try {
      final outcome = await _controller.backupNow();
      reload();
      return outcome;
    } finally {
      state = state.copyWith(isBackingUp: false);
    }
  }
}
