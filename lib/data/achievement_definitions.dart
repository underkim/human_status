import '../models/quest.dart';
import '../models/stat.dart';

class AchievementContext {
  final List<Stat> stats;
  final List<Quest> completedQuests;
  final int streak;
  final int overallLevel;

  const AchievementContext({
    required this.stats,
    required this.completedQuests,
    required this.streak,
    required this.overallLevel,
  });

  int levelOf(String statId) {
    for (final s in stats) {
      if (s.id == statId) return s.level;
    }
    return 0;
  }
}

class AchievementDefinition {
  final String id;
  final String title;
  final String description;
  final String icon;
  final bool Function(AchievementContext ctx) isUnlocked;

  const AchievementDefinition({
    required this.id,
    required this.title,
    required this.description,
    required this.icon,
    required this.isUnlocked,
  });
}

final achievementDefinitions = <AchievementDefinition>[
  AchievementDefinition(
    id: 'first_quest',
    title: '첫 걸음',
    description: '퀘스트를 1개 완료했어요.',
    icon: '🎯',
    isUnlocked: (ctx) => ctx.completedQuests.isNotEmpty,
  ),
  AchievementDefinition(
    id: 'quests_10',
    title: '꾸준함의 시작',
    description: '퀘스트를 10개 완료했어요.',
    icon: '📋',
    isUnlocked: (ctx) => ctx.completedQuests.length >= 10,
  ),
  AchievementDefinition(
    id: 'quests_50',
    title: '퀘스트 마스터',
    description: '퀘스트를 50개 완료했어요.',
    icon: '🏅',
    isUnlocked: (ctx) => ctx.completedQuests.length >= 50,
  ),
  AchievementDefinition(
    id: 'streak_3',
    title: '3일 연속',
    description: '3일 연속으로 퀘스트를 완료했어요.',
    icon: '🔥',
    isUnlocked: (ctx) => ctx.streak >= 3,
  ),
  AchievementDefinition(
    id: 'streak_7',
    title: '일주일 연속',
    description: '7일 연속으로 퀘스트를 완료했어요.',
    icon: '🔥',
    isUnlocked: (ctx) => ctx.streak >= 7,
  ),
  AchievementDefinition(
    id: 'any_stat_lv5',
    title: '전문가',
    description: '스텟 하나를 Lv.5까지 올렸어요.',
    icon: '⭐',
    isUnlocked: (ctx) => ctx.stats.any((s) => s.level >= 5),
  ),
  AchievementDefinition(
    id: 'all_stats_lv2',
    title: '균형 잡힌 삶',
    description: '모든 스텟을 Lv.2 이상으로 올렸어요.',
    icon: '⚖️',
    isUnlocked: (ctx) => ctx.stats.isNotEmpty && ctx.stats.every((s) => s.level >= 2),
  ),
  AchievementDefinition(
    id: 'overall_lv5',
    title: '레벨업!',
    description: '종합 레벨 5를 달성했어요.',
    icon: '🚀',
    isUnlocked: (ctx) => ctx.overallLevel >= 5,
  ),
];
