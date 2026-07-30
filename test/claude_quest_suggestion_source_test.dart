import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:human_status/models/stat.dart';
import 'package:human_status/services/claude_quest_suggestion_source.dart';

List<Stat> _stats() => [Stat(id: 'health', name: '체력', icon: '💪', level: 1)];

String _toolUseResponse(List<Map<String, dynamic>> uses) => jsonEncode({
  'content': [
    for (var i = 0; i < uses.length; i++)
      {'type': 'tool_use', 'id': 'toolu_$i', 'name': 'propose_quest', 'input': uses[i]},
  ],
});

Map<String, dynamic> _quest({
  String title = 'Walk',
  String statId = 'health',
  String difficulty = 'easy',
  num xp = 15,
}) => {
  'title': title,
  'description': 'desc',
  'statId': statId,
  'difficulty': difficulty,
  'xp': xp,
};

void main() {
  group('ClaudeQuestSuggestionSource', () {
    test('accepts well-formed tool calls made in a single turn', () async {
      final client = MockClient((request) async {
        return http.Response(_toolUseResponse([_quest()]), 200);
      });
      final source = ClaudeQuestSuggestionSource(apiKey: 'key', httpClient: client);

      final result = await source.generateSuggestions(
        stats: _stats(),
        existingQuests: [],
        count: 1,
      );

      expect(result, hasLength(1));
      expect(result.first.title, 'Walk');
      expect(result.first.statRewards['health'], 15);
    });

    test('rejects an invalid call and accepts a corrected retry in the next turn', () async {
      var calls = 0;
      final client = MockClient((request) async {
        calls++;
        if (calls == 1) {
          return http.Response(
            _toolUseResponse([_quest(difficulty: 'impossible')]),
            200,
          );
        }
        // Second turn's request must carry the rejected tool_result.
        final sent = jsonDecode(request.body) as Map<String, dynamic>;
        final messages = sent['messages'] as List;
        final lastUserContent = (messages.last as Map)['content'] as List;
        expect(
          (lastUserContent.first as Map)['is_error'],
          isTrue,
          reason: 'retry request should include the rejection as a tool_result',
        );
        return http.Response(_toolUseResponse([_quest()]), 200);
      });
      final source = ClaudeQuestSuggestionSource(apiKey: 'key', httpClient: client);

      final result = await source.generateSuggestions(
        stats: _stats(),
        existingQuests: [],
        count: 1,
      );

      expect(calls, 2);
      expect(result, hasLength(1));
      expect(result.first.title, 'Walk');
    });

    test('drops duplicate titles within the same turn and retries for the rest', () async {
      var calls = 0;
      final client = MockClient((request) async {
        calls++;
        if (calls == 1) {
          return http.Response(
            _toolUseResponse([_quest(title: 'Walk'), _quest(title: 'Walk')]),
            200,
          );
        }
        return http.Response(_toolUseResponse([_quest(title: 'Stretch')]), 200);
      });
      final source = ClaudeQuestSuggestionSource(apiKey: 'key', httpClient: client);

      final result = await source.generateSuggestions(
        stats: _stats(),
        existingQuests: [],
        count: 2,
      );

      expect(result.map((q) => q.title).toSet(), {'Walk', 'Stretch'});
    });

    test('throws once the turn budget is exhausted without filling the batch', () async {
      var calls = 0;
      final client = MockClient((request) async {
        calls++;
        return http.Response(
          _toolUseResponse([_quest(statId: 'not-a-real-stat')]),
          200,
        );
      });
      final source = ClaudeQuestSuggestionSource(apiKey: 'key', httpClient: client);

      await expectLater(
        source.generateSuggestions(stats: _stats(), existingQuests: [], count: 1),
        throwsA(isA<FormatException>()),
      );
      expect(calls, 4);
    });

    test('throws on a non-200 HTTP status', () async {
      final client = MockClient((request) async => http.Response('server error', 500));
      final source = ClaudeQuestSuggestionSource(apiKey: 'key', httpClient: client);

      expect(
        () => source.generateSuggestions(stats: _stats(), existingQuests: []),
        throwsA(isA<Exception>()),
      );
    });

    test('throws when Claude never calls the tool', () async {
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'content': [
              {'type': 'text', 'text': "sorry, I cannot help with that"},
            ],
          }),
          200,
        );
      });
      final source = ClaudeQuestSuggestionSource(apiKey: 'key', httpClient: client);

      expect(
        () => source.generateSuggestions(stats: _stats(), existingQuests: []),
        throwsA(isA<FormatException>()),
      );
    });

    test(
      'a request that never completes fails after the configured timeout',
      () async {
        final neverResponds = Completer<http.Response>();
        final client = MockClient((request) => neverResponds.future);
        final source = ClaudeQuestSuggestionSource(
          apiKey: 'key',
          httpClient: client,
          timeout: const Duration(milliseconds: 50),
        );

        await expectLater(
          source.generateSuggestions(stats: _stats(), existingQuests: []),
          throwsA(isA<TimeoutException>()),
        );
      },
    );

    test('does not close a caller-supplied http client', () async {
      var closed = false;
      final client = _ClosingTrackerClient(
        MockClient((request) async => http.Response(_toolUseResponse([]), 200)),
        onClose: () => closed = true,
      );
      final source = ClaudeQuestSuggestionSource(apiKey: 'key', httpClient: client);

      await expectLater(
        source.generateSuggestions(stats: _stats(), existingQuests: []),
        throwsA(isA<FormatException>()),
      );

      expect(closed, isFalse);
    });
  });
}

/// Wraps a client to observe whether close() is ever called, without
/// actually closing the wrapped MockClient.
class _ClosingTrackerClient extends http.BaseClient {
  final http.Client _inner;
  final void Function() onClose;

  _ClosingTrackerClient(this._inner, {required this.onClose});

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) => _inner.send(request);

  @override
  void close() {
    onClose();
  }
}
