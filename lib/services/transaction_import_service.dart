import 'dart:convert';
import 'dart:typed_data';

import 'package:cp949_codec/cp949_codec.dart';
import 'package:csv/csv.dart';
import 'package:intl/intl.dart';
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

enum AmountColumnMode {
  single,
  splitIncomeExpense,
  // A single always-positive amount column plus a separate text column
  // (e.g. Banksalad's "타입" column) whose value says whether the row is
  // income or expense. Rows whose type text matches neither label (e.g.
  // "이체" transfers between the user's own accounts) are excluded rather
  // than imported.
  typeLabel,
}

/// The user's chosen mapping from CSV column indices to Transaction fields.
class ImportColumnMapping {
  final int dateColumn;
  // e.g. 'yyyy.MM.dd'. Null means auto-normalize separators and try
  // DateTime.parse directly.
  final String? dateFormat;
  final AmountColumnMode amountMode;
  final int? amountColumn; // single and typeLabel modes
  final bool positiveIsIncome; // single mode sign convention
  final int? incomeColumn; // splitIncomeExpense mode
  final int? expenseColumn; // splitIncomeExpense mode
  final int? typeColumn; // typeLabel mode
  final String incomeLabel; // typeLabel mode, e.g. '수입'
  final String expenseLabel; // typeLabel mode, e.g. '지출'
  final int? memoColumn;
  final int? categoryColumn;

  const ImportColumnMapping({
    required this.dateColumn,
    this.dateFormat,
    required this.amountMode,
    this.amountColumn,
    this.positiveIsIncome = true,
    this.incomeColumn,
    this.expenseColumn,
    this.typeColumn,
    this.incomeLabel = '수입',
    this.expenseLabel = '지출',
    this.memoColumn,
    this.categoryColumn,
  });
}

class ParsedImportRow {
  final Transaction? transaction;
  final String? error;
  final List<String> rawRow;

  const ParsedImportRow({this.transaction, this.error, required this.rawRow});

  bool get isValid => transaction != null;
}

/// The exact header Banksalad's 가계부.csv (transaction ledger) export uses.
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

const _banksaladMapping = ImportColumnMapping(
  dateColumn: 0,
  amountMode: AmountColumnMode.typeLabel,
  amountColumn: 6,
  typeColumn: 2,
  categoryColumn: 3,
  memoColumn: 5, // 내용 — the transaction description, more consistently filled in than 메모
);

class BanksaladImportResult {
  final List<ParsedImportRow>? rows;
  final String? error;

  const BanksaladImportResult({this.rows, this.error});

  bool get isValid => rows != null;
}

class TransactionImportService {
  /// Parses [raw] as a date. If [formatHint] is given, parses strictly
  /// against that pattern; otherwise normalizes '.'/'/' separators to '-'
  /// and tries DateTime.parse (handles 'yyyy-MM-dd' and
  /// 'yyyy-MM-dd HH:mm:ss'). Returns null on any failure.
  static DateTime? parseDate(String raw, {String? formatHint}) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;

    if (formatHint != null) {
      try {
        return DateFormat(formatHint).parseStrict(trimmed);
      } catch (_) {
        return null;
      }
    }

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

  static String _cell(List<String> row, int? index) {
    if (index == null || index < 0 || index >= row.length) return '';
    return row[index];
  }

  /// Converts one raw CSV [row] into a Transaction per [mapping], or an
  /// error message if the row can't be interpreted. linkedGoalId is always
  /// left null for imported rows.
  static ParsedImportRow mapRow(List<String> row, ImportColumnMapping mapping) {
    try {
      final date = parseDate(_cell(row, mapping.dateColumn), formatHint: mapping.dateFormat);
      if (date == null) {
        return ParsedImportRow(error: '날짜를 인식할 수 없어요', rawRow: row);
      }

      TransactionType type;
      double amount;

      switch (mapping.amountMode) {
        case AmountColumnMode.single:
          final raw = parseAmount(_cell(row, mapping.amountColumn));
          if (raw == null) {
            return ParsedImportRow(error: '금액을 인식할 수 없어요', rawRow: row);
          }
          final isIncome = mapping.positiveIsIncome ? raw >= 0 : raw < 0;
          type = isIncome ? TransactionType.income : TransactionType.expense;
          amount = raw.abs();
        case AmountColumnMode.splitIncomeExpense:
          final income = parseAmount(_cell(row, mapping.incomeColumn));
          final expense = parseAmount(_cell(row, mapping.expenseColumn));
          if (income != null && income != 0) {
            type = TransactionType.income;
            amount = income.abs();
          } else if (expense != null && expense != 0) {
            type = TransactionType.expense;
            amount = expense.abs();
          } else {
            return ParsedImportRow(error: '수입/지출 금액이 없어요', rawRow: row);
          }
        case AmountColumnMode.typeLabel:
          final typeText = _cell(row, mapping.typeColumn).trim();
          final raw = parseAmount(_cell(row, mapping.amountColumn));
          if (raw == null) {
            return ParsedImportRow(error: '금액을 인식할 수 없어요', rawRow: row);
          }
          if (typeText == mapping.incomeLabel) {
            type = TransactionType.income;
          } else if (typeText == mapping.expenseLabel) {
            type = TransactionType.expense;
          } else {
            return ParsedImportRow(error: '가져오기 제외 대상이에요 (예: 이체)', rawRow: row);
          }
          amount = raw.abs();
      }

      final memo = _cell(row, mapping.memoColumn).trim();
      final category = _cell(row, mapping.categoryColumn).trim();

      return ParsedImportRow(
        rawRow: row,
        transaction: Transaction(
          id: const Uuid().v4(),
          type: type,
          category: category.isNotEmpty ? category : (type == TransactionType.income ? '수입' : '지출'),
          memo: memo,
          amount: amount,
          date: date,
          createdAt: DateTime.now(),
        ),
      );
    } catch (e) {
      return ParsedImportRow(error: '행을 처리할 수 없어요: $e', rawRow: row);
    }
  }

  static bool _isBanksaladHeaderRow(List<String> row) {
    if (row.length < banksaladTransactionHeaders.length) return false;
    for (var i = 0; i < banksaladTransactionHeaders.length; i++) {
      if (row[i].trim() != banksaladTransactionHeaders[i]) return false;
    }
    return true;
  }

  /// Parses [rows] as a Banksalad 가계부.csv export — the only transaction
  /// CSV format this app imports. Locates the header row (allowing preamble
  /// rows before it), then maps every following non-blank row via the fixed
  /// Banksalad column layout. Rows whose 타입 is neither 수입 nor 지출 (e.g.
  /// 이체 transfers between the user's own accounts) are excluded.
  static BanksaladImportResult parseBanksaladTransactions(List<List<String>> rows) {
    final headerIndex = rows.indexWhere(_isBanksaladHeaderRow);
    if (headerIndex == -1) {
      return const BanksaladImportResult(
        error: '뱅크샐러드 가계부.csv 형식이 아니에요 (날짜,시간,타입,대분류,소분류,내용,금액,화폐,결제수단,메모 헤더가 필요해요).',
      );
    }

    final dataRows = rows
        .sublist(headerIndex + 1)
        .where((row) => row.any((cell) => cell.trim().isNotEmpty))
        .toList();

    return BanksaladImportResult(
      rows: dataRows.map((row) => mapRow(row, _banksaladMapping)).toList(),
    );
  }
}
