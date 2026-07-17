import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/asset_snapshot.dart';
import '../models/transaction.dart';
import '../providers/asset_snapshot_provider.dart';
import '../providers/finance_provider.dart';
import '../providers/profile_provider.dart';
import 'reward_transaction.dart';
import 'transaction_import_service.dart';

/// Applies a combined Banksalad import (new transactions + a same-day asset
/// snapshot replacement) as a single unit from the user's perspective.
///
/// [BanksaladImportScreen] parses the file and decides *what* to import;
/// this coordinator owns *how* — so the screen never has to reason about
/// partial failure or concurrent imports itself.
///
/// Two guarantees this provides that [TransactionsNotifier.importTransactions]
/// and [AssetSnapshotsNotifier] don't individually offer:
///
/// - **Serialization**: every call goes through [_lock] (a dedicated
///   [AsyncLock], not the shared reward lock — a stuck/slow import must never
///   block quest/goal completion elsewhere in the app), so two imports
///   triggered back-to-back (e.g. a double-tap that slips past the screen's
///   own `_isImporting` guard) can never interleave their writes.
/// - **All-or-nothing**: if any step fails partway — including a failure
///   that already landed some transactions or already deleted a same-day
///   snapshot before throwing — [_restore] reconciles storage back to
///   exactly its pre-import contents before rethrowing. It does this by
///   diffing against storage's actual post-failure state rather than
///   assuming how much of the failed step applied, so it's correct whether
///   the underlying write failed before touching storage, after finishing,
///   or somewhere in between.
class BanksaladImportCoordinator {
  BanksaladImportCoordinator(this.ref);

  final Ref ref;
  final AsyncLock _lock = AsyncLock();

  bool _isSameDate(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  /// Imports [transactions] (already de-duplicated by the caller) and, if
  /// [snapshot] is given, replaces any existing snapshot(s) imported earlier
  /// today with it. Either both succeed or neither leaves a trace.
  Future<void> importCombined({
    required List<Transaction> transactions,
    required AssetSnapshot? snapshot,
  }) {
    return _lock.synchronized(() => _importLocked(transactions, snapshot));
  }

  Future<void> _importLocked(
    List<Transaction> transactions,
    AssetSnapshot? snapshot,
  ) async {
    final txNotifier = ref.read(transactionsProvider.notifier);
    final assetNotifier = ref.read(assetSnapshotsProvider.notifier);

    // The screen filters duplicates for its preview, but that result can be
    // stale by the time this call reaches the lock (for example, when two
    // screens import the same workbook concurrently). Re-check against
    // storage inside the critical section so the first completed import is
    // visible to every queued import before it writes.
    final transactionsToImport = TransactionImportService.filterDuplicates(
      transactions,
      ref.read(storageServiceProvider).getTransactions(),
    );

    // Captured before any mutation so a mid-failure restore has an exact
    // pre-import set to reconcile back to, regardless of which of these
    // steps actually reached storage before the failure.
    final today = DateTime.now();
    final preexistingSameDaySnapshots = snapshot == null
        ? const <AssetSnapshot>[]
        : ref
              .read(assetSnapshotsProvider)
              .where((s) => _isSameDate(s.importedAt, today))
              .toList();
    final importedTxIds = transactionsToImport.map((t) => t.id).toSet();

    try {
      if (transactionsToImport.isNotEmpty) {
        await txNotifier.importTransactions(transactionsToImport);
      }
      if (snapshot != null) {
        for (final existing in preexistingSameDaySnapshots) {
          await assetNotifier.deleteSnapshot(existing.id);
        }
        await assetNotifier.importSnapshot(snapshot);
      }
    } catch (_) {
      await _restore(
        txNotifier: txNotifier,
        assetNotifier: assetNotifier,
        importedTxIds: importedTxIds,
        preexistingSameDaySnapshots: preexistingSameDaySnapshots,
        newSnapshotId: snapshot?.id,
      );
      rethrow;
    }
  }

  /// Reconciles storage back to its exact pre-import contents after a failed
  /// [_importLocked] run. Each step is diffed against storage's current
  /// state — not assumed from where the failure was thrown — so this is
  /// correct whichever step failed and however far it got. Best-effort: a
  /// restore step's own failure is swallowed (never masks the original
  /// error the caller is already rethrowing) but every other step is still
  /// attempted, matching [RollbackScope]'s convention elsewhere in the app.
  Future<void> _restore({
    required TransactionsNotifier txNotifier,
    required AssetSnapshotsNotifier assetNotifier,
    required Set<String> importedTxIds,
    required List<AssetSnapshot> preexistingSameDaySnapshots,
    required String? newSnapshotId,
  }) async {
    final storage = ref.read(storageServiceProvider);

    final currentTxIds = storage.getTransactions().map((t) => t.id).toSet();
    for (final id in importedTxIds) {
      if (!currentTxIds.contains(id)) continue;
      try {
        await txNotifier.deleteTransaction(id);
      } catch (_) {
        // Best-effort — see doc comment.
      }
    }

    final currentSnapshotIds = storage
        .getAssetSnapshots()
        .map((s) => s.id)
        .toSet();

    if (newSnapshotId != null && currentSnapshotIds.contains(newSnapshotId)) {
      try {
        await assetNotifier.deleteSnapshot(newSnapshotId);
      } catch (_) {
        // Best-effort — see doc comment.
      }
    }

    final afterNewSnapshotCleanup = storage
        .getAssetSnapshots()
        .map((s) => s.id)
        .toSet();
    for (final original in preexistingSameDaySnapshots) {
      if (afterNewSnapshotCleanup.contains(original.id)) continue;
      try {
        await assetNotifier.importSnapshot(original);
      } catch (_) {
        // Best-effort — see doc comment.
      }
    }
  }
}

final banksaladImportCoordinatorProvider = Provider<BanksaladImportCoordinator>(
  (ref) => BanksaladImportCoordinator(ref),
);
