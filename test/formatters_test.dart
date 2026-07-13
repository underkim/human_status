import 'package:flutter_test/flutter_test.dart';
import 'package:human_status/utils/formatters.dart';

void main() {
  group('formatWon', () {
    test('adds thousands separators and 원 suffix', () {
      expect(formatWon(2400000), '2,400,000원');
      expect(formatWon(0), '0원');
    });

    test('rounds fractional amounts', () {
      expect(formatWon(999.6), '1,000원');
    });
  });

  group('formatWonCompact', () {
    test('keeps small amounts as plain numbers', () {
      expect(formatWonCompact(3500), '3,500');
    });

    test('abbreviates 만 with separators', () {
      expect(formatWonCompact(42300000), '4,230만');
    });

    test('abbreviates 억 with one decimal, trimming .0', () {
      expect(formatWonCompact(120000000), '1.2억');
      expect(formatWonCompact(100000000), '1억');
      expect(formatWonCompact(1230000000), '12억');
    });

    test('keeps the sign for negative amounts', () {
      expect(formatWonCompact(-42300000), '-4,230만');
    });
  });

  group('formatDday', () {
    test('is D-DAY on the target date itself', () {
      expect(formatDday(DateTime.now()), 'D-DAY');
    });

    test('counts remaining days ignoring time of day', () {
      final now = DateTime.now();
      final target = DateTime(now.year, now.month, now.day).add(const Duration(days: 84));
      expect(formatDday(target), 'D-84');
    });

    test('reports overdue days', () {
      final now = DateTime.now();
      final target = DateTime(now.year, now.month, now.day).subtract(const Duration(days: 12));
      expect(formatDday(target), '기한 12일 지남');
    });
  });
}
