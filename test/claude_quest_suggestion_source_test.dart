import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:human_status/models/stat.dart';
import 'package:human_status/services/claude_quest_suggestion_source.dart';

List<Stat> _stats() => [Stat(id: 'health', name: '체력', icon: '💪', level: 1)];

void main() {
  group('ClaudeQuestSuggestionSource', () {
    test('parses a well-formed Claude response into quest suggestions', () async {
      final client = MockClient((request) async {
        return http.Response(
          '{"content": [{"type": "text", "text": "[{\\"title\\": \\"Walk\\", \\"description\\": \\"desc\\", \\"statId\\": \\"health\\", \\"difficulty\\": \\"easy\\", \\"xp\\": 15}]"}]}',
          200,
        );
      });
      final source = ClaudeQuestSuggestionSource(
        apiKey: 'key',
        httpClient: client,
      );

      final result = await source.generateSuggestions(
        stats: _stats(),
        existingQuests: [],
        count: 1,
      );

      expect(result, hasLength(1));
      expect(result.first.title, 'Walk');
      expect(result.first.statRewards['health'], 15);
    });

    test(
      'drops rows with invalid difficulty and falls back on incomplete batch',
      () async {
        final client = MockClient((request) async {
          return http.Response(
            '{"content": [{"type": "text", "text": "[{\\"title\\": \\"Walk\\", \\"statId\\": \\"health\\", \\"difficulty\\": \\"impossible\\", \\"xp\\": 15}]"}]}',
            200,
          );
        });
        final source = ClaudeQuestSuggestionSource(
          apiKey: 'key',
          httpClient: client,
        );

        expect(
          () => source.generateSuggestions(
            stats: _stats(),
            existingQuests: [],
            count: 1,
          ),
          throwsA(isA<FormatException>()),
        );
      },
    );

    test('drops rows with non-finite, zero, negative, or >100 xp', () async {
      final client = MockClient((request) async {
        return http.Response(
          '{"content": [{"type": "text", "text": "['
          '{\\"title\\": \\"A\\", \\"statId\\": \\"health\\", \\"difficulty\\": \\"easy\\", \\"xp\\": 0},'
          '{\\"title\\": \\"B\\", \\"statId\\": \\"health\\", \\"difficulty\\": \\"easy\\", \\"xp\\": -5},'
          '{\\"title\\": \\"C\\", \\"statId\\": \\"health\\", \\"difficulty\\": \\"easy\\", \\"xp\\": 101},'
          '{\\"title\\": \\"D\\", \\"statId\\": \\"health\\", \\"difficulty\\": \\"easy\\", \\"xp\\": null}'
          ']"}]}',
          200,
        );
      });
      final source = ClaudeQuestSuggestionSource(
        apiKey: 'key',
        httpClient: client,
      );

      expect(
        () => source.generateSuggestions(
          stats: _stats(),
          existingQuests: [],
          count: 1,
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('throws on a non-200 HTTP status', () async {
      final client = MockClient(
        (request) async => http.Response('server error', 500),
      );
      final source = ClaudeQuestSuggestionSource(
        apiKey: 'key',
        httpClient: client,
      );

      expect(
        () => source.generateSuggestions(stats: _stats(), existingQuests: []),
        throwsA(isA<Exception>()),
      );
    });

    test('throws when the response body has no JSON array', () async {
      final client = MockClient((request) async {
        return http.Response(
          '{"content": [{"type": "text", "text": "sorry, I cannot help with that"}]}',
          200,
        );
      });
      final source = ClaudeQuestSuggestionSource(
        apiKey: 'key',
        httpClient: client,
      );

      expect(
        () => source.generateSuggestions(stats: _stats(), existingQuests: []),
        throwsA(isA<Exception>()),
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
        MockClient(
          (request) async => http.Response(
            '{"content": [{"type": "text", "text": "[]"}]}',
            200,
          ),
        ),
        onClose: () => closed = true,
      );
      final source = ClaudeQuestSuggestionSource(
        apiKey: 'key',
        httpClient: client,
      );

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
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      _inner.send(request);

  @override
  void close() {
    onClose();
  }
}
