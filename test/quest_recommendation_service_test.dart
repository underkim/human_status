import 'package:flutter_test/flutter_test.dart';
import 'package:human_status/data/quest_templates.dart';
import 'package:human_status/models/quest.dart';
import 'package:human_status/models/stat.dart';
import 'package:human_status/models/user_profile.dart';
import 'package:human_status/services/quest_recommendation_service.dart';
import 'package:human_status/services/storage_service.dart';
import 'package:uuid/uuid.dart';

List<Stat> _fiveStats({required Map<String, int> levels}) {
  return [
    Stat(id: 'health', name: '체력', icon: '💪', level: levels['health'] ?? 1),
    Stat(id: 'intelligence', name: '지식', icon: '📚', level: levels['intelligence'] ?? 1),
    Stat(id: 'wealth', name: '재정', icon: '💰', level: levels['wealth'] ?? 1),
    Stat(id: 'relationships', name: '관계', icon: '🤝', level: levels['relationships'] ?? 1),
    Stat(id: 'mental', name: '멘탈', icon: '🧘', level: levels['mental'] ?? 1),
  ];
}

void main() {
  final source = LocalRuleQuestSuggestionSource(uuid: const Uuid());

  test('prioritizes suggestions for the weakest stat first', () async {
    final stats = _fiveStats(levels: {
      'health': 5,
      'intelligence': 5,
      'wealth': 1, // weakest
      'relationships': 5,
      'mental': 5,
    });

    final suggestions = await source.generateSuggestions(
      stats: stats,
      existingQuests: [],
      count: 1,
    );

    expect(suggestions, hasLength(1));
    expect(suggestions.first.statRewards.keys, contains('wealth'));
  });

  test('spreads the default suggestion batch across multiple stats instead of exhausting one', () async {
    final stats = _fiveStats(levels: {
      'health': 5,
      'intelligence': 5,
      'wealth': 1, // strictly weakest
      'relationships': 5,
      'mental': 5,
    });

    final suggestions = await source.generateSuggestions(
      stats: stats,
      existingQuests: [],
      count: 4,
    );

    final statIdsUsed = suggestions.map((q) => q.statRewards.keys.first).toSet();
    expect(statIdsUsed.length, greaterThan(1));
    // The strictly weakest stat should still be represented first.
    expect(suggestions.first.statRewards.keys, contains('wealth'));
  });

  test('does not suggest titles that were already suggested or completed', () async {
    final stats = _fiveStats(levels: {'wealth': 1});
    final wealthTitles = questTemplateBank
        .where((t) => t.statId == 'wealth')
        .map((t) => t.title)
        .toList();

    final existingQuests = wealthTitles
        .map((title) => Quest(
              id: const Uuid().v4(),
              title: title,
              description: '',
              statRewards: const {'wealth': 20},
              status: QuestStatus.completed,
              source: QuestSource.suggested,
              createdAt: DateTime.now(),
            ))
        .toList();

    final suggestions = await source.generateSuggestions(
      stats: stats,
      existingQuests: existingQuests,
      count: 4,
    );

    for (final q in suggestions) {
      expect(wealthTitles, isNot(contains(q.title)));
    }
  });

  test('never returns duplicate titles within a single suggestion batch', () async {
    final stats = _fiveStats(levels: {});

    final suggestions = await source.generateSuggestions(
      stats: stats,
      existingQuests: [],
      count: 10,
    );

    final titles = suggestions.map((q) => q.title).toList();
    expect(titles.toSet().length, titles.length);
  });

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
}
