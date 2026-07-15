import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:human_status/services/claude_financial_advice_source.dart';
import 'package:human_status/services/financial_advice_source.dart';

const _context = FinancialAdviceContext(
  currentMonthExpenseByCategory: {'식비': 100},
  previousMonthExpenseByCategory: {'식비': 80},
  goalProgress: [],
);

void main() {
  group('ClaudeFinancialAdviceSource', () {
    test('parses a well-formed Claude response into advice items', () async {
      final client = MockClient((request) async {
        return http.Response(
          '{"content": [{"type": "text", "text": "[{\\"category\\": \\"spending\\", \\"message\\": \\"식비를 살펴보세요\\"}]"}]}',
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final source = ClaudeFinancialAdviceSource(
        apiKey: 'key',
        httpClient: client,
      );

      final result = await source.generateAdvice(_context);

      expect(result, hasLength(1));
      expect(result.first.category, 'spending');
      expect(result.first.message, '식비를 살펴보세요');
    });

    test('throws on a non-200 HTTP status', () async {
      final client = MockClient(
        (request) async => http.Response('server error', 500),
      );
      final source = ClaudeFinancialAdviceSource(
        apiKey: 'key',
        httpClient: client,
      );

      expect(() => source.generateAdvice(_context), throwsA(isA<Exception>()));
    });

    test('throws when the response body has no JSON array', () async {
      final client = MockClient((request) async {
        return http.Response(
          '{"content": [{"type": "text", "text": "no json here"}]}',
          200,
        );
      });
      final source = ClaudeFinancialAdviceSource(
        apiKey: 'key',
        httpClient: client,
      );

      expect(() => source.generateAdvice(_context), throwsA(isA<Exception>()));
    });

    test(
      'a request that never completes fails after the configured timeout',
      () async {
        final neverResponds = Completer<http.Response>();
        final client = MockClient((request) => neverResponds.future);
        final source = ClaudeFinancialAdviceSource(
          apiKey: 'key',
          httpClient: client,
          timeout: const Duration(milliseconds: 50),
        );

        await expectLater(
          source.generateAdvice(_context),
          throwsA(isA<TimeoutException>()),
        );
      },
    );
  });
}
