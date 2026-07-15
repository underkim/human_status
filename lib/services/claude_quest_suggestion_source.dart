import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import '../models/quest.dart';
import '../models/stat.dart';
import 'claude_request_defaults.dart';
import 'quest_suggestion_source.dart';

/// Generates quest suggestions by asking the Claude API to reason about the
/// user's current stat levels and recent quest history. Throws on any
/// network/parse failure (including a request that exceeds [timeout]) so the
/// caller can fall back to the local rule engine — this source never mutates
/// local state itself.
class ClaudeQuestSuggestionSource implements QuestSuggestionSource {
  final String apiKey;
  final String model;
  final Duration timeout;
  final Uuid _uuid;

  /// Caller-supplied HTTP client, e.g. for tests. When null, a fresh
  /// [http.Client] is created per request and closed afterwards; a supplied
  /// client is never closed by this source, since the caller owns it.
  final http.Client? httpClient;

  ClaudeQuestSuggestionSource({
    required this.apiKey,
    this.model = 'claude-sonnet-5',
    this.timeout = kClaudeRequestTimeout,
    this.httpClient,
    Uuid? uuid,
  }) : _uuid = uuid ?? const Uuid();

  static const _endpoint = 'https://api.anthropic.com/v1/messages';

  @override
  Future<List<Quest>> generateSuggestions({
    required List<Stat> stats,
    required List<Quest> existingQuests,
    int count = 4,
  }) async {
    final recentTitles = existingQuests
        .where(
          (q) =>
              q.source == QuestSource.suggested ||
              q.status == QuestStatus.completed,
        )
        .map((q) => q.title)
        .toSet()
        .take(30)
        .toList();

    final statSummary = stats
        .map(
          (s) =>
              '- ${s.id} (${s.name}): Lv.${s.level}, ${s.currentXp.toInt()} XP',
        )
        .join('\n');

    final prompt =
        '''
You are a life-gamification coach. The user tracks 5 life stats and completes small real-world "quests" to earn XP.

Current stats:
$statSummary

Stat ids you must use: ${stats.map((s) => s.id).join(', ')}.

Recently suggested or completed quest titles (do not repeat these):
${recentTitles.isEmpty ? '(none)' : recentTitles.join('\n')}

Suggest $count new quests, prioritizing the user's weakest stats. Respond with ONLY a JSON array (no markdown, no commentary) where each element is:
{"title": string, "description": string, "statId": one of the stat ids above, "difficulty": "easy" | "medium" | "hard", "xp": number}
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

    final validStatIds = stats.map((s) => s.id).toSet();
    final now = DateTime.now();
    return parsed.whereType<Map>().map((raw) {
      final statId = raw['statId'] as String;
      if (!validStatIds.contains(statId)) {
        throw Exception('Claude suggested an unknown statId: $statId');
      }
      final difficultyStr = raw['difficulty'] as String? ?? 'easy';
      final difficulty = QuestDifficulty.values.firstWhere(
        (d) => d.name == difficultyStr,
        orElse: () => QuestDifficulty.easy,
      );
      return Quest(
        id: _uuid.v4(),
        title: raw['title'] as String,
        description: raw['description'] as String? ?? '',
        statRewards: {statId: (raw['xp'] as num?)?.toDouble() ?? 20},
        difficulty: difficulty,
        status: QuestStatus.suggested,
        source: QuestSource.suggested,
        createdAt: now,
      );
    }).toList();
  }
}
