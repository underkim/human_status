import '../models/goal.dart';
import '../models/quest.dart';
import '../models/stat.dart';

class AchievementContext {
  final List<Stat> stats;
  final List<Quest> completedQuests;
  final int streak;
  final int overallLevel;
  final List<Goal> goals;

  const AchievementContext({
    required this.stats,
    required this.completedQuests,
    required this.streak,
    required this.overallLevel,
    this.goals = const [],
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
  AchievementDefinition(
    id: 'first_goal_set',
    title: '목표 설정',
    description: '첫 목표를 설정했어요.',
    icon: '🧭',
    isUnlocked: (ctx) => ctx.goals.isNotEmpty,
  ),
  AchievementDefinition(
    id: 'first_goal_completed',
    title: '목표 달성',
    description: '첫 목표를 달성했어요.',
    icon: '🏆',
    isUnlocked: (ctx) => ctx.goals.any((g) => g.status == GoalStatus.completed),
  ),
  AchievementDefinition(
    id: 'goals_completed_5',
    title: '목표 수집가',
    description: '목표를 5개 달성했어요.',
    icon: '👑',
    isUnlocked: (ctx) => ctx.goals.where((g) => g.status == GoalStatus.completed).length >= 5,
  ),
  AchievementDefinition(
    id: 'financial_goal_reached',
    title: '재무 설계 성공',
    description: '재무 목표 금액을 달성했어요.',
    icon: '💵',
    isUnlocked: (ctx) =>
        ctx.goals.any((g) => g.status == GoalStatus.completed && g.targetAmount != null),
  ),
];
