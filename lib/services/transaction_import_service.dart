import 'dart:convert';
import 'dart:typed_data';

import 'package:cp949_codec/cp949_codec.dart';
import 'package:csv/csv.dart';
import 'package:uuid/uuid.dart';

import '../models/transaction.dart';

/// Decodes raw file bytes to text, trying UTF-8 first and falling back to
/// CP949/EUC-KR (the encoding most Korean bank CSV exports use) on any
/// invalid-UTF-8 byte sequence. Strips a leading UTF-8 BOM if present.
String decodeBytes(Uint8List bytes) {
  try {
    final decoded = utf8.decode(bytes, allowMalformed: false);
    return decoded.startsWith('﻿') ? decoded.substring(1) : decoded;
  } on FormatException {
    return cp949.decode(bytes);
  }
}

/// Parses CSV text into rows of string cells. Field-delimiter auto-detection
/// and CRLF/LF handling are left to the csv package's defaults.
List<List<String>> parseCsvRows(String text) {
  return csv.decode(text).map((row) => row.map((c) => c.toString()).toList()).toList();
}

class ParsedImportRow {
  final Transaction? transaction;
  final String? error;
  final List<String> rawRow;

  const ParsedImportRow({this.transaction, this.error, required this.rawRow});

  bool get isValid => transaction != null;
}

/// The exact header Banksalad's 가계부 내역 sheet/export uses.
const banksaladTransactionHeaders = [
  '날짜',
  '시간',
  '타입',
  '대분류',
  '소분류',
  '내용',
  '금액',
  '화폐',
  '결제수단',
  '메모',
];

class BanksaladImportResult {
  final List<ParsedImportRow>? rows;
  final String? error;

  const BanksaladImportResult({this.rows, this.error});

  bool get isValid => rows != null;
}

class TransactionImportService {
  /// Parses a date-only string ('yyyy-MM-dd', with '.'/'/' separators also
  /// normalized) or a 'yyyy-MM-dd HH:mm:ss' string. Returns null on failure.
  static DateTime? _parseDateTime(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    final normalized = trimmed.replaceAll('.', '-').replaceAll('/', '-');
    try {
      return DateTime.parse(normalized);
    } catch (_) {
      return null;
    }
  }

  /// Parses [raw] as an amount, stripping thousands separators and currency
  /// symbols (anything that isn't a digit, '.', or '-'). Returns null if
  /// nothing numeric remains.
  static double? parseAmount(String raw) {
    final cleaned = raw.trim().replaceAll(RegExp(r'[^\d.\-]'), '');
    if (cleaned.isEmpty || cleaned == '-') return null;
    return double.tryParse(cleaned);
  }

  static String _cell(List<String> row, int index) {
    if (index < 0 || index >= row.length) return '';
    return row[index];
  }

  static bool _isBanksaladHeaderRow(List<String> row) {
    if (row.length < banksaladTransactionHeaders.length) return false;
    for (var i = 0; i < banksaladTransactionHeaders.length; i++) {
      if (row[i].trim() != banksaladTransactionHeaders[i]) return false;
    }
    return true;
  }

  /// Converts one Banksalad ledger row into a Transaction, or an error/
  /// exclusion reason. Column layout is fixed: 0=날짜, 1=시간, 2=타입,
  /// 3=대분류, 5=내용, 6=금액.
  ///
  /// 타입 branching:
  ///  - '수입' -> income, '지출' -> expense
  ///  - '이체' with 대분류 == '내계좌이체' -> excluded (a transfer between the
  ///    user's own accounts, not real income/expense)
  ///  - '이체' with any other 대분류 (카드대금/저축/투자/현금/미분류/보험 등)
  ///    -> counted as expense — these represent an actual payment made via
  ///    bank transfer, not an internal move
  static ParsedImportRow _mapBanksaladLedgerRow(List<String> row) {
    try {
      final dateTime = _parseDateTime('${_cell(row, 0)} ${_cell(row, 1)}'.trim());
      if (dateTime == null) {
        return ParsedImportRow(error: '날짜를 인식할 수 없어요', rawRow: row);
      }

      final rawAmount = parseAmount(_cell(row, 6));
      if (rawAmount == null) {
        return ParsedImportRow(error: '금액을 인식할 수 없어요', rawRow: row);
      }

      final typeText = _cell(row, 2).trim();
      final category = _cell(row, 3).trim();

      TransactionType type;
      if (typeText == '수입') {
        type = TransactionType.income;
      } else if (typeText == '지출') {
        type = TransactionType.expense;
      } else if (typeText == '이체') {
        if (category == '내계좌이체') {
          return ParsedImportRow(error: '내 계좌 간 이동이라 제외했어요', rawRow: row);
        }
        type = TransactionType.expense;
      } else {
        return ParsedImportRow(error: '알 수 없는 타입이에요: $typeText', rawRow: row);
      }

      final memo = _cell(row, 5).trim();

      return ParsedImportRow(
        rawRow: row,
        transaction: Transaction(
          id: const Uuid().v4(),
          type: type,
          category: category.isNotEmpty ? category : (type == TransactionType.income ? '수입' : '지출'),
          memo: memo,
          amount: rawAmount.abs(),
          date: dateTime,
          createdAt: DateTime.now(),
        ),
      );
    } catch (e) {
      return ParsedImportRow(error: '행을 처리할 수 없어요: $e', rawRow: row);
    }
  }

  /// Parses [rows] as a Banksalad 가계부 (transaction ledger) export — the
  /// only transaction format this app imports. Locates the header row
  /// (allowing preamble rows before it), then maps every following
  /// non-blank row via the fixed Banksalad column layout.
  static BanksaladImportResult parseBanksaladLedger(List<List<String>> rows) {
    final headerIndex = rows.indexWhere(_isBanksaladHeaderRow);
    if (headerIndex == -1) {
      return const BanksaladImportResult(
        error: '뱅크샐러드 가계부 형식이 아니에요 (날짜,시간,타입,대분류,소분류,내용,금액,화폐,결제수단,메모 헤더가 필요해요).',
      );
    }

    final dataRows = rows
        .sublist(headerIndex + 1)
        .where((row) => row.any((cell) => cell.trim().isNotEmpty))
        .toList();

    return BanksaladImportResult(
      rows: dataRows.map(_mapBanksaladLedgerRow).toList(),
    );
  }

  /// Filters [candidates] down to those that don't already exist in
  /// [existing], matching on date (including time-of-day)+category+amount.
  /// Banksalad always exports a rolling last-1-year window, so re-importing
  /// periodically re-sends months of already-stored data; this lets repeat
  /// imports only add what's actually new.
  static List<Transaction> filterDuplicates(List<Transaction> candidates, List<Transaction> existing) {
    final existingKeys = existing.map((t) => (t.date, t.category, t.amount)).toSet();
    return candidates.where((t) => !existingKeys.contains((t.date, t.category, t.amount))).toList();
  }
}
