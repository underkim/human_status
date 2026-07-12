import 'package:flutter_test/flutter_test.dart';
import 'package:human_status/data/achievement_definitions.dart';
import 'package:human_status/models/quest.dart';
import 'package:human_status/models/stat.dart';
import 'package:uuid/uuid.dart';

AchievementDefinition _def(String id) => achievementDefinitions.firstWhere((d) => d.id == id);

List<Quest> _completedQuests(int count) {
  return List.generate(
    count,
    (i) => Quest(
      id: const Uuid().v4(),
      title: 'q$i',
      description: '',
      statRewards: const {'health': 10},
      status: QuestStatus.completed,
      createdAt: DateTime.now(),
      completedAt: DateTime.now(),
    ),
  );
}

void main() {
  test('achievement ids are unique', () {
    final ids = achievementDefinitions.map((d) => d.id).toList();
    expect(ids.toSet().length, ids.length);
  });

  test('first_quest unlocks at exactly 1 completed quest, not 0', () {
    final def = _def('first_quest');
    expect(
      def.isUnlocked(AchievementContext(stats: [], completedQuests: [], streak: 0, overallLevel: 1)),
      isFalse,
    );
    expect(
      def.isUnlocked(AchievementContext(stats: [], completedQuests: _completedQuests(1), streak: 0, overallLevel: 1)),
      isTrue,
    );
  });

  test('quests_10 boundary', () {
    final def = _def('quests_10');
    expect(
      def.isUnlocked(AchievementContext(stats: [], completedQuests: _completedQuests(9), streak: 0, overallLevel: 1)),
      isFalse,
    );
    expect(
      def.isUnlocked(AchievementContext(stats: [], completedQuests: _completedQuests(10), streak: 0, overallLevel: 1)),
      isTrue,
    );
  });

  test('streak_3 and streak_7 boundaries', () {
    final ctx2 = AchievementContext(stats: [], completedQuests: [], streak: 2, overallLevel: 1);
    final ctx3 = AchievementContext(stats: [], completedQuests: [], streak: 3, overallLevel: 1);
    final ctx7 = AchievementContext(stats: [], completedQuests: [], streak: 7, overallLevel: 1);

    expect(_def('streak_3').isUnlocked(ctx2), isFalse);
    expect(_def('streak_3').isUnlocked(ctx3), isTrue);
    expect(_def('streak_7').isUnlocked(ctx3), isFalse);
    expect(_def('streak_7').isUnlocked(ctx7), isTrue);
  });

  test('any_stat_lv5 requires at least one stat at level 5', () {
    final def = _def('any_stat_lv5');
    final low = [Stat(id: 'health', name: '체력', icon: '', level: 4)];
    final high = [Stat(id: 'health', name: '체력', icon: '', level: 5)];

    expect(def.isUnlocked(AchievementContext(stats: low, completedQuests: [], streak: 0, overallLevel: 1)), isFalse);
    expect(def.isUnlocked(AchievementContext(stats: high, completedQuests: [], streak: 0, overallLevel: 1)), isTrue);
  });

  test('all_stats_lv2 requires every stat >= 2 and is false when there are no stats', () {
    final def = _def('all_stats_lv2');
    final mixed = [
      Stat(id: 'health', name: '체력', icon: '', level: 2),
      Stat(id: 'wealth', name: '재정', icon: '', level: 1),
    ];
    final allHigh = [
      Stat(id: 'health', name: '체력', icon: '', level: 2),
      Stat(id: 'wealth', name: '재정', icon: '', level: 3),
    ];

    expect(def.isUnlocked(AchievementContext(stats: [], completedQuests: [], streak: 0, overallLevel: 1)), isFalse);
    expect(def.isUnlocked(AchievementContext(stats: mixed, completedQuests: [], streak: 0, overallLevel: 1)), isFalse);
    expect(def.isUnlocked(AchievementContext(stats: allHigh, completedQuests: [], streak: 0, overallLevel: 1)), isTrue);
  });

  test('overall_lv5 boundary', () {
    final def = _def('overall_lv5');
    expect(def.isUnlocked(AchievementContext(stats: [], completedQuests: [], streak: 0, overallLevel: 4)), isFalse);
    expect(def.isUnlocked(AchievementContext(stats: [], completedQuests: [], streak: 0, overallLevel: 5)), isTrue);
  });
}
