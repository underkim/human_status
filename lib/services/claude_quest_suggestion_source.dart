import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import '../models/goal.dart';
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
  final List<Goal> goals;
  final String? preferredStatId;
  final Uuid _uuid;

  /// Caller-supplied HTTP client, e.g. for tests. When null, a fresh
  /// [http.Client] is created per request and closed afterwards; a supplied
  /// client is never closed by this source, since the caller owns it.
  final http.Client? httpClient;

  ClaudeQuestSuggestionSource({
    required this.apiKey,
    this.model = 'claude-sonnet-5',
    this.timeout = kClaudeRequestTimeout,
    this.goals = const [],
    this.preferredStatId,
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
    final recentQuests = existingQuests
        .map(
          (q) =>
              '- ${q.title} | ${q.difficulty.name} | ${q.status.name} | ${q.statRewards.keys.join("+")}',
        )
        .take(30)
        .toList();

    final activeGoalSummary = goals
        .where((g) => g.status == GoalStatus.active)
        .take(8)
        .map(
          (g) =>
              '- ${g.title} | stat=${g.statId} | ${g.description.isEmpty ? "no description" : g.description}',
        )
        .join('\n');

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
Preferred growth area: ${preferredStatId ?? '(not set)'}

Active goals to support:
${activeGoalSummary.isEmpty ? '(none)' : activeGoalSummary}

Recent quest history (never repeat or lightly reword these):
${recentQuests.isEmpty ? '(none)' : recentQuests.join('\n')}

Create exactly $count highly specific quests for the next 24 hours. Prioritize weak stats while giving the preferred area moderate weight. When active goals exist, include at least one quest that directly advances one of them, but keep at least one exploratory quest unrelated to a goal. Cover at least ${count >= 4 ? 3 : 2} different stats. Make every quest finishable in one sitting and vary the action pattern (movement, reflection, learning, money, connection, environment). Avoid vague verbs such as "improve", "work on", or "be mindful". Include a concrete duration, quantity, place, or trigger in each title or description. Mix easy, medium, and hard when the count permits. Do not recommend purchases, medical treatment, dangerous actions, or contacting a specific person without user choice.

Respond with ONLY a JSON array (no markdown, no commentary) where each element is:
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

    final validStatIds = stats.map((s) => s.id).toSet();
    final now = DateTime.now();
    final seenTitles = <String>{
      ...existingQuests.map((q) => _normalizedTitle(q.title)),
    };
    final suggestions = <Quest>[];
    for (final raw in parsed.whereType<Map>()) {
      final statId = raw['statId'];
      final title = raw['title'];
      if (statId is! String || title is! String || title.trim().isEmpty) {
        continue;
      }
      if (!validStatIds.contains(statId)) {
        continue;
      }
      if (!seenTitles.add(_normalizedTitle(title))) continue;
      final difficultyStr = raw['difficulty'] as String? ?? 'easy';
      final difficulty = QuestDifficulty.values.firstWhere(
        (d) => d.name == difficultyStr,
        orElse: () => QuestDifficulty.easy,
      );
      suggestions.add(
        Quest(
          id: _uuid.v4(),
          title: title.trim(),
          description: raw['description'] as String? ?? '',
          statRewards: {statId: (raw['xp'] as num?)?.toDouble() ?? 20},
          difficulty: difficulty,
          status: QuestStatus.suggested,
          source: QuestSource.suggested,
          createdAt: now,
        ),
      );
      if (suggestions.length == count) break;
    }
    // 부분 응답으로 기존 추천 묶음을 교체하면 사용자가 하루 동안 볼 수 있는
    // 선택지가 줄어든다. 완전한 묶음만 성공으로 인정해 로컬 fallback을 탄다.
    if (suggestions.length != count) {
      throw FormatException(
        'Claude returned ${suggestions.length} valid quests; expected $count',
      );
    }
    return suggestions;
  }

  static String _normalizedTitle(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9가-힣]'), '');
}
