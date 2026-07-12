import 'dart:convert';
import 'dart:typed_data';

import 'package:cp949_codec/cp949_codec.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:human_status/models/transaction.dart';
import 'package:human_status/services/transaction_import_service.dart';
import 'package:uuid/uuid.dart';

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

  group('TransactionImportService.parseBanksaladLedger', () {
    const header = ['날짜', '시간', '타입', '대분류', '소분류', '내용', '금액', '화폐', '결제수단', '메모'];

    List<List<String>> rowsWith(List<List<String>> dataRows) => [header, ...dataRows];

    test('maps 수입/지출 rows directly', () {
      final result = TransactionImportService.parseBanksaladLedger(rowsWith([
        ['2026-07-01', '13:22', '지출', '식비', '카페', '스타벅스', '5000', 'KRW', '카드', ''],
        ['2026-07-02', '09:00', '수입', '급여', '', '7월 급여', '3000000', 'KRW', '이체', ''],
      ]));

      expect(result.isValid, isTrue);
      expect(result.rows, hasLength(2));
      expect(result.rows![0].transaction!.type, TransactionType.expense);
      expect(result.rows![0].transaction!.category, '식비');
      expect(result.rows![0].transaction!.memo, '스타벅스');
      expect(result.rows![1].transaction!.type, TransactionType.income);
      expect(result.rows![1].transaction!.amount, 3000000);
    });

    test('combines 날짜+시간 into one DateTime', () {
      final result = TransactionImportService.parseBanksaladLedger(rowsWith([
        ['2026-07-01', '13:22:00', '지출', '식비', '', '점심', '8000', 'KRW', '카드', ''],
      ]));

      final date = result.rows!.first.transaction!.date;
      expect(date.year, 2026);
      expect(date.month, 7);
      expect(date.day, 1);
      expect(date.hour, 13);
      expect(date.minute, 22);
    });

    test('excludes 이체 rows whose 대분류 is 내계좌이체', () {
      final result = TransactionImportService.parseBanksaladLedger(rowsWith([
        ['2026-07-01', '13:22', '이체', '내계좌이체', '', '내 통장으로', '10000', 'KRW', '이체', ''],
      ]));

      expect(result.isValid, isTrue);
      expect(result.rows!.first.isValid, isFalse);
      expect(result.rows!.first.error, contains('내 계좌'));
    });

    test('counts non-내계좌이체 이체 rows as expense (e.g. 카드대금, 보험)', () {
      final result = TransactionImportService.parseBanksaladLedger(rowsWith([
        ['2026-07-01', '13:22', '이체', '카드대금', '', '카드값 결제', '150000', 'KRW', '이체', ''],
        ['2026-07-02', '09:00', '이체', '보험', '', '보험료', '30000', 'KRW', '이체', ''],
      ]));

      expect(result.rows!.every((r) => r.isValid), isTrue);
      expect(result.rows![0].transaction!.type, TransactionType.expense);
      expect(result.rows![0].transaction!.category, '카드대금');
      expect(result.rows![1].transaction!.type, TransactionType.expense);
      expect(result.rows![1].transaction!.category, '보험');
    });

    test('errors on an unrecognized 타입 value', () {
      final result = TransactionImportService.parseBanksaladLedger(rowsWith([
        ['2026-07-01', '13:22', '알수없음', '기타', '', '', '1000', 'KRW', '', ''],
      ]));

      expect(result.rows!.first.isValid, isFalse);
    });

    test('finds the header even with preamble rows before it', () {
      final rows = [
        ['이 파일은 뱅크샐러드에서 내보낸 가계부입니다', '', '', '', '', '', '', '', '', ''],
        ...rowsWith([
          ['2026-07-01', '13:22', '지출', '식비', '', '점심', '8000', 'KRW', '카드', ''],
        ]),
      ];
      final result = TransactionImportService.parseBanksaladLedger(rows);

      expect(result.isValid, isTrue);
      expect(result.rows, hasLength(1));
    });

    test('skips fully blank trailing rows', () {
      final result = TransactionImportService.parseBanksaladLedger(rowsWith([
        ['2026-07-01', '13:22', '지출', '식비', '', '점심', '8000', 'KRW', '카드', ''],
        ['', '', '', '', '', '', '', '', '', ''],
      ]));

      expect(result.rows, hasLength(1));
    });

    test('errors when the header does not match', () {
      final result = TransactionImportService.parseBanksaladLedger([
        ['Date', 'Amount', 'Description'],
        ['2026-07-01', '8000', '점심'],
      ]);

      expect(result.isValid, isFalse);
      expect(result.error, isNotNull);
    });
  });

  group('TransactionImportService.filterDuplicates', () {
    Transaction tx({required DateTime date, String category = '식비', double amount = 1000}) => Transaction(
          id: const Uuid().v4(),
          type: TransactionType.expense,
          category: category,
          memo: '',
          amount: amount,
          date: date,
          createdAt: DateTime.now(),
        );

    test('excludes a candidate matching date+category+amount of an existing transaction', () {
      final date = DateTime(2026, 7, 1, 13, 22);
      final existing = [tx(date: date)];
      final candidates = [tx(date: date)];

      final result = TransactionImportService.filterDuplicates(candidates, existing);

      expect(result, isEmpty);
    });

    test('keeps a candidate whose amount differs', () {
      final date = DateTime(2026, 7, 1, 13, 22);
      final existing = [tx(date: date, amount: 1000)];
      final candidates = [tx(date: date, amount: 2000)];

      final result = TransactionImportService.filterDuplicates(candidates, existing);

      expect(result, hasLength(1));
    });

    test('keeps a candidate whose time-of-day differs from an existing same-date transaction', () {
      final existing = [tx(date: DateTime(2026, 7, 1, 9, 0))];
      final candidates = [tx(date: DateTime(2026, 7, 1, 13, 22))];

      final result = TransactionImportService.filterDuplicates(candidates, existing);

      expect(result, hasLength(1));
    });

    test('keeps a candidate whose category differs', () {
      final date = DateTime(2026, 7, 1, 13, 22);
      final existing = [tx(date: date, category: '식비')];
      final candidates = [tx(date: date, category: '교통')];

      final result = TransactionImportService.filterDuplicates(candidates, existing);

      expect(result, hasLength(1));
    });
  });
}
