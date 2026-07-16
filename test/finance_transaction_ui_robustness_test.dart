import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:human_status/models/transaction.dart';
import 'package:human_status/providers/finance_provider.dart';
import 'package:human_status/providers/profile_provider.dart';
import 'package:human_status/screens/finance_screen.dart';
import 'package:human_status/services/storage_service.dart';

import 'helpers/test_app.dart';

/// A [TransactionsNotifier] whose [addTransaction]/[deleteTransaction] block
/// on a gate the test controls, and can be told to fail once released — lets
/// tests observe the UI mid-flight (button disabled, dialog still open)
/// without a real async race.
class _GatedTransactionsNotifier extends TransactionsNotifier {
  _GatedTransactionsNotifier(super.storage, super.ref);

  int addCalls = 0;
  int deleteCalls = 0;
  bool shouldThrow = false;
  Completer<void> gate = Completer<void>();

  @override
  Future<void> addTransaction(Transaction tx) async {
    addCalls++;
    await gate.future;
    if (shouldThrow) throw StateError('simulated add failure');
    await super.addTransaction(tx);
  }

  @override
  Future<void> deleteTransaction(String id) async {
    deleteCalls++;
    await gate.future;
    if (shouldThrow) throw StateError('simulated delete failure');
    await super.deleteTransaction(id);
  }
}

Future<void> _openAddDialog(WidgetTester tester) async {
  await tester.tap(find.byTooltip('거래 직접 추가'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField).at(0), '식비'); // 카테고리
  await tester.enterText(find.byType(TextField).at(2), '10000'); // 금액
}

void main() {
  group('거래 추가 다이얼로그 — 중복 탭/실패 방어', () {
    testWidgets('저장 중에는 추가 버튼을 다시 눌러도 두 번 제출되지 않는다', (tester) async {
      final storage = await createTestStorage();
      late _GatedTransactionsNotifier notifier;
      await pumpApp(
        tester,
        storage,
        const Scaffold(body: FinanceListView()),
        overrides: [
          transactionsProvider.overrideWith((ref) {
            notifier = _GatedTransactionsNotifier(
              ref.watch(storageServiceProvider),
              ref,
            );
            return notifier;
          }),
        ],
      );

      await _openAddDialog(tester);
      await tester.tap(find.widgetWithText(FilledButton, '추가'));
      await tester.pump();
      // Second tap while the first save is still in flight must be ignored
      // — the button is disabled during save.
      await tester.tap(find.widgetWithText(FilledButton, '추가'));
      await tester.pump();

      expect(notifier.addCalls, 1);

      notifier.gate.complete();
      await tester.pumpAndSettle();

      expect(find.text('거래 추가'), findsNothing);
    });

    testWidgets('저장에 실패하면 다이얼로그가 열린 채로 일반 오류 문구만 보여준다', (tester) async {
      final storage = await createTestStorage();
      late _GatedTransactionsNotifier notifier;
      await pumpApp(
        tester,
        storage,
        const Scaffold(body: FinanceListView()),
        overrides: [
          transactionsProvider.overrideWith((ref) {
            notifier = _GatedTransactionsNotifier(
              ref.watch(storageServiceProvider),
              ref,
            );
            notifier.shouldThrow = true;
            return notifier;
          }),
        ],
      );

      await _openAddDialog(tester);
      await tester.tap(find.widgetWithText(FilledButton, '추가'));
      await tester.pump();
      notifier.gate.complete();
      await tester.pumpAndSettle();

      // Dialog stays open so the user can retry without re-entering data.
      expect(find.text('거래 추가'), findsOneWidget);
      expect(find.text('거래를 저장하지 못했습니다. 잠시 후 다시 시도해주세요.'), findsOneWidget);
      // No raw exception detail (type name / message) reaches the UI.
      expect(find.textContaining('StateError'), findsNothing);
      expect(find.textContaining('simulated'), findsNothing);
      expect(storage.getTransactions(), isEmpty);

      // The retry path still works once the fault is gone.
      notifier.shouldThrow = false;
      notifier.gate = Completer<void>();
      await tester.tap(find.widgetWithText(FilledButton, '추가'));
      await tester.pump();
      notifier.gate.complete();
      await tester.pumpAndSettle();

      expect(find.text('거래 추가'), findsNothing);
      expect(storage.getTransactions(), hasLength(1));
    });
  });

  group('거래 삭제 — 중복 탭/실패 방어', () {
    Future<void> seedOneTransaction(StorageService storage) =>
        storage.saveTransaction(
          Transaction(
            id: 't1',
            type: TransactionType.expense,
            category: '식비',
            memo: '',
            amount: 5000,
            date: DateTime.now(),
            createdAt: DateTime.now(),
          ),
        );

    testWidgets('삭제가 진행 중인 행은 다시 눌러도 삭제가 두 번 들어가지 않는다', (tester) async {
      // 거래 행이 스크롤 뷰포트 밖에 있으면 Sliver가 아예 빌드하지 않는다 —
      // 화면을 충분히 키워 목록 전체가 한 프레임에 들어오게 한다.
      setScreenSize(tester, const Size(800, 2000));
      final storage = await createTestStorage();
      await seedOneTransaction(storage);
      late _GatedTransactionsNotifier notifier;
      await pumpApp(
        tester,
        storage,
        const Scaffold(body: FinanceListView()),
        overrides: [
          transactionsProvider.overrideWith((ref) {
            notifier = _GatedTransactionsNotifier(
              ref.watch(storageServiceProvider),
              ref,
            );
            return notifier;
          }),
        ],
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '삭제'));
      await tester.pump();

      // The row's delete icon is now disabled while the first delete is
      // still pending — tapping where it was must not queue a second call.
      await tester.tap(find.byIcon(Icons.delete_outline), warnIfMissed: false);
      await tester.pump();

      expect(notifier.deleteCalls, 1);

      notifier.gate.complete();
      await tester.pumpAndSettle();

      expect(storage.getTransactions(), isEmpty);
    });

    testWidgets('삭제에 실패하면 데이터가 복원된 채로 일반 오류 문구만 보여준다', (tester) async {
      setScreenSize(tester, const Size(800, 2000));
      final storage = await createTestStorage();
      await seedOneTransaction(storage);
      late _GatedTransactionsNotifier notifier;
      await pumpApp(
        tester,
        storage,
        const Scaffold(body: FinanceListView()),
        overrides: [
          transactionsProvider.overrideWith((ref) {
            notifier = _GatedTransactionsNotifier(
              ref.watch(storageServiceProvider),
              ref,
            );
            notifier.shouldThrow = true;
            return notifier;
          }),
        ],
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '삭제'));
      await tester.pump();
      notifier.gate.complete();
      await tester.pumpAndSettle();

      expect(find.text('거래를 삭제하지 못했습니다. 잠시 후 다시 시도해주세요.'), findsOneWidget);
      expect(find.textContaining('StateError'), findsNothing);
      expect(find.textContaining('simulated'), findsNothing);
      // The transaction is still present (rollback restored it upstream;
      // here the mock never actually deleted it since it threw first).
      expect(storage.getTransactions(), hasLength(1));
    });
  });
}
