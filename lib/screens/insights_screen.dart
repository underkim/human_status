import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/achievement_definitions.dart';
import '../providers/profile_provider.dart';
import '../providers/progression_provider.dart';
import '../providers/quest_provider.dart';
import '../services/stats_insights_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../widgets/completion_heatmap.dart';
import '../widgets/page_content_bounds.dart';
import '../widgets/progression_journey_card.dart';

const _weekdayLabels = ['월', '화', '수', '목', '금', '토', '일'];

/// 막대 그래프는 시각 정보만 전달하므로, 보조기술 사용자가 같은 내용을
/// 문장으로 얻을 수 있는 대체 텍스트를 만든다.
String _xpChartSummary(Map<DateTime, double> xpByDay) {
  if (xpByDay.isEmpty) return '최근 7일 XP 데이터가 없어요.';
  final days = xpByDay.keys.toList();
  final values = xpByDay.values.toList();
  var peakIndex = 0;
  for (var i = 1; i < values.length; i++) {
    if (values[i] > values[peakIndex]) peakIndex = i;
  }
  String labelOf(int i) => _weekdayLabels[(days[i].weekday - 1) % 7];
  final perDay = [
    for (var i = 0; i < values.length; i++)
      '${labelOf(i)} ${values[i].round()}XP',
  ].join(', ');
  return '최근 7일 XP: $perDay. 가장 많이 획득한 요일은 ${labelOf(peakIndex)}, '
      '${values[peakIndex].round()}XP.';
}

class InsightsScreen extends ConsumerWidget {
  const InsightsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(statsProvider);
    final completedQuests = ref.watch(completedQuestsProvider);

    final snapshot = ref.watch(progressionSnapshotProvider);
    final nextAchievement = ref.watch(nextAchievementProgressProvider);
    final now = ref.watch(nowProvider);
    final completionCounts = StatsInsightsService.completionCountByDay(
      completedQuests,
      now: now,
    );
    final xpByDay = StatsInsightsService.xpByDay(
      completedQuests,
      days: 7,
      now: now,
    );
    final totalXpByStat = StatsInsightsService.totalXpByStat(
      completedQuests,
      now: now,
    );
    final unlockedAchievements = ref.watch(unlockedAchievementsProvider);

    final maxXp = xpByDay.values.fold<double>(0, (a, b) => b > a ? b : a);

    return Scaffold(
      appBar: AppBar(title: const Text('통계')),
      body: PageContentBounds(
        maxWidth: PageContentBounds.wide,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text('🔥', style: TextStyle(fontSize: 32)),
                        const SizedBox(width: 12),
                        Text(
                          '${snapshot.currentStreak}일 연속',
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      ProgressionJourneyCard.statusCopy(
                        completedToday: snapshot.completedToday,
                        currentStreak: snapshot.currentStreak,
                      ),
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '최고 기록 ${snapshot.longestStreak}일',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                        Expanded(
                          child: Text(
                            '이번 주 ${snapshot.activeDaysThisWeek}/7일',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                      ],
                    ),
                    if (nextAchievement != null) ...[
                      const SizedBox(height: AppSpacing.md),
                      Row(
                        children: [
                          Text(
                            nextAchievement.icon,
                            style: const TextStyle(fontSize: 18),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: Text(
                              '다음 업적: ${nextAchievement.title}',
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(fontWeight: FontWeight.w600),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                        child: LinearProgressIndicator(
                          value: nextAchievement.ratio,
                          minHeight: 6,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        nextAchievement.label,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ] else ...[
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        '모든 업적을 달성했어요! 🎉',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text('완료 기록', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: CompletionHeatmap(countsByDay: completionCounts),
              ),
            ),
            const SizedBox(height: 24),
            Text('최근 7일 XP', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Semantics(
              label: _xpChartSummary(xpByDay),
              child: ExcludeSemantics(
                child: SizedBox(
                  height: 180,
                  child: BarChart(
                    BarChartData(
                      alignment: BarChartAlignment.spaceAround,
                      maxY: maxXp <= 0 ? 10 : maxXp * 1.2,
                      titlesData: FlTitlesData(
                        leftTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        rightTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        topTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            getTitlesWidget: (value, meta) {
                              final index = value.toInt();
                              if (index < 0 || index >= xpByDay.length) {
                                return const SizedBox.shrink();
                              }
                              final day = xpByDay.keys.elementAt(index);
                              return Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  _weekdayLabels[(day.weekday - 1) % 7],
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                      borderData: FlBorderData(show: false),
                      gridData: const FlGridData(show: false),
                      barGroups: xpByDay.entries.toList().asMap().entries.map((
                        entry,
                      ) {
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
                  color: isUnlocked
                      ? null
                      : Theme.of(context).colorScheme.surfaceContainerHighest,
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Row(
                      children: [
                        Text(
                          isUnlocked ? def.icon : '🔒',
                          style: TextStyle(
                            fontSize: 20,
                            color: isUnlocked ? null : mutedColor,
                          ),
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
                                style: TextStyle(
                                  fontSize: 11,
                                  color: mutedColor,
                                ),
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
      ),
    );
  }
}
