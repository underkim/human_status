import 'dart:convert';

import 'package:http/http.dart' as http;

import 'claude_request_defaults.dart';
import 'financial_advice_source.dart';

/// Asks the Claude API to turn a FinancialAdviceContext's summarized numbers
/// into short, natural-language coaching comments. Only ever sees aggregated
/// figures (category totals, progress ratios) — never raw transactions.
/// Throws on any network/parse failure (including a request that exceeds
/// [timeout]) so the caller can fall back to LocalRuleFinancialAdviceSource.
/// Modeled directly on ClaudeGoalDecompositionSource.
class ClaudeFinancialAdviceSource implements FinancialAdviceSource {
  final String apiKey;
  final String model;
  final Duration timeout;

  /// Caller-supplied HTTP client, e.g. for tests. When null, a fresh
  /// [http.Client] is created per request and closed afterwards; a supplied
  /// client is never closed by this source, since the caller owns it.
  final http.Client? httpClient;

  ClaudeFinancialAdviceSource({
    required this.apiKey,
    this.model = 'claude-sonnet-5',
    this.timeout = kClaudeRequestTimeout,
    this.httpClient,
  });

  static const _endpoint = 'https://api.anthropic.com/v1/messages';

  @override
  Future<List<AdviceItem>> generateAdvice(
    FinancialAdviceContext context,
  ) async {
    final spendingLines = context.currentMonthExpenseByCategory.entries
        .map((e) {
          final previous = context.previousMonthExpenseByCategory[e.key] ?? 0;
          return '- ${e.key}: 이번달 ${e.value.toInt()}, 지난달 ${previous.toInt()}';
        })
        .join('\n');

    final goalLines = context.goalProgress
        .map((g) {
          final expected = g.expectedProgress != null
              ? '${(g.expectedProgress! * 100).round()}%'
              : '알수없음';
          return '- ${g.title}: 실제 진행률 ${(g.actualProgress * 100).round()}%, 기대 진행률 $expected';
        })
        .join('\n');

    final netWorthLine = context.netWorthChangePercent != null
        ? '순자산 변화: 이전 스냅샷 대비 ${context.netWorthChangePercent!.round()}%'
        : '순자산 변화: 비교할 스냅샷이 부족함';

    final prompt =
        '''
You are a personal budgeting coach. Based on the summarized numbers below, write short, encouraging coaching comments in Korean.

카테고리별 지출 (이번달 vs 지난달):
${spendingLines.isEmpty ? '(데이터 없음)' : spendingLines}

목표 저축 진행률:
${goalLines.isEmpty ? '(활성 재무 목표 없음)' : goalLines}

$netWorthLine

중요: 일반적인 예산·저축 습관 코칭만 하고, 특정 종목이나 금융상품의 매수/매도 추천은 절대 하지 마세요.

3~5개의 코멘트를 만들어주세요. 각 코멘트는 한두 문장으로 짧게. JSON 배열만 응답하세요(마크다운이나 설명 없이):
[{"category": "spending" | "goal" | "networth" | "general", "message": string}]
''';

    final client = httpClient ?? http.Client();
    http.Response response;
    try {
      response = await client
          .post(
            Uri.parse(_endpoint),
            headers: {
              'content-type': 'application/json',
              'x-api-key': apiKey,
              'anthropic-version': '2023-06-01',
            },
            body: jsonEncode({
              'model': model,
              'max_tokens': 1024,
              'messages': [
                {'role': 'user', 'content': prompt},
              ],
            }),
          )
          .timeout(timeout);
    } finally {
      if (httpClient == null) client.close();
    }

    if (response.statusCode != 200) {
      throw Exception(
        'Claude API error ${response.statusCode}: ${response.body}',
      );
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final content = body['content'] as List;
    final text = content
        .whereType<Map>()
        .where((c) => c['type'] == 'text')
        .map((c) => c['text'] as String)
        .join();

    final jsonStart = text.indexOf('[');
    final jsonEnd = text.lastIndexOf(']');
    if (jsonStart == -1 || jsonEnd == -1 || jsonEnd < jsonStart) {
      throw Exception('Could not find a JSON array in Claude response: $text');
    }
    final parsed = jsonDecode(text.substring(jsonStart, jsonEnd + 1)) as List;

    return parsed
        .whereType<Map>()
        .map((raw) {
          return AdviceItem(
            category: raw['category'] as String? ?? 'general',
            message: raw['message'] as String? ?? '',
          );
        })
        .where((a) => a.message.isNotEmpty)
        .toList();
  }
}
