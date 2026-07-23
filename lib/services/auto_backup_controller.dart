import 'auto_backup_service.dart';
import 'auto_backup_target_access.dart';
import 'backup_service.dart';
import 'notification_service.dart';
import 'storage_service.dart';

/// Result of a user-triggered [AutoBackupController.backupNow] call — enough
/// for the settings screen to pick the right SnackBar copy without reaching
/// back into storage itself.
enum AutoBackupRunOutcome { ran, unsupported, disabled, noDirectory }

/// Drives automatic backups from the two opportunistic trigger points the
/// plan allows (app startup, after the daily refresh; and
/// `AppLifecycleState.resumed`) — never a background task that fires while
/// the app is fully closed (plan section 0/5.1). Composes
/// [AutoBackupService] (pure file IO) with [StorageService] (durable
/// enabled/directory/frequency/last-result state) and, best-effort,
/// [NotificationService] for a failure ping.
class AutoBackupController {
  AutoBackupController({
    required StorageService storage,
    required BackupService backupService,
    AutoBackupService? autoBackupService,
    NotificationService? notificationService,
    DateTime Function()? clock,
    bool Function()? isSupported,
    // ignore: prefer_initializing_formals
  }) : _storage = storage,
       // ignore: prefer_initializing_formals
       _backupService = backupService,
       _autoBackupService = autoBackupService ?? const AutoBackupService(),
       // ignore: prefer_initializing_formals
       _notificationService = notificationService,
       _clock = clock ?? DateTime.now,
       _isSupported = isSupported ?? (() => isAutoBackupSupportedPlatform);

  static const _retryBackoff = Duration(hours: 1);
  static const _failureNotifyThrottle = Duration(hours: 24);

  final StorageService _storage;
  final BackupService _backupService;
  final AutoBackupService _autoBackupService;
  final NotificationService? _notificationService;
  final DateTime Function() _clock;
  final bool Function() _isSupported;

  /// The currently-running attempt, if any. Concurrent callers (a startup
  /// sequence racing a resume event) share this instead of running twice.
  Future<void>? _inFlight;

  /// Runs a backup if one is currently due (enabled, supported, a directory
  /// is set, the frequency window has elapsed, and — after a prior failure —
  /// the 1-hour retry backoff has passed). A no-op future otherwise.
  Future<void> backupIfDue() {
    final inFlight = _inFlight;
    if (inFlight != null) return inFlight;
    if (!_dueNow()) return Future.value();
    return _run();
  }

  /// The user's explicit "지금 백업" action. Ignores the due/backoff window
  /// (plan 5.2: "사용자의 '지금 백업'은 backoff를 무시한다") but still shares
  /// the in-flight guard and refuses to run at all when unsupported,
  /// disabled, or unconfigured.
  Future<AutoBackupRunOutcome> backupNow() async {
    final inFlight = _inFlight;
    if (inFlight != null) await inFlight;

    if (!_isSupported()) return AutoBackupRunOutcome.unsupported;
    if (!_storage.autoBackupEnabled) return AutoBackupRunOutcome.disabled;
    final directoryPath = _storage.autoBackupDirectoryPath;
    if (directoryPath == null || directoryPath.isEmpty) {
      return AutoBackupRunOutcome.noDirectory;
    }

    await _run();
    return AutoBackupRunOutcome.ran;
  }

  bool _dueNow() {
    if (!_isSupported()) return false;
    if (!_storage.autoBackupEnabled) return false;
    final directoryPath = _storage.autoBackupDirectoryPath;
    if (directoryPath == null || directoryPath.isEmpty) return false;

    final now = _clock();
    final lastFailureAt = _storage.autoBackupLastFailureAt;
    if (lastFailureAt != null) {
      final sinceFailure = now.difference(lastFailureAt);
      if (sinceFailure.abs() < _retryBackoff && !sinceFailure.isNegative) {
        return false;
      }
    }

    return _autoBackupService.isDue(
      now: now,
      lastSuccessAt: _storage.autoBackupLastSuccessAt,
      frequency: _storage.autoBackupFrequency,
    );
  }

  Future<void> _run() {
    final future = _doRun();
    _inFlight = future;
    return future.whenComplete(() {
      if (identical(_inFlight, future)) _inFlight = null;
    });
  }

  Future<void> _doRun() async {
    final directoryPath = _storage.autoBackupDirectoryPath;
    if (directoryPath == null || directoryPath.isEmpty) return;
    final attemptAt = _clock();

    final result = await _autoBackupService.backupToDirectory(
      directoryPath: directoryPath,
      backupService: _backupService,
      attemptAt: attemptAt,
    );

    if (result.success) {
      try {
        await _storage.recordAutoBackupSuccess(attemptAt);
      } catch (_) {
        // The backup file itself exists on disk, but the app has no durable
        // record of it (plan 6.2's last row: a settings-write failure after
        // a real successful write is still reported as a failure). Record
        // this as a failure — rather than silently returning — so the
        // due/backoff logic and the "지금 백업" SnackBar both see it as
        // unresolved instead of losing track of what just happened.
        await _recordFailure(attemptAt, AutoBackupFailureCode.stateSaveFailed);
        return;
      }
      try {
        await _autoBackupService.pruneOldBackups(directoryPath);
      } catch (_) {
        // Non-fatal: pruning failure must never turn an already-recorded
        // success into a failure.
      }
      return;
    }

    await _recordFailure(
      attemptAt,
      result.failureCode ?? AutoBackupFailureCode.writeFailed,
    );
  }

  Future<void> _recordFailure(
    DateTime attemptAt,
    AutoBackupFailureCode code,
  ) async {
    try {
      await _storage.recordAutoBackupFailure(attemptAt: attemptAt, code: code);
    } catch (_) {
      return;
    }

    final notificationService = _notificationService;
    if (notificationService == null) return;

    final lastNotified = _storage.autoBackupLastFailureNotifiedAt;
    final shouldNotify =
        lastNotified == null ||
        attemptAt.difference(lastNotified).abs() >= _failureNotifyThrottle;
    if (!shouldNotify) return;

    try {
      await notificationService.showAutoBackupFailed();
      await _storage.recordAutoBackupFailureNotified(attemptAt);
    } catch (_) {
      // Best-effort notification only; must never fail an already-completed
      // backup attempt.
    }
  }
}
