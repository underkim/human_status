import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/progression_provider.dart';
import '../screens/insights_screen.dart';
import '../services/achievement_progress_service.dart';
import '../theme/app_spacing.dart';

/// 오늘의 행동 허브 바로 아래, 스텟/레벨보다 먼저 보여주는 성장 여정 요약 —
/// "지금 하는 행동이 장기적으로 무엇을 쌓고 있는가"를 한눈에 답한다: 연속
/// 기록이 살아있는지, 이번 주 얼마나 움직였는지, 역대 최고 기록, 그리고
/// 가장 가까운 다음 업적. 값은 전부 [progressionSnapshotProvider] /
/// [nextAchievementProgressProvider]에서 오므로 InsightsScreen 상단과 항상
/// 일치한다.
class ProgressionJourneyCard extends ConsumerWidget {
  const ProgressionJourneyCard({super.key});

  static String statusCopy({
    required bool completedToday,
    required int currentStreak,
  }) {
    if (completedToday) return '오늘의 몫을 지켰어요. 내일도 이어가볼까요?';
    if (currentStreak > 0) return '퀘스트 하나만 완료하면 연속 기록이 오늘도 이어져요.';
    return '오늘부터 다시 시작해볼까요? 첫 걸음이 연속 기록의 시작이에요.';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final snapshot = ref.watch(progressionSnapshotProvider);
    final next = ref.watch(nextAchievementProgressProvider);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('성장 여정', style: theme.textTheme.titleLarge),
            const SizedBox(height: AppSpacing.xs),
            Text(
              statusCopy(
                completedToday: snapshot.completedToday,
                currentStreak: snapshot.currentStreak,
              ),
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: _StatColumn(
                    icon: '🔥',
                    label: '연속',
                    value: '${snapshot.currentStreak}일',
                  ),
                ),
                Expanded(
                  child: _StatColumn(
                    icon: '⭐',
                    label: '최고 기록',
                    value: '${snapshot.longestStreak}일',
                  ),
                ),
                Expanded(
                  child: _StatColumn(
                    icon: '📅',
                    label: '이번 주',
                    value: '${snapshot.activeDaysThisWeek}/7일',
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            if (next != null)
              _NextAchievement(next: next)
            else
              Text('모든 업적을 달성했어요! 🎉', style: theme.textTheme.bodyMedium),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const InsightsScreen()),
                ),
                child: const Text('통계·업적 보기'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatColumn extends StatelessWidget {
  final String icon;
  final String label;
  final String value;

  const _StatColumn({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Text('$icon $value', style: theme.textTheme.titleMedium),
        Text(label, style: theme.textTheme.bodySmall),
      ],
    );
  }
}

class _NextAchievement extends StatelessWidget {
  final NextAchievementProgress next;

  const _NextAchievement({required this.next});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(next.icon, style: const TextStyle(fontSize: 20)),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                '다음 업적: ${next.title}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          child: LinearProgressIndicator(value: next.ratio, minHeight: 6),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(next.label, style: theme.textTheme.bodySmall),
      ],
    );
  }
}
