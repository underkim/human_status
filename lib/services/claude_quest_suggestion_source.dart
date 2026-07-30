import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import '../models/goal.dart';
import '../models/quest.dart';
import '../models/stat.dart';
import 'claude_request_defaults.dart';
import 'quest_suggestion_source.dart';

/// Generates quest suggestions through an Anthropic tool-use conversation:
/// Claude must call the [_toolName] tool once per quest instead of returning
/// a JSON blob embedded in free text. Invalid tool calls (bad statId,
/// duplicate title, out-of-range xp, ...) are rejected with a `tool_result`
/// error so Claude can retry within the same request, bounded by
/// [_maxTurns] round-trips. Throws on any network/parse failure, an
/// unreachable turn budget, or a request that exceeds [timeout] so the
/// caller can fall back to the local rule engine — this source never
/// mutates local state itself.
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
  static const _toolName = 'propose_quest';

  /// Round-trips allowed to fill the requested quest count. Each turn can
  /// contain multiple tool calls, so this bounds retries after rejected
  /// calls rather than the number of quests.
  static const _maxTurns = 4;

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

    final validStatIds = stats.map((s) => s.id).toSet();

    const systemPrompt =
        'You are a life-gamification coach. The user tracks 5 life stats '
        'and completes small real-world "quests" to earn XP.';

    final userPrompt =
        '''
Current stats:
$statSummary

Stat ids you must use: ${validStatIds.join(', ')}.
Preferred growth area: ${preferredStatId ?? '(not set)'}

Active goals to support:
${activeGoalSummary.isEmpty ? '(none)' : activeGoalSummary}

Recent quest history (never repeat or lightly reword these):
${recentQuests.isEmpty ? '(none)' : recentQuests.join('\n')}

Call the $_toolName tool exactly $count times, once per quest, to submit highly specific quests for the next 24 hours. Prioritize weak stats while giving the preferred area moderate weight. When active goals exist, include at least one quest that directly advances one of them, but keep at least one exploratory quest unrelated to a goal. Cover at least ${count >= 4 ? 3 : 2} different stats. Make every quest finishable in one sitting and vary the action pattern (movement, reflection, learning, money, connection, environment). Avoid vague verbs such as "improve", "work on", or "be mindful". Include a concrete duration, quantity, place, or trigger in each title or description. Mix easy, medium, and hard when the count permits. Do not recommend purchases, medical treatment, dangerous actions, or contacting a specific person without user choice. If a call is rejected, read the reason and call the tool again with a corrected quest.
''';

    final tool = {
      'name': _toolName,
      'description': 'Propose one quest for the user to complete in the next 24 hours.',
      'input_schema': {
        'type': 'object',
        'properties': {
          'title': {'type': 'string'},
          'description': {'type': 'string'},
          'statId': {'type': 'string', 'enum': validStatIds.toList()},
          'difficulty': {
            'type': 'string',
            'enum': QuestDifficulty.values.map((d) => d.name).toList(),
          },
          'xp': {'type': 'number'},
        },
        'required': ['title', 'statId', 'difficulty', 'xp'],
      },
    };

    final messages = <Map<String, dynamic>>[
      {'role': 'user', 'content': userPrompt},
    ];

    final now = DateTime.now();
    final seenTitles = <String>{
      ...existingQuests.map((q) => _normalizedTitle(q.title)),
    };
    final suggestions = <Quest>[];

    final client = httpClient ?? http.Client();
    try {
      for (var turn = 0; turn < _maxTurns && suggestions.length < count; turn++) {
        final response = await client
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
                'system': systemPrompt,
                'tools': [tool],
                'tool_choice': {'type': 'any'},
                'messages': messages,
              }),
            )
            .timeout(timeout);

        if (response.statusCode != 200) {
          throw Exception('Claude API request failed (${response.statusCode})');
        }

        final body = jsonDecode(response.body) as Map<String, dynamic>;
        final content = (body['content'] as List).cast<Map<String, dynamic>>();
        final toolUses = content.where((c) => c['type'] == 'tool_use').toList();

        if (toolUses.isEmpty) continue;

        messages.add({'role': 'assistant', 'content': content});

        final toolResults = <Map<String, dynamic>>[];
        for (final use in toolUses) {
          final id = use['id'] as String;
          if (use['name'] != _toolName) {
            toolResults.add(_errorResult(id, 'Unknown tool.'));
            continue;
          }
          if (suggestions.length >= count) {
            toolResults.add(
              _errorResult(id, 'Already have $count accepted quests; stop calling the tool.'),
            );
            continue;
          }
          final input = (use['input'] as Map?)?.cast<String, dynamic>() ?? {};
          final error = _validationError(input, validStatIds, seenTitles);
          if (error != null) {
            toolResults.add(_errorResult(id, error));
            continue;
          }

          final title = (input['title'] as String).trim();
          seenTitles.add(_normalizedTitle(title));
          suggestions.add(
            Quest(
              id: _uuid.v4(),
              title: title,
              description: input['description'] as String? ?? '',
              statRewards: {input['statId'] as String: (input['xp'] as num).toDouble()},
              difficulty: QuestDifficulty.values.firstWhere(
                (d) => d.name == input['difficulty'],
              ),
              status: QuestStatus.suggested,
              source: QuestSource.suggested,
              createdAt: now,
            ),
          );
          toolResults.add({
            'type': 'tool_result',
            'tool_use_id': id,
            'content': 'Accepted.',
          });
        }

        if (suggestions.length >= count) break;
        messages.add({'role': 'user', 'content': toolResults});
      }
    } finally {
      if (httpClient == null) client.close();
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

  static String? _validationError(
    Map<String, dynamic> input,
    Set<String> validStatIds,
    Set<String> seenTitles,
  ) {
    final title = input['title'];
    if (title is! String || title.trim().isEmpty) {
      return 'title is required and must be non-empty.';
    }
    final statId = input['statId'];
    if (statId is! String || !validStatIds.contains(statId)) {
      return 'statId must be one of: ${validStatIds.join(', ')}.';
    }
    final difficulty = input['difficulty'];
    if (difficulty is! String ||
        !QuestDifficulty.values.any((d) => d.name == difficulty)) {
      return 'difficulty must be one of: '
          '${QuestDifficulty.values.map((d) => d.name).join(', ')}.';
    }
    final xp = input['xp'];
    if (xp is! num || !xp.isFinite || xp <= 0 || xp > 100) {
      return 'xp must be a finite number greater than 0 and at most 100.';
    }
    if (seenTitles.contains(_normalizedTitle(title))) {
      return 'title duplicates an existing or already-proposed quest; '
          'pick a different one.';
    }
    return null;
  }

  static Map<String, dynamic> _errorResult(String id, String message) => {
    'type': 'tool_result',
    'tool_use_id': id,
    'content': message,
    'is_error': true,
  };

  static String _normalizedTitle(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9가-힣]'), '');
}
