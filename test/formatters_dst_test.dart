import 'package:flutter_test/flutter_test.dart';
import 'package:human_status/utils/formatters.dart';

void main() {
  group('formatDday calendar boundaries', () {
    test('ignores time of day through a spring-forward date boundary', () {
      expect(
        formatDday(DateTime(2026, 3, 9, 0), now: DateTime(2026, 3, 8, 23)),
        'D-1',
      );
    });

    test('ignores time of day through a fall-back date boundary', () {
      expect(
        formatDday(DateTime(2026, 11, 2, 0), now: DateTime(2026, 11, 1, 23)),
        'D-1',
      );
    });

    test('handles leap-day ordinal arithmetic', () {
      expect(
        formatDday(DateTime(2028, 3, 1), now: DateTime(2028, 2, 28)),
        'D-2',
      );
    });
  });
}
