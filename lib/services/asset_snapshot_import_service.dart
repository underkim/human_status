import 'package:uuid/uuid.dart';

import '../models/asset_snapshot.dart';
import 'transaction_import_service.dart';

class AssetSnapshotParseResult {
  final AssetSnapshot? snapshot;
  final String? error;

  const AssetSnapshotParseResult({this.snapshot, this.error});

  bool get isValid => snapshot != null;
}

/// Parses the "3.재무현황" (asset/liability status) section of a Banksalad
/// "현황.csv" export. This is a dedicated parser for Banksalad's own report
/// template — not a generic bank-format mapper like TransactionImportService,
/// since there's only one source format to support here.
class AssetSnapshotImportService {
  static final _nextSectionPattern = RegExp(r'^\d+\.');

  static String _cell(List<String> row, int index) {
    if (index < 0 || index >= row.length) return '';
    return row[index];
  }

  /// Parses [rows] into an AssetSnapshot. Totals are computed by summing
  /// every recognized category line rather than trusting the source file's
  /// own "총자산"/"순자산" summary row, whose value position is ambiguous
  /// due to merged-cell artifacts.
  ///
  /// Column positions are located dynamically (by finding "항목" immediately
  /// followed by "상품명") rather than assumed to start at column 0, because
  /// the CSV export and the native .xlsx sheet don't line up: the .xlsx
  /// version has an extra leading blank column that CSV export drops.
  static AssetSnapshotParseResult parse(List<List<String>> rows) {
    final sectionStart = rows.indexWhere((r) => r.any((c) => c.contains('재무현황')));
    if (sectionStart == -1) {
      return const AssetSnapshotParseResult(
        error: '재무현황 데이터를 찾을 수 없어요 (뱅크샐러드 현황 형식이 아닐 수 있어요)',
      );
    }

    var headerRowIndex = -1;
    var anchorCol = -1;
    for (var i = sectionStart + 1; i < rows.length; i++) {
      final row = rows[i];
      for (var col = 0; col < row.length - 1; col++) {
        if (row[col].trim() == '항목' && row[col + 1].trim() == '상품명') {
          headerRowIndex = i;
          anchorCol = col;
          break;
        }
      }
      if (headerRowIndex != -1) break;
    }
    if (headerRowIndex == -1) {
      return const AssetSnapshotParseResult(error: '자산 표를 찾을 수 없어요');
    }

    final assetsByCategory = <String, double>{};
    final liabilitiesByCategory = <String, double>{};
    String? currentAssetCategory;
    String? currentLiabilityCategory;

    for (var i = headerRowIndex + 1; i < rows.length; i++) {
      final row = rows[i];
      final assetCategoryCell = _cell(row, anchorCol).trim();
      final assetProductCell = _cell(row, anchorCol + 1).trim();
      final liabilityCategoryCell = _cell(row, anchorCol + 4).trim();
      final liabilityProductCell = _cell(row, anchorCol + 5).trim();

      if (assetCategoryCell == '총자산' || _nextSectionPattern.hasMatch(assetCategoryCell)) break;

      if (assetCategoryCell.isNotEmpty) currentAssetCategory = assetCategoryCell;

      // A row only carries liability data when these cells hold genuine
      // label text (not a number) — asset rows with extra value columns
      // (e.g. 매입금액/평가금액/수익률 for investment holdings) can spill
      // numbers into these column positions without actually being
      // liability rows.
      final liabilityCategoryIsLabel =
          liabilityCategoryCell.isNotEmpty && TransactionImportService.parseAmount(liabilityCategoryCell) == null;
      final liabilityProductIsLabel =
          liabilityProductCell.isNotEmpty && TransactionImportService.parseAmount(liabilityProductCell) == null;

      if (liabilityCategoryIsLabel || liabilityProductIsLabel) {
        if (liabilityCategoryIsLabel) currentLiabilityCategory = liabilityCategoryCell;
        final category = currentLiabilityCategory;
        if (category != null) {
          // Scan only the value columns (skip the liability's own
          // category/product label) — product names can contain embedded
          // digits (e.g. "TIGER 미국나스닥100(H)") that would otherwise be
          // mistaken for amounts.
          final nums = <double>[];
          for (var col = anchorCol + 6; col < row.length; col++) {
            final v = TransactionImportService.parseAmount(row[col]);
            if (v != null) nums.add(v);
          }
          if (nums.isNotEmpty) {
            final amount = nums.length >= 2 ? nums[1] : nums[0];
            liabilitiesByCategory[category] = (liabilitiesByCategory[category] ?? 0) + amount;
          }
        }
      } else if ((assetCategoryCell.isNotEmpty || assetProductCell.isNotEmpty) && currentAssetCategory != null) {
        final category = currentAssetCategory;
        // Scan only the value columns (skip the category/product label) for
        // the same embedded-digit reason as above.
        final nums = <double>[];
        for (var col = anchorCol + 2; col < row.length; col++) {
          final v = TransactionImportService.parseAmount(row[col]);
          if (v != null) nums.add(v);
        }
        if (nums.isNotEmpty) {
          // 2+ numbers on a line: assume 매입금액→평가금액 order, so the
          // 2nd is current value. Exactly 1 number: that's the balance.
          final amount = nums.length >= 2 ? nums[1] : nums[0];
          assetsByCategory[category] = (assetsByCategory[category] ?? 0) + amount;
        }
      }
    }

    if (assetsByCategory.isEmpty) {
      return const AssetSnapshotParseResult(error: '인식된 자산 항목이 없어요');
    }

    final totalAssets = assetsByCategory.values.fold(0.0, (a, b) => a + b);
    final totalLiabilities = liabilitiesByCategory.values.fold(0.0, (a, b) => a + b);

    return AssetSnapshotParseResult(
      snapshot: AssetSnapshot(
        id: const Uuid().v4(),
        importedAt: DateTime.now(),
        assetsByCategory: assetsByCategory,
        liabilitiesByCategory: liabilitiesByCategory,
        totalAssets: totalAssets,
        totalLiabilities: totalLiabilities,
      ),
    );
  }
}
