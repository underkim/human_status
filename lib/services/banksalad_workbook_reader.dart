import 'dart:typed_data';

import 'package:excel/excel.dart';

/// Converts an Excel cell value to a string in a form the existing row-based
/// parsers (built for CSV) already understand. Date/time-like cells are
/// rendered from their own year/month/day/hour/minute/second fields rather
/// than via CellValue's own toString() (which emits a full ISO-8601
/// timestamp like '2026-07-01T00:00:00.000Z' — the '.000' would be mangled
/// by TransactionImportService.parseDate's dot-to-dash normalization).
String cellValueToString(CellValue? value) {
  return switch (value) {
    null => '',
    DateCellValue() =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}',
    DateTimeCellValue() =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')} '
          '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}:${value.second.toString().padLeft(2, '0')}',
    TimeCellValue() =>
      '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}:${value.second.toString().padLeft(2, '0')}',
    FormulaCellValue() => value.formula,
    TextCellValue() => value.toString(),
    IntCellValue() => value.toString(),
    DoubleCellValue() => value.toString(),
    BoolCellValue() => value.toString(),
  };
}

/// Reads a Banksalad .xlsx export and exposes each sheet as the same
/// row-of-strings shape the CSV-based parsers already use, so
/// AssetSnapshotImportService.parse and TransactionImportService.parseBanksaladLedger
/// work unchanged regardless of source format.
class BanksaladWorkbook {
  final Excel _excel;

  BanksaladWorkbook._(this._excel);

  factory BanksaladWorkbook.decode(Uint8List bytes) => BanksaladWorkbook._(Excel.decodeBytes(bytes));

  List<String> get sheetNames => _excel.tables.keys.toList();

  /// Finds the first sheet whose name contains [nameSubstring] (Banksalad's
  /// exact sheet names can vary slightly between export versions) and
  /// returns its rows, or null if no matching sheet exists.
  List<List<String>>? findSheetRowsContaining(String nameSubstring) {
    for (final entry in _excel.tables.entries) {
      if (!entry.key.contains(nameSubstring)) continue;
      return entry.value.rows
          .map((row) => row.map((cell) => cellValueToString(cell?.value)).toList())
          .toList();
    }
    return null;
  }
}
