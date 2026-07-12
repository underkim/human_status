import 'package:flutter_test/flutter_test.dart';
import 'package:human_status/services/asset_snapshot_import_service.dart';

/// Builds a synthetic row matrix mimicking the observed structure of
/// Banksalad's 현황.csv "3.재무현황" section (fake categories/amounts only).
List<List<String>> _sampleRows({List<List<String>>? assetRows, List<List<String>>? extraTail}) {
  return [
    ['1.고객정보', '', '', '', '', '', '', ''],
    ['설명', '', '', '', '', '', '', ''],
    ['이름', '', '', '', '', '', '', ''],
    ['3.재무현황', '', '', '', '', '', '', ''],
    ['설명', '', '', '', '', '', '', ''],
    ['자산', '', '', '', '부채', '', '', ''],
    ['항목', '상품명', '', '금액', '항목', '상품명', '', '금액'],
    ...(assetRows ?? []),
    ...(extraTail ?? []),
  ];
}

void main() {
  group('AssetSnapshotImportService.parse', () {
    test('parses a single-amount category row', () {
      final rows = _sampleRows(assetRows: [
        ['카테고리A', '상품1', '', '1000', '', '', '', ''],
        ['총자산', '', '', '9999', '9999', '9999', '총부채', ''],
      ]);
      final result = AssetSnapshotImportService.parse(rows);

      expect(result.isValid, isTrue);
      expect(result.snapshot!.assetsByCategory['카테고리A'], 1000);
      expect(result.snapshot!.totalAssets, 1000);
    });

    test('picks the 2nd numeric value when a row has multiple amounts', () {
      final rows = _sampleRows(assetRows: [
        ['카테고리B', '상품3', '', '500', '1500', '', '', ''],
        ['총자산', '', '', '9999', '9999', '9999', '총부채', ''],
      ]);
      final result = AssetSnapshotImportService.parse(rows);

      expect(result.snapshot!.assetsByCategory['카테고리B'], 1500);
    });

    test('carries the category label forward across blank rows', () {
      final rows = _sampleRows(assetRows: [
        ['카테고리A', '상품1', '', '1000', '', '', '', ''],
        ['', '상품2', '', '2000', '', '', '', ''],
        ['총자산', '', '', '9999', '9999', '9999', '총부채', ''],
      ]);
      final result = AssetSnapshotImportService.parse(rows);

      expect(result.snapshot!.assetsByCategory['카테고리A'], 3000);
    });

    test('skips categories with no product/amount data', () {
      final rows = _sampleRows(assetRows: [
        ['빈 카테고리', '', '', '', '', '', '', ''],
        ['카테고리A', '상품1', '', '1000', '', '', '', ''],
        ['총자산', '', '', '9999', '9999', '9999', '총부채', ''],
      ]);
      final result = AssetSnapshotImportService.parse(rows);

      expect(result.snapshot!.assetsByCategory.containsKey('빈 카테고리'), isFalse);
      expect(result.snapshot!.assetsByCategory['카테고리A'], 1000);
    });

    test('attributes a row to liabilities only when col4/col5 carry a real label', () {
      final rows = _sampleRows(assetRows: [
        // Asset row whose numbers spill into columns 3-4 (e.g. 매입/평가) —
        // must not be mistaken for a liability row just because col4 is numeric.
        ['투자성 자산', '펀드A', '', '800', '1200', '', '', ''],
        ['', '부채상품A', '', '', '부채카테고리', '부채상품A', '', '300'],
        ['총자산', '', '', '9999', '9999', '9999', '총부채', ''],
      ]);
      final result = AssetSnapshotImportService.parse(rows);

      expect(result.snapshot!.assetsByCategory['투자성 자산'], 1200);
      expect(result.snapshot!.liabilitiesByCategory['부채카테고리'], 300);
    });

    test('stops reading once it reaches the 총자산 summary row', () {
      final rows = _sampleRows(assetRows: [
        ['카테고리A', '상품1', '', '1000', '', '', '', ''],
        ['총자산', '', '', '9999', '9999', '9999', '총부채', ''],
        ['순자산', '', '', '', '', '', '', ''],
        ['9999', '', '', '', '', '', '', ''],
      ]);
      final result = AssetSnapshotImportService.parse(rows);

      expect(result.snapshot!.totalAssets, 1000);
    });

    test('errors when no 재무현황 section exists', () {
      final rows = [
        ['1.고객정보', '', '', ''],
        ['이름', '', '', ''],
      ];
      final result = AssetSnapshotImportService.parse(rows);

      expect(result.isValid, isFalse);
      expect(result.error, isNotNull);
    });

    test('errors when the 항목/상품명 header row is missing', () {
      final rows = [
        ['3.재무현황', '', '', ''],
        ['설명', '', '', ''],
        ['카테고리A', '상품1', '', '1000'],
      ];
      final result = AssetSnapshotImportService.parse(rows);

      expect(result.isValid, isFalse);
      expect(result.error, isNotNull);
    });

    test('errors when no asset rows are recognized', () {
      final rows = _sampleRows(assetRows: [
        ['총자산', '', '', '9999', '9999', '9999', '총부채', ''],
      ]);
      final result = AssetSnapshotImportService.parse(rows);

      expect(result.isValid, isFalse);
      expect(result.error, isNotNull);
    });

    test('totalAssets/totalLiabilities/netWorth match the category sums', () {
      final rows = _sampleRows(assetRows: [
        ['카테고리A', '상품1', '', '1000', '', '', '', ''],
        ['카테고리B', '상품3', '', '500', '1500', '', '', ''],
        ['', '부채상품A', '', '', '부채카테고리', '부채상품A', '', '300'],
        ['총자산', '', '', '9999', '9999', '9999', '총부채', ''],
      ]);
      final snapshot = AssetSnapshotImportService.parse(rows).snapshot!;

      expect(snapshot.totalAssets, 1000 + 1500);
      expect(snapshot.totalLiabilities, 300);
      expect(snapshot.netWorth, 1000 + 1500 - 300);
    });
  });
}
