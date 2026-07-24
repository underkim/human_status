import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart' as path_provider;

import '../providers/profile_provider.dart' show storageServiceProvider;
import 'storage_service.dart';

/// Thrown by [QuestCompletionExecutionLock.synchronized] when the lock could
/// not be acquired before its timeout elapsed. Callers must treat this the
/// same as any other failed completion attempt — nothing was mutated — and
/// show a "처리하지 못했습니다. 앱에서 확인해 주세요." style message rather than a
/// generic crash.
class QuestCompletionLockTimeoutException implements Exception {
  const QuestCompletionLockTimeoutException();

  @override
  String toString() =>
      'QuestCompletionLockTimeoutException: could not acquire the quest '
      'completion execution lock in time';
}

/// An acquired lock grant. [release] must be idempotent — callers always
/// invoke it from a `finally` block and it must never throw for having
/// already been released.
abstract class QuestCompletionLockHandle {
  Future<void> release();
}

/// Abstracts *how* the cross-process exclusive lock described in
/// `docs/plans/phase4_notification_action_plan.md` section 4.4 is actually
/// acquired, so tests (and Hive's `inMemory` test mode, which never touches
/// disk) can substitute [InMemoryQuestCompletionLockBackend] instead of real
/// file IO.
abstract class QuestCompletionLockBackend {
  /// Attempts to acquire the lock, retrying until it succeeds or [deadline]
  /// passes. Throws [QuestCompletionLockTimeoutException] on timeout and
  /// nothing else.
  Future<QuestCompletionLockHandle> acquire(DateTime deadline);
}

/// Production backend: a dedicated lock file (never a user data file) guarded
/// by the OS's advisory file lock.
///
/// IMPORTANT CAVEAT (see `RandomAccessFile.lock` in the Dart SDK docs): on
/// Linux/macOS/Android, advisory file locks are held at the *process* level,
/// not per file descriptor or per isolate — "several isolates in the same
/// process can obtain an exclusive lock on the same file." That means this
/// backend only actually serializes two genuinely separate OS processes
/// racing for the same file. Two isolates inside the *same* process (e.g. a
/// background notification-action isolate spawned while the foreground app
/// process is still alive) are NOT guaranteed to be excluded from each other
/// by this mechanism alone. This is exactly why the plan's section 4.4
/// Go/No-Go gate requires a real two-engine device/emulator integration test
/// before shipping background completion — it cannot be proven from unit
/// tests or from this comment alone.
///
/// [lockFilePathResolver] is resolved lazily (and cached) on first
/// [acquire] rather than eagerly, so constructing this backend never itself
/// requires an async plugin call.
///
/// CAVEAT ABOVE FIXED IN-PROCESS: the OS-level advisory lock alone cannot
/// exclude two callers *inside this same process/isolate* on Linux/macOS
/// (see caveat above) — a second `open()+lock()` from the very same process
/// simply succeeds instead of blocking, since the process already holds the
/// lock. Two same-isolate callers racing `QuestCompletionExecutionLock`
/// directly (before ever reaching the separate `rewardLockProvider`) must
/// still be serialized, so this backend layers an in-process FIFO queue
/// (identical in spirit to [InMemoryQuestCompletionLockBackend]) *underneath*
/// the OS file lock: only one in-process caller attempts the file lock at a
/// time, and the OS lock remains the only thing that excludes genuinely
/// separate processes from each other.
class FileQuestCompletionLockBackend implements QuestCompletionLockBackend {
  FileQuestCompletionLockBackend(
    this.lockFilePathResolver, {
    this.pollInterval = const Duration(milliseconds: 50),
  });

  final Future<String> Function() lockFilePathResolver;
  final Duration pollInterval;

  Future<String>? _pathFuture;

  Future<String> get _lockFilePath => _pathFuture ??= lockFilePathResolver();

  // In-process FIFO gate, mirroring InMemoryQuestCompletionLockBackend: grants
  // exactly one caller in this isolate the right to attempt the OS file lock
  // at a time.
  bool _inProcessLocked = false;
  final _inProcessWaiters = <Completer<void>>[];

  Future<void> _acquireInProcessSlot(DateTime deadline) async {
    if (!_inProcessLocked) {
      // No `await` between the check and the flip — nothing else can
      // interleave here under Dart's single-threaded-per-isolate guarantee.
      _inProcessLocked = true;
      return;
    }

    final waiter = Completer<void>();
    _inProcessWaiters.add(waiter);
    final remaining = deadline.difference(DateTime.now());
    if (remaining.isNegative || remaining == Duration.zero) {
      _inProcessWaiters.remove(waiter);
      throw const QuestCompletionLockTimeoutException();
    }
    try {
      await waiter.future.timeout(remaining);
    } on TimeoutException {
      _inProcessWaiters.remove(waiter);
      throw const QuestCompletionLockTimeoutException();
    }
    // The waiter was handed the slot directly (FIFO) by
    // `_releaseInProcessSlot` — re-checking `_inProcessLocked` here would
    // wrongly send an already-granted waiter back through the queue.
  }

  void _releaseInProcessSlot() {
    _inProcessLocked = false;
    if (_inProcessWaiters.isNotEmpty) {
      _inProcessLocked = true;
      _inProcessWaiters.removeAt(0).complete();
    }
  }

  @override
  Future<QuestCompletionLockHandle> acquire(DateTime deadline) async {
    await _acquireInProcessSlot(deadline);
    try {
      final path = await _lockFilePath;
      while (true) {
        RandomAccessFile? raf;
        try {
          // writeOnlyAppend: creates the file if missing, never truncates it
          // — this file's only purpose is to be lock()ed, its contents (if
          // any) are irrelevant, but truncating it on every open (as
          // FileMode.write would) is needless churn on a file another
          // process might currently hold open.
          raf = await File(path).open(mode: FileMode.writeOnlyAppend);
          // Non-blocking: throws immediately if another process holds the
          // lock, instead of queuing indefinitely inside the OS/event loop
          // where a later successful-but-abandoned acquisition could leak.
          await raf.lock(FileLock.exclusive);
          return _FileLockHandle(raf, this);
        } on FileSystemException {
          await raf?.close();
          if (!DateTime.now().isBefore(deadline)) {
            throw const QuestCompletionLockTimeoutException();
          }
          await Future<void>.delayed(pollInterval);
        }
      }
    } catch (_) {
      // The in-process slot must not leak if the OS-level acquisition
      // itself fails (e.g. timed out) — a later caller must still be able
      // to proceed.
      _releaseInProcessSlot();
      rethrow;
    }
  }
}

class _FileLockHandle implements QuestCompletionLockHandle {
  _FileLockHandle(this._raf, this._backend);

  final RandomAccessFile _raf;
  final FileQuestCompletionLockBackend _backend;
  bool _released = false;

  @override
  Future<void> release() async {
    if (_released) return;
    _released = true;
    try {
      await _raf.unlock();
    } finally {
      await _raf.close();
      _backend._releaseInProcessSlot();
    }
  }
}

/// In-memory backend used whenever real file IO isn't appropriate: Hive's
/// `inMemory: true` test mode (see [StorageService.inMemory]) and web (no
/// `dart:io` file locking there at all). Serializes calls with a FIFO queue
/// *within this isolate only* — it cannot and does not claim to serialize
/// across isolates/processes, which real production use relies on
/// [FileQuestCompletionLockBackend] for instead.
class InMemoryQuestCompletionLockBackend implements QuestCompletionLockBackend {
  bool _locked = false;
  final _waiters = <Completer<void>>[];

  @override
  Future<QuestCompletionLockHandle> acquire(DateTime deadline) async {
    if (!_locked) {
      // No `await` between the check and the flip, so nothing else can
      // interleave here — the usual single-threaded-Dart guarantee.
      _locked = true;
      return _InMemoryLockHandle(this);
    }

    final waiter = Completer<void>();
    _waiters.add(waiter);
    final remaining = deadline.difference(DateTime.now());
    if (remaining.isNegative || remaining == Duration.zero) {
      _waiters.remove(waiter);
      throw const QuestCompletionLockTimeoutException();
    }
    try {
      await waiter.future.timeout(remaining);
    } on TimeoutException {
      _waiters.remove(waiter);
      throw const QuestCompletionLockTimeoutException();
    }
    // _releaseAndWakeNext already set `_locked = true` and handed this
    // waiter the lock directly (FIFO) — re-checking `_locked` here would
    // wrongly send an already-granted waiter back through the queue.
    return _InMemoryLockHandle(this);
  }

  void _releaseAndWakeNext() {
    _locked = false;
    if (_waiters.isNotEmpty) {
      // Hand the lock directly to the next waiter (FIFO) so it never has to
      // re-race a fresh caller that arrived after it — first queued, first
      // served.
      _locked = true;
      _waiters.removeAt(0).complete();
    }
  }
}

class _InMemoryLockHandle implements QuestCompletionLockHandle {
  _InMemoryLockHandle(this._backend);

  final InMemoryQuestCompletionLockBackend _backend;
  bool _released = false;

  @override
  Future<void> release() async {
    if (_released) return;
    _released = true;
    _backend._releaseAndWakeNext();
  }
}

/// The cross-isolate/cross-process exclusive execution boundary required by
/// `docs/plans/phase4_notification_action_plan.md` section 4.4. Every quest
/// completion entry point — both the UI's [QuestsNotifier.completeQuest] and
/// the background notification-action handler — must acquire this lock
/// *before* the existing isolate-local `rewardLockProvider`. Lock order is
/// always "execution lock -> reward lock", never the reverse, to avoid a
/// deadlock between the two entry points.
class QuestCompletionExecutionLock {
  // Deliberately not `this._backend`: the field is private, but the
  // constructor parameter needs a public external name (mirrors
  // NotificationService's constructor for the same reason).
  QuestCompletionExecutionLock({
    required QuestCompletionLockBackend backend,
    this.timeout = const Duration(seconds: 5),
    // ignore: prefer_initializing_formals
  }) : _backend = backend;

  final QuestCompletionLockBackend _backend;

  /// How long [synchronized] waits to acquire the lock before giving up with
  /// [QuestCompletionLockTimeoutException]. Deliberately short — this guards
  /// interactive completion flows (a notification tap, a button press), not
  /// a background batch job, so a stuck lock must surface quickly rather
  /// than hang the caller.
  final Duration timeout;

  /// Runs [action] only after acquiring the lock, and always releases it
  /// afterwards — including when [action] throws — before rethrowing.
  Future<T> synchronized<T>(Future<T> Function() action) async {
    final handle = await _backend.acquire(DateTime.now().add(timeout));
    try {
      return await action();
    } finally {
      await handle.release();
    }
  }
}

/// Resolves the dedicated lock file's path — a single fixed file under the
/// platform's app-support directory, never a user data file. Only called by
/// [FileQuestCompletionLockBackend], which [questCompletionExecutionLockProvider]
/// never selects on web or for in-memory storage, so this never runs there.
Future<String> defaultQuestCompletionLockFilePathResolver() async {
  final dir = await path_provider.getApplicationSupportDirectory();
  return '${dir.path}${Platform.pathSeparator}quest_completion.lock';
}

/// Builds the lock this app actually uses: an in-memory backend for
/// [StorageService.inMemory] (tests, and Hive's memory-only mode) or web
/// (`dart:io` file locking doesn't exist there), and the real file-based
/// backend everywhere else.
final questCompletionExecutionLockProvider =
    Provider<QuestCompletionExecutionLock>((ref) {
      final storage = ref.watch(storageServiceProvider);
      final backend = (storage.inMemory || kIsWeb)
          ? InMemoryQuestCompletionLockBackend()
          : FileQuestCompletionLockBackend(
              defaultQuestCompletionLockFilePathResolver,
            );
      return QuestCompletionExecutionLock(backend: backend);
    });
