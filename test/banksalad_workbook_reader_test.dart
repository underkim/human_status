import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:human_status/services/banksalad_workbook_reader.dart';

void main() {
  group('cellValueToString', () {
    test('converts TextCellValue to plain text', () {
      expect(cellValueToString(TextCellValue('안녕')), '안녕');
    });

    test('converts IntCellValue and DoubleCellValue', () {
      expect(cellValueToString(const IntCellValue(5000)), '5000');
      expect(cellValueToString(const DoubleCellValue(12.5)), '12.5');
    });

    test('converts DateCellValue to a parser-safe yyyy-MM-dd string (no dots)', () {
      final value = cellValueToString(const DateCellValue(year: 2026, month: 7, day: 1));
      expect(value, '2026-07-01');
      expect(value.contains('.'), isFalse);
    });

    test('converts TimeCellValue to HH:mm:ss', () {
      expect(cellValueToString(const TimeCellValue(hour: 13, minute: 22, second: 5)), '13:22:05');
    });

    test('converts DateTimeCellValue to a parser-safe combined string', () {
      final value = cellValueToString(
        const DateTimeCellValue(year: 2026, month: 7, day: 1, hour: 13, minute: 22),
      );
      expect(value, '2026-07-01 13:22:00');
      expect(value.contains('.'), isFalse);
    });

    test('converts null to an empty string', () {
      expect(cellValueToString(null), '');
    });
  });

  group('BanksaladWorkbook', () {
    test('finds a sheet by substring match and reads its rows', () {
      final excel = Excel.createExcel();
      final sheet = excel['가계부 내역'];
      sheet.appendRow([TextCellValue('날짜'), TextCellValue('금액')]);
      sheet.appendRow([TextCellValue('2026-07-01'), const IntCellValue(5000)]);

      final bytes = excel.encode()!;
      final workbook = BanksaladWorkbook.decode(Uint8List.fromList(bytes));

      final rows = workbook.findSheetRowsContaining('가계부');

      expect(rows, isNotNull);
      expect(rows!.first, ['날짜', '금액']);
      expect(rows[1], ['2026-07-01', '5000']);
    });

    test('returns null when no sheet matches the substring', () {
      final excel = Excel.createExcel();
      excel['다른시트'].appendRow([TextCellValue('x')]);

      final bytes = excel.encode()!;
      final workbook = BanksaladWorkbook.decode(Uint8List.fromList(bytes));

      expect(workbook.findSheetRowsContaining('가계부'), isNull);
    });
  });
}
