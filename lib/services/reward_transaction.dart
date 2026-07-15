import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Serializes every reward-mutating operation (quest/goal completion) into a
/// single global critical section.
///
/// Dart itself is single-threaded, but a completion flow crosses several
/// `await`s (stat XP writes, quest/goal status writes, achievement checks)
/// that touch shared Hive boxes. Without this lock, two concurrent
/// completions — the same quest tapped twice before the UI rebuilds, or two
/// different quests that reward the same stat — can interleave between those
/// awaits, causing a lost update or a double award. Every completion entry
/// point acquires this lock before reading or writing any reward state and
/// holds it for the whole transaction (including any nested goal
/// auto-completion), so at most one completion is ever in flight at a time.
class AsyncLock {
  Future<void> _tail = Future.value();

  /// Runs [action] only after every previously-queued [synchronized] call on
  /// this lock has finished, so at most one [action] is ever running.
  Future<T> synchronized<T>(Future<T> Function() action) {
    final previous = _tail;
    final completer = Completer<void>();
    _tail = completer.future;
    // `whenComplete` both signals the next queued caller and forwards this
    // call's value/error to the single Future we return — chaining a
    // second, unobserved Future off of `previous.then(...)` here would let
    // Dart report its error as unhandled even though the caller awaits (and
    // may catch) the one we actually return.
    return previous.then((_) => action()).whenComplete(completer.complete);
  }
}

/// Shared across quest and goal completion so both go through the same
/// critical section — see [AsyncLock].
final rewardLockProvider = Provider<AsyncLock>((ref) => AsyncLock());

/// Accumulates undo steps for an in-progress reward transaction.
///
/// Each step should be registered *before* the mutation it undoes runs, so
/// that even a mutation that partially applies in memory before its Hive
/// write throws is still rolled back correctly. If the transaction fails,
/// [rollback] runs every step in reverse order (most recent first), on a
/// best-effort basis: a cleanup failure is swallowed so it never masks the
/// original error, which the caller is responsible for rethrowing after
/// calling [rollback].
class RollbackScope {
  final _undoSteps = <Future<void> Function()>[];

  void addUndo(Future<void> Function() undo) => _undoSteps.add(undo);

  Future<void> rollback() async {
    for (final undo in _undoSteps.reversed) {
      try {
        await undo();
      } catch (_) {
        // Best-effort: the original error already propagating out of the
        // transaction takes precedence over a cleanup failure.
      }
    }
  }
}
