import 'dart:convert';
import 'dart:typed_data';

import 'package:cp949_codec/cp949_codec.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:human_status/models/transaction.dart';
import 'package:human_status/services/transaction_import_service.dart';

void main() {
  group('decodeBytes', () {
    test('round-trips UTF-8 text', () {
      final bytes = utf8.encode('안녕하세요');
      expect(decodeBytes(bytes), '안녕하세요');
    });

    test('falls back to CP949/EUC-KR when bytes are not valid UTF-8', () {
      final bytes = cp949.encode('안녕하세요');
      expect(decodeBytes(bytes), '안녕하세요');
    });

    test('strips a leading UTF-8 BOM', () {
      final bytes = Uint8List.fromList([0xEF, 0xBB, 0xBF, ...utf8.encode('가나다')]);
      expect(decodeBytes(bytes), '가나다');
    });
  });

  group('parseCsvRows', () {
    test('parses basic comma-separated rows', () {
      final rows = parseCsvRows('a,b,c\n1,2,3');
      expect(rows, [
        ['a', 'b', 'c'],
        ['1', '2', '3'],
      ]);
    });

    test('handles a quoted field containing a comma', () {
      final rows = parseCsvRows('a,"b,c",d');
      expect(rows, [
        ['a', 'b,c', 'd'],
      ]);
    });
  });

  group('TransactionImportService.parseDate', () {
    test('parses dot-separated dates', () {
      expect(TransactionImportService.parseDate('2026.07.01'), DateTime(2026, 7, 1));
    });

    test('parses ISO dash-separated dates', () {
      expect(TransactionImportService.parseDate('2026-07-01'), DateTime(2026, 7, 1));
    });

    test('parses a date with a time component', () {
      expect(
        TransactionImportService.parseDate('2026-07-01 13:22:00'),
        DateTime(2026, 7, 1, 13, 22, 0),
      );
    });

    test('parses using an explicit format hint', () {
      expect(
        TransactionImportService.parseDate('07/01/2026', formatHint: 'MM/dd/yyyy'),
        DateTime(2026, 7, 1),
      );
    });

    test('returns null for unparsable input', () {
      expect(TransactionImportService.parseDate('not a date'), isNull);
      expect(TransactionImportService.parseDate(''), isNull);
    });
  });

  group('TransactionImportService.parseAmount', () {
    test('strips thousands separators', () {
      expect(TransactionImportService.parseAmount('12,345'), 12345.0);
    });

    test('strips currency symbols and keeps the sign', () {
      expect(TransactionImportService.parseAmount('-1,200원'), -1200.0);
    });

    test('returns null when nothing numeric remains', () {
      expect(TransactionImportService.parseAmount(''), isNull);
      expect(TransactionImportService.parseAmount('-'), isNull);
      expect(TransactionImportService.parseAmount('원'), isNull);
    });
  });

  group('TransactionImportService.mapRow', () {
    test('single-mode: positive amount is income by default', () {
      const mapping = ImportColumnMapping(
        dateColumn: 0,
        amountMode: AmountColumnMode.single,
        amountColumn: 1,
      );
      final result = TransactionImportService.mapRow(['2026-07-01', '10000'], mapping);

      expect(result.isValid, isTrue);
      expect(result.transaction!.type, TransactionType.income);
      expect(result.transaction!.amount, 10000);
    });

    test('single-mode: negative amount is expense by default', () {
      const mapping = ImportColumnMapping(
        dateColumn: 0,
        amountMode: AmountColumnMode.single,
        amountColumn: 1,
      );
      final result = TransactionImportService.mapRow(['2026-07-01', '-5000'], mapping);

      expect(result.transaction!.type, TransactionType.expense);
      expect(result.transaction!.amount, 5000);
    });

    test('single-mode: positiveIsIncome=false flips the sign convention', () {
      const mapping = ImportColumnMapping(
        dateColumn: 0,
        amountMode: AmountColumnMode.single,
        amountColumn: 1,
        positiveIsIncome: false,
      );
      final result = TransactionImportService.mapRow(['2026-07-01', '5000'], mapping);

      expect(result.transaction!.type, TransactionType.expense);
    });

    test('split-mode: uses the income column when it has a value', () {
      const mapping = ImportColumnMapping(
        dateColumn: 0,
        amountMode: AmountColumnMode.splitIncomeExpense,
        incomeColumn: 1,
        expenseColumn: 2,
      );
      final result = TransactionImportService.mapRow(['2026-07-01', '3000', ''], mapping);

      expect(result.transaction!.type, TransactionType.income);
      expect(result.transaction!.amount, 3000);
    });

    test('split-mode: uses the expense column when income is empty', () {
      const mapping = ImportColumnMapping(
        dateColumn: 0,
        amountMode: AmountColumnMode.splitIncomeExpense,
        incomeColumn: 1,
        expenseColumn: 2,
      );
      final result = TransactionImportService.mapRow(['2026-07-01', '', '1500'], mapping);

      expect(result.transaction!.type, TransactionType.expense);
      expect(result.transaction!.amount, 1500);
    });

    test('split-mode: errors when both income and expense are empty', () {
      const mapping = ImportColumnMapping(
        dateColumn: 0,
        amountMode: AmountColumnMode.splitIncomeExpense,
        incomeColumn: 1,
        expenseColumn: 2,
      );
      final result = TransactionImportService.mapRow(['2026-07-01', '', ''], mapping);

      expect(result.isValid, isFalse);
      expect(result.error, isNotNull);
    });

    test('errors when the date column is unparsable', () {
      const mapping = ImportColumnMapping(
        dateColumn: 0,
        amountMode: AmountColumnMode.single,
        amountColumn: 1,
      );
      final result = TransactionImportService.mapRow(['n/a', '1000'], mapping);

      expect(result.isValid, isFalse);
      expect(result.transaction, isNull);
    });

    test('falls back to a default category and empty memo when unmapped', () {
      const mapping = ImportColumnMapping(
        dateColumn: 0,
        amountMode: AmountColumnMode.single,
        amountColumn: 1,
      );
      final result = TransactionImportService.mapRow(['2026-07-01', '1000'], mapping);

      expect(result.transaction!.category, '수입');
      expect(result.transaction!.memo, '');
    });

    test('uses the mapped memo and category columns when provided', () {
      const mapping = ImportColumnMapping(
        dateColumn: 0,
        amountMode: AmountColumnMode.single,
        amountColumn: 1,
        memoColumn: 2,
        categoryColumn: 3,
      );
      final result = TransactionImportService.mapRow(
        ['2026-07-01', '-1000', '점심 식사', '식비'],
        mapping,
      );

      expect(result.transaction!.memo, '점심 식사');
      expect(result.transaction!.category, '식비');
    });

    group('typeLabel mode (e.g. Banksalad: 날짜,타입,금액 with 수입/지출/이체)', () {
      const mapping = ImportColumnMapping(
        dateColumn: 0,
        amountMode: AmountColumnMode.typeLabel,
        amountColumn: 2,
        typeColumn: 1,
      );

      test('matches the income label', () {
        final result = TransactionImportService.mapRow(['2026-07-01', '수입', '10000'], mapping);
        expect(result.isValid, isTrue);
        expect(result.transaction!.type, TransactionType.income);
        expect(result.transaction!.amount, 10000);
      });

      test('matches the expense label', () {
        final result = TransactionImportService.mapRow(['2026-07-01', '지출', '5000'], mapping);
        expect(result.isValid, isTrue);
        expect(result.transaction!.type, TransactionType.expense);
        expect(result.transaction!.amount, 5000);
      });

      test('excludes rows whose type matches neither label (e.g. 이체)', () {
        final result = TransactionImportService.mapRow(['2026-07-01', '이체', '3000'], mapping);
        expect(result.isValid, isFalse);
        expect(result.error, isNotNull);
      });

      test('respects custom income/expense label text', () {
        const customMapping = ImportColumnMapping(
          dateColumn: 0,
          amountMode: AmountColumnMode.typeLabel,
          amountColumn: 2,
          typeColumn: 1,
          incomeLabel: 'IN',
          expenseLabel: 'OUT',
        );
        final result = TransactionImportService.mapRow(['2026-07-01', 'OUT', '2000'], customMapping);
        expect(result.transaction!.type, TransactionType.expense);
      });
    });
  });

  group('TransactionImportService.parseBanksaladTransactions', () {
    const header = ['날짜', '시간', '타입', '대분류', '소분류', '내용', '금액', '화폐', '결제수단', '메모'];

    test('parses rows under the Banksalad header', () {
      final rows = [
        header,
        ['2026-07-01', '13:22', '지출', '식비', '카페', '스타벅스', '5000', 'KRW', '카드', ''],
        ['2026-07-02', '09:00', '수입', '급여', '', '7월 급여', '3000000', 'KRW', '이체', ''],
      ];
      final result = TransactionImportService.parseBanksaladTransactions(rows);

      expect(result.isValid, isTrue);
      expect(result.rows, hasLength(2));
      expect(result.rows![0].transaction!.type, TransactionType.expense);
      expect(result.rows![0].transaction!.category, '식비');
      expect(result.rows![0].transaction!.memo, '스타벅스');
      expect(result.rows![1].transaction!.type, TransactionType.income);
      expect(result.rows![1].transaction!.amount, 3000000);
    });

    test('excludes 이체 rows', () {
      final rows = [
        header,
        ['2026-07-01', '13:22', '이체', '계좌이체', '', '내 통장으로', '10000', 'KRW', '이체', ''],
      ];
      final result = TransactionImportService.parseBanksaladTransactions(rows);

      expect(result.isValid, isTrue);
      expect(result.rows!.first.isValid, isFalse);
    });

    test('finds the header even with preamble rows before it', () {
      final rows = [
        ['이 파일은 뱅크샐러드에서 내보낸 가계부입니다', '', '', '', '', '', '', '', '', ''],
        header,
        ['2026-07-01', '13:22', '지출', '식비', '', '점심', '8000', 'KRW', '카드', ''],
      ];
      final result = TransactionImportService.parseBanksaladTransactions(rows);

      expect(result.isValid, isTrue);
      expect(result.rows, hasLength(1));
    });

    test('skips fully blank trailing rows', () {
      final rows = [
        header,
        ['2026-07-01', '13:22', '지출', '식비', '', '점심', '8000', 'KRW', '카드', ''],
        ['', '', '', '', '', '', '', '', '', ''],
      ];
      final result = TransactionImportService.parseBanksaladTransactions(rows);

      expect(result.rows, hasLength(1));
    });

    test('errors when the header does not match', () {
      final rows = [
        ['Date', 'Amount', 'Description'],
        ['2026-07-01', '8000', '점심'],
      ];
      final result = TransactionImportService.parseBanksaladTransactions(rows);

      expect(result.isValid, isFalse);
      expect(result.error, isNotNull);
    });
  });
}
