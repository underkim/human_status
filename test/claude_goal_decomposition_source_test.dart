import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:human_status/models/goal.dart';
import 'package:human_status/services/claude_goal_decomposition_source.dart';

Goal _goal() => Goal(
  id: 'g1',
  title: '5km 달리기',
  description: '',
  statId: 'health',
  createdAt: DateTime.now(),
);

void main() {
  group('ClaudeGoalDecompositionSource', () {
    test(
      'parses a well-formed Claude response into quests linked to the goal',
      () async {
        final client = MockClient((request) async {
          return http.Response(
            '{"content": [{"type": "text", "text": "[{\\"title\\": \\"준비운동\\", \\"description\\": \\"desc\\", \\"difficulty\\": \\"easy\\", \\"xp\\": 10}]"}]}',
            200,
            headers: {'content-type': 'application/json'},
          );
        });
        final source = ClaudeGoalDecompositionSource(
          apiKey: 'key',
          httpClient: client,
        );

        final result = await source.decompose(
          goal: _goal(),
          stats: [],
          existingQuests: [],
        );

        expect(result, hasLength(1));
        expect(result.first.title, '준비운동');
        expect(result.first.goalId, 'g1');
        expect(result.first.statRewards['health'], 10);
      },
    );

    test('throws on a non-200 HTTP status', () async {
      final client = MockClient(
        (request) async => http.Response('server error', 500),
      );
      final source = ClaudeGoalDecompositionSource(
        apiKey: 'key',
        httpClient: client,
      );

      expect(
        () => source.decompose(goal: _goal(), stats: [], existingQuests: []),
        throwsA(isA<Exception>()),
      );
    });

    test('throws when the response body has no JSON array', () async {
      final client = MockClient((request) async {
        return http.Response(
          '{"content": [{"type": "text", "text": "no json here"}]}',
          200,
        );
      });
      final source = ClaudeGoalDecompositionSource(
        apiKey: 'key',
        httpClient: client,
      );

      expect(
        () => source.decompose(goal: _goal(), stats: [], existingQuests: []),
        throwsA(isA<Exception>()),
      );
    });

    test(
      'a request that never completes fails after the configured timeout',
      () async {
        final neverResponds = Completer<http.Response>();
        final client = MockClient((request) => neverResponds.future);
        final source = ClaudeGoalDecompositionSource(
          apiKey: 'key',
          httpClient: client,
          timeout: const Duration(milliseconds: 50),
        );

        await expectLater(
          source.decompose(goal: _goal(), stats: [], existingQuests: []),
          throwsA(isA<TimeoutException>()),
        );
      },
    );
  });
}
