import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:human_status/models/asset_snapshot.dart';
import 'package:human_status/providers/asset_snapshot_provider.dart';
import 'package:human_status/providers/profile_provider.dart';
import 'package:human_status/screens/asset_snapshot_screen.dart';

import 'helpers/test_app.dart';

/// deleteSnapshot 호출을 [gate]가 풀릴 때까지 붙잡아두고 호출 횟수를 세는
/// AssetSnapshotsNotifier — goals_screen_test.dart의
/// `_GatedGoalsListNotifier`와 같은 패턴.
class _GatedAssetSnapshotsNotifier extends AssetSnapshotsNotifier {
  _GatedAssetSnapshotsNotifier(super.storage);

  int deleteCalls = 0;
  Completer<void> gate = Completer<void>();

  @override
  Future<void> deleteSnapshot(String id) async {
    deleteCalls++;
    await gate.future;
    await super.deleteSnapshot(id);
  }
}

AssetSnapshot _snapshot(
  String id,
  DateTime importedAt, {
  double totalAssets = 1000,
  double totalLiabilities = 0,
}) => AssetSnapshot(
  id: id,
  importedAt: importedAt,
  assetsByCategory: {'현금': totalAssets},
  liabilitiesByCategory: totalLiabilities > 0 ? {'대출': totalLiabilities} : {},
  totalAssets: totalAssets,
  totalLiabilities: totalLiabilities,
);

void main() {
  testWidgets('가져온 자산현황이 없으면 빈 상태 안내가 나온다', (tester) async {
    final storage = await createTestStorage();
    await pumpApp(tester, storage, const AssetSnapshotListView());

    expect(find.textContaining('아직 가져온 자산 현황이 없어요'), findsOneWidget);
  });

  testWidgets('이력에서 삭제하면 확인 후 목록에서 사라진다', (tester) async {
    final storage = await createTestStorage();
    await storage.saveAssetSnapshot(_snapshot('s1', DateTime(2026, 7, 1)));
    await pumpApp(tester, storage, const AssetSnapshotListView());

    await tester.tap(find.widgetWithIcon(IconButton, Icons.delete_outline));
    await tester.pumpAndSettle();

    expect(find.textContaining('삭제할까요'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '삭제'));
    await tester.pumpAndSettle();

    expect(storage.getAssetSnapshots(), isEmpty);
    expect(find.textContaining('아직 가져온 자산 현황이 없어요'), findsOneWidget);
  });

  testWidgets('삭제 확인창이 뜨기 전에 같은 항목을 빠르게 두 번 눌러도 확인창은 하나만 뜨고 삭제는 한 번만 반영된다', (
    tester,
  ) async {
    final storage = await createTestStorage();
    await storage.saveAssetSnapshot(_snapshot('s1', DateTime(2026, 7, 1)));
    late _GatedAssetSnapshotsNotifier notifier;
    await pumpApp(
      tester,
      storage,
      const AssetSnapshotListView(),
      overrides: [
        assetSnapshotsProvider.overrideWith((ref) {
          notifier = _GatedAssetSnapshotsNotifier(
            ref.watch(storageServiceProvider),
          );
          return notifier;
        }),
      ],
    );

    // 확인창이 뜨기도 전에(동일 콜백을 두 번 직접 호출) — 두 번째 호출은
    // pending 가드에 막혀야 한다.
    final button = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.delete_outline),
    );
    button.onPressed!();
    button.onPressed!();
    await tester.pumpAndSettle();

    expect(find.textContaining('삭제할까요'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, '삭제'));
    await tester.pump();
    notifier.gate.complete();
    await tester.pumpAndSettle();

    expect(notifier.deleteCalls, 1);
    expect(storage.getAssetSnapshots(), isEmpty);
  });
}
