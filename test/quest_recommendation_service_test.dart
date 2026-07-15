import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:human_status/data/quest_templates.dart';
import 'package:human_status/models/quest.dart';
import 'package:human_status/models/stat.dart';
import 'package:human_status/models/user_profile.dart';
import 'package:human_status/services/quest_recommendation_service.dart';
import 'package:human_status/services/storage_service.dart';
import 'package:uuid/uuid.dart';

import 'helpers/test_app.dart';

/// Always throws, simulating a timed-out or otherwise failed Claude request.
class _AlwaysFailsSource implements QuestSuggestionSource {
  @override
  Future<List<Quest>> generateSuggestions({
    required List<Stat> stats,
    required List<Quest> existingQuests,
    int count = 4,
  }) {
    throw TimeoutException('simulated timeout');
  }
}

/// Succeeds with a fixed batch, so tests can assert the new suggestions
/// replaced the stale ones.
class _FixedSuggestionsSource implements QuestSuggestionSource {
  final List<Quest> suggestions;
  _FixedSuggestionsSource(this.suggestions);

  @override
  Future<List<Quest>> generateSuggestions({
    required List<Stat> stats,
    required List<Quest> existingQuests,
    int count = 4,
  }) async => suggestions;
}

List<Stat> _fiveStats({required Map<String, int> levels}) {
  return [
    Stat(id: 'health', name: '체력', icon: '💪', level: levels['health'] ?? 1),
    Stat(
      id: 'intelligence',
      name: '지식',
      icon: '📚',
      level: levels['intelligence'] ?? 1,
    ),
    Stat(id: 'wealth', name: '재정', icon: '💰', level: levels['wealth'] ?? 1),
    Stat(
      id: 'relationships',
      name: '관계',
      icon: '🤝',
      level: levels['relationships'] ?? 1,
    ),
    Stat(id: 'mental', name: '멘탈', icon: '🧘', level: levels['mental'] ?? 1),
  ];
}

void main() {
  final source = LocalRuleQuestSuggestionSource(uuid: const Uuid());

  test('prioritizes suggestions for the weakest stat first', () async {
    final stats = _fiveStats(
      levels: {
        'health': 5,
        'intelligence': 5,
        'wealth': 1, // weakest
        'relationships': 5,
        'mental': 5,
      },
    );

    final suggestions = await source.generateSuggestions(
      stats: stats,
      existingQuests: [],
      count: 1,
    );

    expect(suggestions, hasLength(1));
    expect(suggestions.first.statRewards.keys, contains('wealth'));
  });

  test(
    'spreads the default suggestion batch across multiple stats instead of exhausting one',
    () async {
      final stats = _fiveStats(
        levels: {
          'health': 5,
          'intelligence': 5,
          'wealth': 1, // strictly weakest
          'relationships': 5,
          'mental': 5,
        },
      );

      final suggestions = await source.generateSuggestions(
        stats: stats,
        existingQuests: [],
        count: 4,
      );

      final statIdsUsed = suggestions
          .map((q) => q.statRewards.keys.first)
          .toSet();
      expect(statIdsUsed.length, greaterThan(1));
      // The strictly weakest stat should still be represented first.
      expect(suggestions.first.statRewards.keys, contains('wealth'));
    },
  );

  test(
    'does not suggest titles that were already suggested or completed',
    () async {
      final stats = _fiveStats(levels: {'wealth': 1});
      final wealthTitles = questTemplateBank
          .where((t) => t.statId == 'wealth')
          .map((t) => t.title)
          .toList();

      final existingQuests = wealthTitles
          .map(
            (title) => Quest(
              id: const Uuid().v4(),
              title: title,
              description: '',
              statRewards: const {'wealth': 20},
              status: QuestStatus.completed,
              source: QuestSource.suggested,
              createdAt: DateTime.now(),
            ),
          )
          .toList();

      final suggestions = await source.generateSuggestions(
        stats: stats,
        existingQuests: existingQuests,
        count: 4,
      );

      for (final q in suggestions) {
        expect(wealthTitles, isNot(contains(q.title)));
      }
    },
  );

  test(
    'never returns duplicate titles within a single suggestion batch',
    () async {
      final stats = _fiveStats(levels: {});

      final suggestions = await source.generateSuggestions(
        stats: stats,
        existingQuests: [],
        count: 10,
      );

      final titles = suggestions.map((q) => q.title).toList();
      expect(titles.toSet().length, titles.length);
    },
  );

  test('marks generated quests as suggested/source=suggested', () async {
    final stats = _fiveStats(levels: {});
    final suggestions = await source.generateSuggestions(
      stats: stats,
      existingQuests: [],
      count: 2,
    );

    for (final q in suggestions) {
      expect(q.status, QuestStatus.suggested);
      expect(q.source, QuestSource.suggested);
    }
  });

  group('QuestRecommendationService.shouldRefresh', () {
    final service = QuestRecommendationService(storage: StorageService());

    test('is true when never refreshed', () {
      expect(service.shouldRefresh(UserProfile()), isTrue);
    });

    test('is false right after a refresh', () {
      expect(
        service.shouldRefresh(UserProfile(lastQuestRefresh: DateTime.now())),
        isFalse,
      );
    });

    test('is true once the refresh interval has elapsed', () {
      final stale = DateTime.now().subtract(const Duration(hours: 25));
      expect(
        service.shouldRefresh(UserProfile(lastQuestRefresh: stale)),
        isTrue,
      );
    });
  });

  group('QuestRecommendationService.refreshIfNeeded', () {
    late StorageService storage;

    setUp(() async {
      storage = await createTestStorage();
    });

    Quest staleSuggestion() => Quest(
      id: const Uuid().v4(),
      title: 'old suggestion',
      description: '',
      statRewards: const {'wealth': 20},
      status: QuestStatus.suggested,
      source: QuestSource.suggested,
      createdAt: DateTime.now(),
    );

    test('replaces stale suggestions with a fresh batch on success', () async {
      await storage.saveQuest(staleSuggestion());
      final fresh = Quest(
        id: const Uuid().v4(),
        title: 'fresh suggestion',
        description: '',
        statRewards: const {'wealth': 20},
        status: QuestStatus.suggested,
        source: QuestSource.suggested,
        createdAt: DateTime.now(),
      );
      final service = QuestRecommendationService(
        storage: storage,
        source: _FixedSuggestionsSource([fresh]),
      );

      await service.refreshIfNeeded();

      final suggestions = storage
          .getQuests()
          .where((q) => q.status == QuestStatus.suggested)
          .toList();
      expect(suggestions, hasLength(1));
      expect(suggestions.first.title, 'fresh suggestion');
      expect(storage.getProfile().lastQuestRefresh, isNotNull);
    });

    test(
      'a Claude timeout falls back to the local rule engine and still replaces suggestions',
      () async {
        await storage.saveQuest(staleSuggestion());
        // The default `source` is Claude-shaped here (throws); refreshIfNeeded
        // is expected to catch the failure and fall back internally to
        // LocalRuleQuestSuggestionSource.
        final service = QuestRecommendationService(
          storage: storage,
          source: _AlwaysFailsSource(),
        );

        await service.refreshIfNeeded();

        final suggestions = storage
            .getQuests()
            .where((q) => q.status == QuestStatus.suggested)
            .toList();
        expect(suggestions, isNotEmpty);
        expect(suggestions.every((q) => q.title != 'old suggestion'), isTrue);
        expect(storage.getProfile().lastQuestRefresh, isNotNull);
      },
    );

    test(
      'lastQuestRefresh is left untouched when refresh is not due',
      () async {
        final recent = DateTime.now();
        final profile = storage.getProfile();
        profile.lastQuestRefresh = recent;
        await storage.saveProfile(profile);
        final service = QuestRecommendationService(
          storage: storage,
          source: _FixedSuggestionsSource([]),
        );

        await service.refreshIfNeeded();

        expect(storage.getProfile().lastQuestRefresh, recent);
      },
    );
  });
}
