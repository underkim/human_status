import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/achievement_definitions.dart';
import '../providers/profile_provider.dart';
import '../providers/quest_provider.dart';
import '../services/stats_insights_service.dart';
import '../theme/app_colors.dart';

const _weekdayLabels = ['월', '화', '수', '목', '금', '토', '일'];

class InsightsScreen extends ConsumerWidget {
  const InsightsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(statsProvider);
    final completedQuests = ref.watch(completedQuestsProvider);

    final streak = StatsInsightsService.currentStreak(completedQuests);
    final xpByDay = StatsInsightsService.xpByDay(completedQuests, days: 7);
    final totalXpByStat = StatsInsightsService.totalXpByStat(completedQuests);
    final unlockedAchievements = ref.watch(unlockedAchievementsProvider);

    final maxXp = xpByDay.values.fold<double>(0, (a, b) => b > a ? b : a);

    return Scaffold(
      appBar: AppBar(title: const Text('통계')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Text('🔥', style: TextStyle(fontSize: 32)),
                  const SizedBox(width: 12),
                  Text(
                    '$streak일 연속',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text('최근 7일 XP', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          SizedBox(
            height: 180,
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: maxXp <= 0 ? 10 : maxXp * 1.2,
                titlesData: FlTitlesData(
                  leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) {
                        final index = value.toInt();
                        if (index < 0 || index >= xpByDay.length) return const SizedBox.shrink();
                        final day = xpByDay.keys.elementAt(index);
                        return Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(_weekdayLabels[(day.weekday - 1) % 7]),
                        );
                      },
                    ),
                  ),
                ),
                borderData: FlBorderData(show: false),
                gridData: const FlGridData(show: false),
                barGroups: xpByDay.entries.toList().asMap().entries.map((entry) {
                  final index = entry.key;
                  final xp = entry.value.value;
                  return BarChartGroupData(
                    x: index,
                    barRods: [
                      BarChartRodData(
                        toY: xp,
                        color: Theme.of(context).colorScheme.primary,
                        width: 18,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text('스텟별 누적 획득 XP', style: Theme.of(context).textTheme.titleLarge),
          Card(
            child: Column(
              children: stats.map((s) {
                final total = totalXpByStat[s.id] ?? 0;
                return ListTile(
                  leading: Text(s.icon, style: const TextStyle(fontSize: 20)),
                  title: Text(s.name),
                  trailing: Text('${total.toInt()} XP'),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 24),
          Text('업적', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 3,
            children: achievementDefinitions.map((def) {
              final unlockedAt = unlockedAchievements[def.id];
              final isUnlocked = unlockedAt != null;
              final mutedColor = context.appColors.textMuted;
              return Card(
                color: isUnlocked ? null : Theme.of(context).colorScheme.surfaceContainerHighest,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Row(
                    children: [
                      Text(
                        isUnlocked ? def.icon : '🔒',
                        style: TextStyle(fontSize: 20, color: isUnlocked ? null : mutedColor),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              def.title,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: isUnlocked ? null : mutedColor,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              def.description,
                              style: TextStyle(fontSize: 11, color: mutedColor),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
