import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:human_status/models/asset_snapshot.dart';
import 'package:human_status/models/transaction.dart';
import 'package:human_status/providers/profile_provider.dart';
import 'package:human_status/services/banksalad_import_coordinator.dart';
import 'package:human_status/services/storage_service.dart';

import 'helpers/test_app.dart';

Transaction _tx(String id, {DateTime? date}) => Transaction(
  id: id,
  type: TransactionType.expense,
  category: '식비',
  memo: '',
  amount: 1000,
  date: date ?? DateTime(2026, 7, 10),
  createdAt: date ?? DateTime(2026, 7, 10),
);

AssetSnapshot _snapshot(
  String id,
  DateTime importedAt, {
  double totalAssets = 0,
}) => AssetSnapshot(
  id: id,
  importedAt: importedAt,
  assetsByCategory: const {},
  liabilitiesByCategory: const {},
  totalAssets: totalAssets,
  totalLiabilities: 0,
);

/// A [StorageService] that throws on the Nth call (1-indexed) of a chosen
/// write method and otherwise behaves normally — same shape as
/// financial_transaction_atomicity_test.dart's `_ThrowsOnNthSaveGoalStorage`,
/// applied to the three writes [BanksaladImportCoordinator] makes. Also
/// supports simulating a *partial* batch write before the failure, since
/// `saveTransactions` is a single batched call and the coordinator's
/// restore logic must not assume it's all-or-nothing.
class _FaultyStorage extends StorageService {
  _FaultyStorage({super.inMemory});

  int throwOnSaveTransactionsCall = 0;
  int throwOnSaveAssetSnapshotCall = 0;
  int throwOnDeleteAssetSnapshotCall = 0;
  bool partialTransactionWrite = false;

  int _saveTransactionsCalls = 0;
  int _saveAssetSnapshotCalls = 0;
  int _deleteAssetSnapshotCalls = 0;

  /// Zeroes the call counters — tests that seed pre-existing data through
  /// these same methods before arming a `throwOnXCall` must call this first,
  /// so "call N" means the Nth call made by the import itself, not by setup.
  void resetCallCounts() {
    _saveTransactionsCalls = 0;
    _saveAssetSnapshotCalls = 0;
    _deleteAssetSnapshotCalls = 0;
  }

  @override
  Future<void> saveTransactions(List<Transaction> transactions) async {
    _saveTransactionsCalls++;
    if (_saveTransactionsCalls == throwOnSaveTransactionsCall) {
      if (partialTransactionWrite && transactions.isNotEmpty) {
        // Half the batch actually lands before the simulated failure — the
        // restore path must notice these from storage, not assume nothing
        // was written just because the call as a whole threw.
        final half = (transactions.length / 2).ceil();
        await super.saveTransactions(transactions.take(half).toList());
      }
      throw StateError(
        'simulated saveTransactions failure (call $_saveTransactionsCalls)',
      );
    }
    await super.saveTransactions(transactions);
  }

  @override
  Future<void> saveAssetSnapshot(AssetSnapshot snapshot) async {
    _saveAssetSnapshotCalls++;
    if (_saveAssetSnapshotCalls == throwOnSaveAssetSnapshotCall) {
      throw StateError(
        'simulated saveAssetSnapshot failure (call $_saveAssetSnapshotCalls)',
      );
    }
    await super.saveAssetSnapshot(snapshot);
  }

  @override
  Future<void> deleteAssetSnapshot(String id) async {
    _deleteAssetSnapshotCalls++;
    if (_deleteAssetSnapshotCalls == throwOnDeleteAssetSnapshotCall) {
      throw StateError(
        'simulated deleteAssetSnapshot failure (call $_deleteAssetSnapshotCalls)',
      );
    }
    await super.deleteAssetSnapshot(id);
  }
}

/// Blocks the first call to [saveTransactions] until released — lets a test
/// prove a second [BanksaladImportCoordinator.importCombined] call issued
/// while the first is still in flight queues behind it instead of
/// interleaving writes. Same `entered`/`release` shape as
/// completion_reward_integrity_test.dart's `_HoldsThenThrowsAchievementService`.
class _HoldsStorage extends StorageService {
  _HoldsStorage({super.inMemory});

  final Completer<void> entered = Completer<void>();
  final Completer<void> release = Completer<void>();
  final List<String> callLog = [];
  bool _first = true;

  @override
  Future<void> saveTransactions(List<Transaction> transactions) async {
    final ids = transactions.map((t) => t.id).join(',');
    callLog.add('start:$ids');
    if (_first) {
      _first = false;
      entered.complete();
      await release.future;
    }
    await super.saveTransactions(transactions);
    callLog.add('end:$ids');
  }
}

void main() {
  group('BanksaladImportCoordinator — 원자성/롤백', () {
    test('거래 저장이 실패하면 거래가 하나도 남지 않는다', () async {
      final storage = _FaultyStorage(inMemory: true);
      await storage.init();
      addTearDown(Hive.close);
      storage.throwOnSaveTransactionsCall = 1;

      final container = ProviderContainer(
        overrides: [storageServiceProvider.overrideWithValue(storage)],
      );
      addTearDown(container.dispose);
      final coordinator = container.read(banksaladImportCoordinatorProvider);

      await expectLater(
        coordinator.importCombined(
          transactions: [_tx('t1'), _tx('t2')],
          snapshot: null,
        ),
        throwsA(isA<StateError>()),
      );

      expect(storage.getTransactions(), isEmpty);
    });

    test('거래 저장 도중 일부만 기록된 뒤 실패해도, 이미 기록된 거래까지 전부 롤백된다', () async {
      final storage = _FaultyStorage(inMemory: true);
      await storage.init();
      addTearDown(Hive.close);
      storage.throwOnSaveTransactionsCall = 1;
      storage.partialTransactionWrite = true;

      final container = ProviderContainer(
        overrides: [storageServiceProvider.overrideWithValue(storage)],
      );
      addTearDown(container.dispose);
      final coordinator = container.read(banksaladImportCoordinatorProvider);

      final txs = [_tx('t1'), _tx('t2'), _tx('t3'), _tx('t4')];
      await expectLater(
        coordinator.importCombined(transactions: txs, snapshot: null),
        throwsA(isA<StateError>()),
      );

      // t1/t2 landed before the simulated failure — the restore step must
      // discover and remove them by diffing storage, not by assuming the
      // whole batch either fully landed or fully didn't.
      expect(storage.getTransactions(), isEmpty);
    });

    test('기존 스냅샷 삭제 도중 실패하면 거래도 롤백되고 기존 스냅샷은 그대로 남는다', () async {
      final storage = _FaultyStorage(inMemory: true);
      await storage.init();
      addTearDown(Hive.close);

      final today = DateTime.now();
      await storage.saveAssetSnapshot(
        _snapshot('old', today, totalAssets: 500),
      );
      storage.throwOnDeleteAssetSnapshotCall = 1;

      final container = ProviderContainer(
        overrides: [storageServiceProvider.overrideWithValue(storage)],
      );
      addTearDown(container.dispose);
      final coordinator = container.read(banksaladImportCoordinatorProvider);

      await expectLater(
        coordinator.importCombined(
          transactions: [_tx('t1')],
          snapshot: _snapshot('new', today, totalAssets: 900),
        ),
        throwsA(isA<StateError>()),
      );

      expect(storage.getTransactions(), isEmpty);
      final snaps = storage.getAssetSnapshots();
      expect(snaps.map((s) => s.id), ['old']);
      expect(snaps.single.totalAssets, 500);
    });

    test('같은 날짜 스냅샷이 여럿일 때 일부만 지운 뒤 실패해도 전부 원래대로 복원된다', () async {
      final storage = _FaultyStorage(inMemory: true);
      await storage.init();
      addTearDown(Hive.close);

      final today = DateTime.now();
      await storage.saveAssetSnapshot(
        _snapshot('oldA', today, totalAssets: 100),
      );
      await storage.saveAssetSnapshot(
        _snapshot('oldB', today, totalAssets: 200),
      );
      // The first deleteAssetSnapshot call (oldA) succeeds; the second
      // (oldB) fails — proving the restore doesn't just re-add "the"
      // deleted snapshot but reconciles every one that's actually missing.
      storage.throwOnDeleteAssetSnapshotCall = 2;

      final container = ProviderContainer(
        overrides: [storageServiceProvider.overrideWithValue(storage)],
      );
      addTearDown(container.dispose);
      final coordinator = container.read(banksaladImportCoordinatorProvider);

      await expectLater(
        coordinator.importCombined(
          transactions: const [],
          snapshot: _snapshot('new', today, totalAssets: 999),
        ),
        throwsA(isA<StateError>()),
      );

      final snaps = storage.getAssetSnapshots();
      expect(snaps.map((s) => s.id).toSet(), {'oldA', 'oldB'});
      expect(snaps.firstWhere((s) => s.id == 'oldA').totalAssets, 100);
      expect(snaps.firstWhere((s) => s.id == 'oldB').totalAssets, 200);
    });

    test('새 스냅샷 저장이 실패하면 지워졌던 기존 스냅샷이 복원되고 거래도 롤백된다', () async {
      final storage = _FaultyStorage(inMemory: true);
      await storage.init();
      addTearDown(Hive.close);

      final today = DateTime.now();
      await storage.saveAssetSnapshot(
        _snapshot('old', today, totalAssets: 300),
      );
      storage.resetCallCounts();
      storage.throwOnSaveAssetSnapshotCall = 1;

      final container = ProviderContainer(
        overrides: [storageServiceProvider.overrideWithValue(storage)],
      );
      addTearDown(container.dispose);
      final coordinator = container.read(banksaladImportCoordinatorProvider);

      await expectLater(
        coordinator.importCombined(
          transactions: [_tx('t1')],
          snapshot: _snapshot('new', today, totalAssets: 777),
        ),
        throwsA(isA<StateError>()),
      );

      expect(storage.getTransactions(), isEmpty);
      final snaps = storage.getAssetSnapshots();
      expect(snaps.map((s) => s.id), ['old']);
      expect(snaps.single.totalAssets, 300);
    });

    test('정상적으로 가져오면 배치 중복을 제거하고 오늘자 스냅샷을 반영한다', () async {
      final storage = await createTestStorage();
      final today = DateTime.now();
      final yesterday = today.subtract(const Duration(days: 1));
      await storage.saveAssetSnapshot(
        _snapshot('oldToday', today, totalAssets: 10),
      );
      await storage.saveAssetSnapshot(
        _snapshot('otherDay', yesterday, totalAssets: 20),
      );

      final container = ProviderContainer(
        overrides: [storageServiceProvider.overrideWithValue(storage)],
      );
      addTearDown(container.dispose);
      final coordinator = container.read(banksaladImportCoordinatorProvider);

      await coordinator.importCombined(
        transactions: [_tx('t1'), _tx('t2')],
        snapshot: _snapshot('new', today, totalAssets: 50),
      );

      expect(storage.getTransactions().map((t) => t.id).toSet(), {'t1'});
      expect(storage.getAssetSnapshots().map((s) => s.id).toSet(), {
        'new',
        'otherDay',
      });
    });
  });

  group('BanksaladImportCoordinator — 동시 실행 직렬화', () {
    test('두 번의 가져오기가 동시에 들어와도 서로 끼어들지 않고 순서대로 처리된다', () async {
      final storage = _HoldsStorage(inMemory: true);
      await storage.init();
      addTearDown(Hive.close);

      final container = ProviderContainer(
        overrides: [storageServiceProvider.overrideWithValue(storage)],
      );
      addTearDown(container.dispose);
      final coordinator = container.read(banksaladImportCoordinatorProvider);

      final future1 = coordinator.importCombined(
        transactions: [_tx('t1')],
        snapshot: null,
      );
      // Call 1 is now inside saveTransactions, holding the coordinator's
      // lock, blocked on its own gate.
      await storage.entered.future;

      final future2 = coordinator.importCombined(
        transactions: [_tx('t2', date: DateTime(2026, 7, 11))],
        snapshot: null,
      );
      // If serialization were broken, call 2's write would already show up
      // here even though call 1 hasn't released yet.
      await Future<void>.delayed(Duration.zero);
      expect(storage.callLog, ['start:t1']);

      storage.release.complete();
      await Future.wait([future1, future2]);

      expect(storage.callLog, ['start:t1', 'end:t1', 'start:t2', 'end:t2']);
      expect(storage.getTransactions().map((t) => t.id).toSet(), {'t1', 't2'});
    });

    test('동일한 논리 거래가 동시에 들어오면 잠금 안에서 다시 중복 제거한다', () async {
      final storage = _HoldsStorage(inMemory: true);
      await storage.init();
      addTearDown(Hive.close);

      final container = ProviderContainer(
        overrides: [storageServiceProvider.overrideWithValue(storage)],
      );
      addTearDown(container.dispose);
      final coordinator = container.read(banksaladImportCoordinatorProvider);

      final future1 = coordinator.importCombined(
        transactions: [_tx('first-id')],
        snapshot: null,
      );
      await storage.entered.future;

      // A separate parse of the same workbook produces a fresh UUID even
      // though date/category/amount are identical. Caller-side duplicate
      // filtering can therefore admit both while the first import is pending.
      final future2 = coordinator.importCombined(
        transactions: [_tx('second-id')],
        snapshot: null,
      );

      storage.release.complete();
      await Future.wait([future1, future2]);

      expect(storage.callLog, ['start:first-id', 'end:first-id']);
      expect(storage.getTransactions().map((t) => t.id), ['first-id']);
    });
  });
}
