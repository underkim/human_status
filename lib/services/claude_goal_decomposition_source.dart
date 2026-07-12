import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import '../models/goal.dart';
import '../models/quest.dart';
import '../models/stat.dart';
import 'goal_decomposition_source.dart';

/// Asks the Claude API to break a single Goal down into concrete, actionable
/// quests. Throws on any network/parse failure so the caller can fall back
/// to LocalRuleGoalDecompositionSource — this source never mutates local
/// state itself. Modeled directly on ClaudeQuestSuggestionSource.
class ClaudeGoalDecompositionSource implements GoalDecompositionSource {
  final String apiKey;
  final String model;
  final Uuid _uuid;

  ClaudeGoalDecompositionSource({
    required this.apiKey,
    this.model = 'claude-sonnet-5',
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

    final prompt = '''
You are a life-coach helping someone break a long-term goal down into small, concrete real-world action steps ("quests").

Goal title: ${goal.title}
Goal description: ${goal.description}
Linked life stat: $statName
$targetLine
$dateLine

Suggest $count concrete quests that make tangible progress toward this goal. Respond with ONLY a JSON array (no markdown, no commentary) where each element is:
{"title": string, "description": string, "difficulty": "easy" | "medium" | "hard", "xp": number}
''';

    final response = await http.post(
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
    );

    if (response.statusCode != 200) {
      throw Exception('Claude API error ${response.statusCode}: ${response.body}');
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

    final now = DateTime.now();
    return parsed.whereType<Map>().map((raw) {
      final difficultyStr = raw['difficulty'] as String? ?? 'easy';
      final difficulty = QuestDifficulty.values.firstWhere(
        (d) => d.name == difficultyStr,
        orElse: () => QuestDifficulty.easy,
      );
      return Quest(
        id: _uuid.v4(),
        title: raw['title'] as String,
        description: raw['description'] as String? ?? '',
        // statId is always forced to the goal's own stat, regardless of what
        // Claude echoes back, to avoid an extra validStatIds check.
        statRewards: {goal.statId: (raw['xp'] as num?)?.toDouble() ?? 20},
        difficulty: difficulty,
        status: QuestStatus.active,
        source: QuestSource.manual,
        createdAt: now,
        goalId: goal.id,
      );
    }).toList();
  }
}
