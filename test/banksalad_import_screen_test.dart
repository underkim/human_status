import 'dart:async';
import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:human_status/models/asset_snapshot.dart';
import 'package:human_status/models/transaction.dart';
import 'package:human_status/screens/banksalad_import_screen.dart';
import 'package:human_status/services/banksalad_import_coordinator.dart';
import 'package:human_status/services/storage_service.dart';

import 'helpers/test_app.dart';

/// A real, minimal Banksalad-shaped .xlsx: one ledger row and one asset
/// category, matching the exact header/column shapes
/// TransactionImportService.parseBanksaladLedger and
/// AssetSnapshotImportService.parse expect (see their own unit tests) — so
/// the screen's full pick-through-confirm pipeline runs unmocked past the
/// picker step.
Uint8List _validWorkbookBytes() {
  final excel = Excel.createExcel();

  final ledger = excel['가계부 내역'];
  for (final row in [
    ['날짜', '시간', '타입', '대분류', '소분류', '내용', '금액', '화폐', '결제수단', '메모'],
    ['2026-07-01', '13:22', '지출', '식비', '카페', '스타벅스', '5000', 'KRW', '카드', ''],
  ]) {
    ledger.appendRow(row.map((s) => TextCellValue(s)).toList());
  }

  final status = excel['3.재무현황'];
  for (final row in [
    ['1.고객정보', '', '', '', '', '', '', ''],
    ['설명', '', '', '', '', '', '', ''],
    ['이름', '', '', '', '', '', '', ''],
    ['3.재무현황', '', '', '', '', '', '', ''],
    ['설명', '', '', '', '', '', '', ''],
    ['자산', '', '', '', '부채', '', '', ''],
    ['항목', '상품명', '', '금액', '항목', '상품명', '', '금액'],
    ['카테고리A', '상품1', '', '1000', '', '', '', ''],
    ['총자산', '', '', '9999', '9999', '9999', '총부채', ''],
  ]) {
    status.appendRow(row.map((s) => TextCellValue(s)).toList());
  }

  return Uint8List.fromList(excel.encode()!);
}

/// A [BanksaladImportCoordinator] whose [importCombined] blocks on a gate
/// the test controls, and can be told to fail once released — same shape as
/// finance_transaction_ui_robustness_test.dart's `_GatedTransactionsNotifier`.
class _GatedImportCoordinator extends BanksaladImportCoordinator {
  _GatedImportCoordinator(super.ref);

  int calls = 0;
  bool shouldThrow = false;
  Completer<void> gate = Completer<void>();

  @override
  Future<void> importCombined({
    required List<Transaction> transactions,
    required AssetSnapshot? snapshot,
  }) async {
    calls++;
    await gate.future;
    if (shouldThrow) throw StateError('simulated import failure');
    await super.importCombined(transactions: transactions, snapshot: snapshot);
  }
}

Future<void> _pushScreen(
  WidgetTester tester,
  StorageService storage, {
  Future<(String, Uint8List)?> Function()? debugPickFile,
  List<Override> overrides = const [],
}) async {
  await pumpApp(
    tester,
    storage,
    Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) =>
                    BanksaladImportScreen(debugPickFile: debugPickFile),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
    overrides: overrides,
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void _popScreen(WidgetTester tester) {
  Navigator.of(tester.element(find.byType(BanksaladImportScreen))).pop();
}

void main() {
  group('BanksaladImportScreen — 파일 선택 중 화면 이탈 방어', () {
    testWidgets('파일 선택이 대기 중일 때 화면을 벗어나도 예외가 나지 않는다', (tester) async {
      final storage = await createTestStorage();
      final gate = Completer<(String, Uint8List)?>();

      await _pushScreen(tester, storage, debugPickFile: () => gate.future);

      await tester.tap(find.text('파일 선택'));
      await tester.pump();

      // Leave the screen while the (fake) picker is still pending — the OS
      // file picker can stay open this long in practice.
      _popScreen(tester);
      await tester.pumpAndSettle();
      expect(find.byType(BanksaladImportScreen), findsNothing);

      // Resolve the picker after disposal — must not touch setState/context
      // on the now-disposed State.
      gate.complete(('file.xlsx', _validWorkbookBytes()));
      await tester.pump();
      await tester.pump();

      expect(tester.takeException(), isNull);
    });

    testWidgets('파일 읽기가 취소되면(피커가 null을 반환하면) 화면을 벗어나도 예외가 나지 않는다', (
      tester,
    ) async {
      final storage = await createTestStorage();
      final gate = Completer<(String, Uint8List)?>();

      await _pushScreen(tester, storage, debugPickFile: () => gate.future);

      await tester.tap(find.text('파일 선택'));
      await tester.pump();

      _popScreen(tester);
      await tester.pumpAndSettle();

      gate.complete(null);
      await tester.pump();

      expect(tester.takeException(), isNull);
    });
  });

  group('BanksaladImportScreen — 가져오기 확정 중 화면 이탈 방어', () {
    testWidgets('가져오기가 대기 중일 때 화면을 벗어나도 예외가 나지 않는다', (tester) async {
      final storage = await createTestStorage();
      late _GatedImportCoordinator coordinator;

      await _pushScreen(
        tester,
        storage,
        debugPickFile: () async => ('file.xlsx', _validWorkbookBytes()),
        overrides: [
          banksaladImportCoordinatorProvider.overrideWith((ref) {
            coordinator = _GatedImportCoordinator(ref);
            return coordinator;
          }),
        ],
      );

      await tester.tap(find.text('파일 선택'));
      await tester.pumpAndSettle();
      expect(find.text('가져오기 확정'), findsOneWidget);

      await tester.tap(find.text('가져오기 확정'));
      await tester.pump();
      expect(coordinator.calls, 1);

      // Back out of the screen while the import is still gated — the
      // coordinator call keeps running detached from the (disposed) State.
      _popScreen(tester);
      await tester.pumpAndSettle();
      expect(find.byType(BanksaladImportScreen), findsNothing);

      coordinator.gate.complete();
      await tester.pump();
      await tester.pump();

      expect(tester.takeException(), isNull);
      // The import itself must still have gone through even though the
      // screen that triggered it is gone — disposal safety is about the UI
      // callbacks, not about cancelling already-committed writes.
      expect(storage.getTransactions(), hasLength(1));
    });

    testWidgets('가져오기가 대기 중일 때 화면을 벗어난 뒤 실패해도 예외가 나지 않는다', (tester) async {
      final storage = await createTestStorage();
      late _GatedImportCoordinator coordinator;

      await _pushScreen(
        tester,
        storage,
        debugPickFile: () async => ('file.xlsx', _validWorkbookBytes()),
        overrides: [
          banksaladImportCoordinatorProvider.overrideWith((ref) {
            coordinator = _GatedImportCoordinator(ref);
            coordinator.shouldThrow = true;
            return coordinator;
          }),
        ],
      );

      await tester.tap(find.text('파일 선택'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('가져오기 확정'));
      await tester.pump();

      _popScreen(tester);
      await tester.pumpAndSettle();

      coordinator.gate.complete();
      await tester.pump();
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(storage.getTransactions(), isEmpty);
    });
  });

  group('BanksaladImportScreen — 정상 흐름', () {
    testWidgets('파일을 선택하고 확정하면 거래와 자산현황이 반영되고 화면이 닫힌다', (tester) async {
      final storage = await createTestStorage();

      await _pushScreen(
        tester,
        storage,
        debugPickFile: () async => ('file.xlsx', _validWorkbookBytes()),
      );

      await tester.tap(find.text('파일 선택'));
      await tester.pumpAndSettle();
      expect(find.textContaining('신규 1건'), findsOneWidget);

      await tester.tap(find.text('가져오기 확정'));
      await tester.pumpAndSettle();

      expect(find.byType(BanksaladImportScreen), findsNothing);
      expect(storage.getTransactions(), hasLength(1));
      expect(storage.getAssetSnapshots(), hasLength(1));
    });

    testWidgets('가져오기가 실패하면 화면이 열린 채로 오류 스낵바를 보여주고 다시 시도할 수 있다', (
      tester,
    ) async {
      final storage = await createTestStorage();
      late _GatedImportCoordinator coordinator;

      await _pushScreen(
        tester,
        storage,
        debugPickFile: () async => ('file.xlsx', _validWorkbookBytes()),
        overrides: [
          banksaladImportCoordinatorProvider.overrideWith((ref) {
            coordinator = _GatedImportCoordinator(ref);
            coordinator.shouldThrow = true;
            coordinator.gate.complete();
            return coordinator;
          }),
        ],
      );

      await tester.tap(find.text('파일 선택'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('가져오기 확정'));
      await tester.pumpAndSettle();

      expect(find.byType(BanksaladImportScreen), findsOneWidget);
      expect(find.textContaining('가져오기에 실패했어요'), findsOneWidget);
      expect(storage.getTransactions(), isEmpty);

      // The button re-enables (isImporting reset) so a retry is possible.
      coordinator.shouldThrow = false;
      coordinator.gate = Completer<void>();
      coordinator.gate.complete();
      await tester.tap(find.text('가져오기 확정'));
      await tester.pumpAndSettle();

      expect(find.byType(BanksaladImportScreen), findsNothing);
      expect(storage.getTransactions(), hasLength(1));
    });
  });
}
