import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import '../models/goal.dart';
import '../models/quest.dart';
import '../models/stat.dart';
import 'claude_request_defaults.dart';
import 'goal_decomposition_source.dart';

/// Asks the Claude API to break a single Goal down into concrete, actionable
/// quests. Throws on any network/parse failure (including a request that
/// exceeds [timeout]) so the caller can fall back to
/// LocalRuleGoalDecompositionSource — this source never mutates local state
/// itself. Modeled directly on ClaudeQuestSuggestionSource.
class ClaudeGoalDecompositionSource implements GoalDecompositionSource {
  final String apiKey;
  final String model;
  final Duration timeout;
  final Uuid _uuid;

  /// Caller-supplied HTTP client, e.g. for tests. When null, a fresh
  /// [http.Client] is created per request and closed afterwards; a supplied
  /// client is never closed by this source, since the caller owns it.
  final http.Client? httpClient;

  ClaudeGoalDecompositionSource({
    required this.apiKey,
    this.model = 'claude-sonnet-5',
    this.timeout = kClaudeRequestTimeout,
    this.httpClient,
    Uuid? uuid,
  }) : _uuid = uuid ?? const Uuid();

  static const _endpoint = 'https://api.anthropic.com/v1/messages';

  @override
  Future<List<Quest>> decompose({
    required Goal goal,
    required List<Stat> stats,
    required List<Quest> existingQuests,
    int count = 4,
  }) async {
    final statName = stats.where((s) => s.id == goal.statId).isNotEmpty
        ? stats.firstWhere((s) => s.id == goal.statId).name
        : goal.statId;

    final targetLine = goal.targetAmount != null
        ? '이 목표는 금액 목표예요: 목표 금액 ${goal.targetAmount!.toInt()}, 현재 ${goal.currentAmount.toInt()}.'
        : '';
    final dateLine = goal.targetDate != null
        ? '목표 기한: ${goal.targetDate!.toIso8601String().split('T').first}'
        : '';

    final prompt =
        '''
You are a life-coach helping someone break a long-term goal down into small, concrete real-world action steps ("quests").

Goal title: ${goal.title}
Goal description: ${goal.description}
Linked life stat: $statName
$targetLine
$dateLine

Existing quest titles to avoid:
${existingQuests.take(40).map((q) => '- ${q.title}').join('\n')}

Build exactly $count progressive quests that make tangible progress toward this goal. The set must include: one action doable in 5 minutes, one repeatable habit with a clear trigger, one measurable milestone, and one review/adjustment step. Every quest must specify a duration, quantity, place, or completion condition. Adapt the scale to the deadline and remaining amount when supplied. Avoid vague motivation, near-duplicate actions, purchases, medical treatment, and unsafe advice.

Respond with ONLY a JSON array (no markdown, no commentary) where each element is:
{"title": string, "description": string, "difficulty": "easy" | "medium" | "hard", "xp": number}
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
      throw Exception('Claude API request failed (${response.statusCode})');
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
      throw const FormatException('Claude response did not contain JSON');
    }
    final parsed = jsonDecode(text.substring(jsonStart, jsonEnd + 1)) as List;

    final now = DateTime.now();
    final seenTitles = <String>{
      ...existingQuests.map((q) => _normalizedTitle(q.title)),
    };
    final quests = <Quest>[];
    for (final raw in parsed.whereType<Map>()) {
      final title = raw['title'];
      if (title is! String || title.trim().isEmpty) continue;
      if (!seenTitles.add(_normalizedTitle(title))) continue;
      final difficultyStr = raw['difficulty'] as String? ?? 'easy';
      final difficulty = QuestDifficulty.values.firstWhere(
        (d) => d.name == difficultyStr,
        orElse: () => QuestDifficulty.easy,
      );
      quests.add(
        Quest(
          id: _uuid.v4(),
          title: title.trim(),
          description: raw['description'] as String? ?? '',
          // statId is always forced to the goal's own stat, regardless of what
          // Claude echoes back, to avoid an extra validStatIds check.
          statRewards: {goal.statId: (raw['xp'] as num?)?.toDouble() ?? 20},
          difficulty: difficulty,
          status: QuestStatus.active,
          source: QuestSource.manual,
          createdAt: now,
          goalId: goal.id,
        ),
      );
      if (quests.length == count) break;
    }
    return quests;
  }

  static String _normalizedTitle(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9가-힣]'), '');
}
