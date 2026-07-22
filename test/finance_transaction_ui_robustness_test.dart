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
  // FinanceListView의 인라인 검색창이 다이얼로그 아래에서도 계속
  // 마운트돼 있으므로, 전역 인덱스 대신 다이얼로그 내부로 범위를 좁힌다.
  final dialogFields = find.descendant(
    of: find.byType(AlertDialog),
    matching: find.byType(TextField),
  );
  await tester.enterText(dialogFields.at(0), '식비'); // 카테고리
  await tester.enterText(dialogFields.at(2), '10000'); // 금액
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
      expect(find.text('거래를 저장하지 못했어요. 잠시 후 다시 시도해주세요.'), findsOneWidget);
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

    testWidgets('저장이 대기 중일 때 뒤로가기로 다이얼로그를 닫아도 실패 처리에서 예외가 나지 않는다', (
      tester,
    ) async {
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

      // '취소' 버튼은 저장 중 비활성화되지만, showDialog의 기본
      // barrierDismissible(바깥 탭)이나 시스템 뒤로가기는 그와 무관하게
      // 다이얼로그(라우트)를 곧장 pop할 수 있다 — 저장이 아직 게이트에
      // 걸려 있는 이 시점에 그 경로를 흉내낸다. 배리어를 실제로 탭하는
      // 대신 다이얼로그가 속한 Navigator에 직접 pop을 호출해, 탭 위치·
      // 배리어 겹침 같은 히트테스트 디테일과 무관하게 "라우트가 외부에서
      // 닫혔다"는 상황 자체를 결정적으로 재현한다.
      Navigator.of(tester.element(find.byType(AlertDialog))).pop();
      // 다이얼로그의 종료 트랜지션이 실제로 끝나 라우트가 트리에서 빠질
      // 때까지 기다린다 — 저장은 여전히 게이트에 걸려 있어 다른 타이머가
      // 없으므로 pumpAndSettle이 여기서 멈춰 있지 않는다.
      await tester.pumpAndSettle();
      expect(find.text('거래 추가'), findsNothing);

      // 이제 실패를 흘려보낸다: 다이얼로그(그 StatefulBuilder)는 이미
      // dispose됐으므로, catch 블록이 dialogContext.mounted를 확인하지
      // 않고 setState를 부르면 여기서 프레임워크 예외가 난다.
      notifier.gate.complete();
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('거래 추가'), findsNothing);
      expect(storage.getTransactions(), isEmpty);
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

    testWidgets(
      '확인창이 뜨기 전에 삭제 아이콘을 빠르게 두 번 눌러도 확인창은 하나만 뜨고, 확인 후 삭제는 한 번만 실행된다',
      (tester) async {
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

        // Invoke the row's onPressed callback directly, twice in a row with no
        // await/pump between the calls — this is the actual reproduction of
        // "확인창이 뜨기도 전에 두 번 누른" (both calls happen before
        // showDialog's Future for the first call has resolved). A raw
        // tester.tap() x2 doesn't work here: Flutter's hit-testing considers
        // the second tap a miss once the first tap is mid-flight (verified
        // empirically — it logs "would not hit test"), so it never reaches
        // onPressed at all and the test would pass vacuously regardless of the
        // guard. Calling onPressed directly reproduces the real race without
        // depending on tap-hit-testing timing.
        final iconButton = tester.widget<IconButton>(
          find.ancestor(
            of: find.byIcon(Icons.delete_outline),
            matching: find.byType(IconButton),
          ),
        );
        iconButton.onPressed!();
        iconButton.onPressed!();
        await tester.pumpAndSettle();

        expect(find.text('거래 삭제'), findsOneWidget);

        await tester.tap(find.widgetWithText(FilledButton, '삭제'));
        await tester.pump();
        notifier.gate.complete();
        await tester.pumpAndSettle();

        expect(notifier.deleteCalls, 1);
        expect(storage.getTransactions(), isEmpty);
      },
    );

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

      expect(find.text('거래를 삭제하지 못했어요. 잠시 후 다시 시도해주세요.'), findsOneWidget);
      expect(find.textContaining('StateError'), findsNothing);
      expect(find.textContaining('simulated'), findsNothing);
      // The transaction is still present (rollback restored it upstream;
      // here the mock never actually deleted it since it threw first).
      expect(storage.getTransactions(), hasLength(1));
    });
  });
}
