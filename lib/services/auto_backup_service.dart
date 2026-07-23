import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:uuid/uuid.dart';

import 'backup_service.dart';
import 'storage_service.dart' show AutoBackupFailureCode, AutoBackupFrequency;

/// Normalizes a [FileSystemException] into a privacy-safe
/// [AutoBackupFailureCode] — never surfaces [e]'s message (which can
/// contain the absolute path) to callers. A top-level function (rather than
/// a private method) so tests can exercise the classification directly with
/// a crafted [FileSystemException]/[OSError], independent of whether the
/// host OS running the test suite can actually reproduce a full-disk or
/// permission-denied condition.
@visibleForTesting
AutoBackupFailureCode classifyAutoBackupFileSystemException(
  FileSystemException e,
) {
  final osError = e.osError;
  final code = osError?.errorCode;
  // POSIX ENOSPC=28; Windows ERROR_HANDLE_DISK_FULL=39, ERROR_DISK_FULL=112.
  if (code == 28 || code == 39 || code == 112) {
    return AutoBackupFailureCode.noSpace;
  }
  // POSIX EACCES=13, EROFS=30; Windows ERROR_ACCESS_DENIED=5.
  if (code == 13 || code == 30 || code == 5) {
    return AutoBackupFailureCode.permissionDenied;
  }
  final message = '${e.message} ${osError?.message ?? ''}'.toLowerCase();
  if (message.contains('no space') || message.contains('disk full')) {
    return AutoBackupFailureCode.noSpace;
  }
  if (message.contains('permission denied') ||
      message.contains('access is denied') ||
      message.contains('read-only')) {
    return AutoBackupFailureCode.permissionDenied;
  }
  return AutoBackupFailureCode.writeFailed;
}

/// Outcome of one [AutoBackupService.probeDirectory] call — a lightweight,
/// no-trace-left-behind check of whether a folder can currently be written
/// to, used both right after the user picks a folder and (implicitly, via
/// the write attempt itself) on every scheduled run.
class DirectoryProbeResult {
  final bool ok;
  final AutoBackupFailureCode? failureCode;

  const DirectoryProbeResult.ok() : ok = true, failureCode = null;

  const DirectoryProbeResult.failed(AutoBackupFailureCode this.failureCode)
    : ok = false;
}

/// Outcome of one [AutoBackupService.backupToDirectory] call. Deliberately
/// minimal (plan section 7): callers only need to know whether it succeeded,
/// when it was attempted/completed, and — on failure — a privacy-safe
/// failure code, never the raw exception or the file's absolute path.
class AutoBackupResult {
  final bool success;
  final DateTime attemptAt;
  final DateTime? completedAt;
  final AutoBackupFailureCode? failureCode;

  const AutoBackupResult.success({
    required this.attemptAt,
    required this.completedAt,
  }) : success = true,
       failureCode = null;

  const AutoBackupResult.failure({
    required this.attemptAt,
    required AutoBackupFailureCode this.failureCode,
  }) : success = false,
       completedAt = null;
}

/// Writes/prunes automatic backup files inside a user-chosen folder. Pure
/// file-system logic: knows nothing about Hive settings, scheduling, or
/// notifications — those live in `AutoBackupController`. Reuses
/// [BackupService.encode]/[BackupService.inspect] rather than duplicating
/// backup serialization or validation (plan section 7: "그대로 재사용").
class AutoBackupService {
  static const filePrefix = 'human_status_auto_backup_';
  static const fileSuffix = '.json';
  static const defaultKeep = 7;

  const AutoBackupService();

  /// Checks that [directoryPath] exists and is currently writable, without
  /// leaving anything behind on success or failure. Used right after the
  /// user picks a folder (and when re-enabling with a previously-picked
  /// folder), so a bad choice is caught before the setting is saved.
  Future<DirectoryProbeResult> probeDirectory(String directoryPath) async {
    final dirCheck = await _checkDirectoryExists(directoryPath);
    if (dirCheck != null) return DirectoryProbeResult.failed(dirCheck);

    final probeFile = File(_join(directoryPath, '.human_status_probe_${_uuid.v4()}.tmp'));
    try {
      await probeFile.writeAsString('probe', flush: true);
      await probeFile.delete();
      return const DirectoryProbeResult.ok();
    } on FileSystemException catch (e) {
      await _bestEffortDelete(probeFile.path);
      return DirectoryProbeResult.failed(
        classifyAutoBackupFileSystemException(e),
      );
    } catch (_) {
      await _bestEffortDelete(probeFile.path);
      return const DirectoryProbeResult.failed(AutoBackupFailureCode.writeFailed);
    }
  }

  /// Runs one backup: encode → write to a unique temp file in the same
  /// folder → flush → rename to the final name → re-read and
  /// [BackupService.inspect] the result. Anything failing before the final
  /// inspect leaves no trace of a bad file under the real backup name (plan
  /// section 6.1); [attemptAt] is captured by the caller so scheduling
  /// decisions and the written filename always agree on "now".
  Future<AutoBackupResult> backupToDirectory({
    required String directoryPath,
    required BackupService backupService,
    required DateTime attemptAt,
  }) async {
    final dirCheck = await _checkDirectoryExists(directoryPath);
    if (dirCheck != null) {
      return AutoBackupResult.failure(attemptAt: attemptAt, failureCode: dirCheck);
    }

    final String jsonStr;
    try {
      jsonStr = backupService.encode();
    } catch (_) {
      return AutoBackupResult.failure(
        attemptAt: attemptAt,
        failureCode: AutoBackupFailureCode.writeFailed,
      );
    }

    final finalPath = _join(directoryPath, _buildFileName(attemptAt));
    final tempPath = _join(
      directoryPath,
      '.human_status_auto_backup_${_uuid.v4()}.tmp',
    );
    final tempFile = File(tempPath);
    var renamed = false;

    try {
      final sink = tempFile.openWrite();
      try {
        sink.add(utf8.encode(jsonStr));
        await sink.flush();
      } finally {
        await sink.close();
      }

      await tempFile.rename(finalPath);
      renamed = true;

      // Re-read from disk (rather than trusting the in-memory jsonStr) so a
      // partial write from a sync client rewriting the file mid-flight, or
      // a rename that silently truncated on some filesystem, is actually
      // caught here instead of being reported as a success.
      final writtenStr = await File(finalPath).readAsString();
      backupService.inspect(writtenStr);

      return AutoBackupResult.success(attemptAt: attemptAt, completedAt: attemptAt);
    } on FileSystemException catch (e) {
      await _bestEffortDelete(renamed ? finalPath : tempPath);
      return AutoBackupResult.failure(
        attemptAt: attemptAt,
        failureCode: classifyAutoBackupFileSystemException(e),
      );
    } catch (_) {
      await _bestEffortDelete(renamed ? finalPath : tempPath);
      return AutoBackupResult.failure(
        attemptAt: attemptAt,
        failureCode: AutoBackupFailureCode.writeFailed,
      );
    }
  }

  /// Deletes all but the most recent [keep] automatic-backup files (matched
  /// by [filePrefix]/[fileSuffix], never manual exports or unrelated JSON)
  /// in [directoryPath]. Called only after a successful [backupToDirectory]
  /// — any failure here (a locked file, a listing error) is swallowed rather
  /// than thrown, so pruning can never turn an already-succeeded backup into
  /// a reported failure.
  Future<void> pruneOldBackups(
    String directoryPath, {
    int keep = defaultKeep,
  }) async {
    final dir = Directory(directoryPath);
    List<FileSystemEntity> entries;
    try {
      entries = await dir.list().toList();
    } catch (_) {
      return;
    }

    final autoBackups = <File>[];
    for (final entry in entries) {
      if (entry is! File) continue;
      final name = _basename(entry.path);
      if (name.startsWith(filePrefix) && name.endsWith(fileSuffix)) {
        autoBackups.add(entry);
      }
    }
    if (autoBackups.length <= keep) return;

    // The filename embeds a UTC timestamp down to the millisecond, so
    // lexical sort order matches chronological order without touching
    // filesystem mtimes (which some sync clients rewrite on their own
    // schedule when a file is re-synced).
    autoBackups.sort((a, b) => a.path.compareTo(b.path));
    final toDelete = autoBackups.sublist(0, autoBackups.length - keep);
    for (final file in toDelete) {
      try {
        await file.delete();
      } catch (_) {
        // Best-effort: one stubborn file (e.g. locked by a sync client)
        // must not stop the rest from being pruned.
      }
    }
  }

  /// Whether a backup is due, given only elapsed time since the last
  /// success — never the wall-clock time of day — so DST transitions and
  /// timezone changes can't cause a duplicate or skipped run (plan 5.2).
  bool isDue({
    required DateTime now,
    required DateTime? lastSuccessAt,
    required AutoBackupFrequency frequency,
  }) {
    if (lastSuccessAt == null) return true;
    final elapsed = now.difference(lastSuccessAt);
    if (elapsed.isNegative) {
      // The clock moved backwards (or lastSuccessAt is stamped in the
      // future). A implausibly large jump is treated as a corrupted/invalid
      // timestamp and forces exactly one run rather than waiting on a bogus
      // baseline forever; a small skew (NTP correction, DST) is treated as
      // "not due yet".
      return elapsed.abs() > const Duration(hours: 24);
    }
    final threshold = frequency == AutoBackupFrequency.daily
        ? const Duration(hours: 24)
        : const Duration(days: 7);
    return elapsed >= threshold;
  }

  static final _uuid = Uuid();

  Future<AutoBackupFailureCode?> _checkDirectoryExists(
    String directoryPath,
  ) async {
    try {
      if (await Directory(directoryPath).exists()) return null;
      return AutoBackupFailureCode.directoryMissing;
    } catch (_) {
      return AutoBackupFailureCode.directoryMissing;
    }
  }

  Future<void> _bestEffortDelete(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (_) {
      // Best-effort cleanup only; a failure here must never mask/replace
      // the real failure that triggered this cleanup attempt.
    }
  }

  String _buildFileName(DateTime attemptAt) {
    // UTC (not local time) so the filename — and therefore prune-by-name
    // sort order — stays monotonic across DST transitions and timezone
    // changes; the user-facing "마지막 백업" display uses local time
    // separately from the stored `lastSuccessAt` instant.
    final utc = attemptAt.toUtc();
    String pad(int n, [int width = 2]) => n.toString().padLeft(width, '0');
    final stamp =
        '${utc.year}${pad(utc.month)}${pad(utc.day)}_'
        '${pad(utc.hour)}${pad(utc.minute)}${pad(utc.second)}_'
        '${pad(utc.millisecond, 3)}';
    return '$filePrefix$stamp$fileSuffix';
  }

  String _join(String directoryPath, String fileName) {
    final separator = Platform.pathSeparator;
    return directoryPath.endsWith(separator)
        ? '$directoryPath$fileName'
        : '$directoryPath$separator$fileName';
  }

  String _basename(String path) {
    final normalized = path.replaceAll('\\', '/');
    final idx = normalized.lastIndexOf('/');
    return idx == -1 ? normalized : normalized.substring(idx + 1);
  }
}
