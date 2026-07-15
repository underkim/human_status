import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

/// GitHub 잔디밭 스타일 완료 히트맵. [countsByDay]는 월요일 시작 완전한 주로
/// 채워진 (날짜→완료 수) 맵이어야 한다(StatsInsightsService.completionCountByDay).
/// 한 열이 한 주, 위에서 아래로 월~일.
class CompletionHeatmap extends StatelessWidget {
  final Map<DateTime, int> countsByDay;

  const CompletionHeatmap({super.key, required this.countsByDay});

  static const _weekdayLabels = ['월', '', '수', '', '금', '', '일'];

  /// 완료 수 → 채도 단계(0~4). 절대 개수가 아니라 "했나/많이 했나" 수준만
  /// 구분하면 충분하므로 고정 구간을 쓴다.
  int _level(int count) {
    if (count <= 0) return 0;
    if (count == 1) return 1;
    if (count <= 3) return 2;
    if (count <= 5) return 3;
    return 4;
  }

  Color _cellColor(BuildContext context, int level) {
    final colors = context.appColors;
    if (level == 0) return colors.surfaceAlt;
    final base = Theme.of(context).colorScheme.primary;
    return base.withValues(alpha: [0.0, 0.35, 0.55, 0.78, 1.0][level]);
  }

  @override
  Widget build(BuildContext context) {
    final days = countsByDay.keys.toList()..sort();
    // 완전한 주로 채워져 있다는 전제 — 7로 나눠 주(열) 단위로 자른다.
    final weeks = <List<DateTime>>[];
    for (var i = 0; i < days.length; i += 7) {
      weeks.add(days.sublist(i, i + 7 <= days.length ? i + 7 : days.length));
    }

    const cell = 13.0;
    const gap = 3.0;

    final grid = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 요일 라벨 열.
        Column(
          children: [
            for (final label in _weekdayLabels)
              SizedBox(
                height: cell + gap,
                width: 18,
                child: Text(label, style: Theme.of(context).textTheme.bodySmall),
              ),
          ],
        ),
        for (final week in weeks)
          Padding(
            padding: const EdgeInsets.only(right: gap),
            child: Column(
              children: [
                for (final day in week)
                  Padding(
                    padding: const EdgeInsets.only(bottom: gap),
                    child: Tooltip(
                      message: '${day.month}/${day.day} · ${countsByDay[day]}개 완료',
                      child: Container(
                        width: cell,
                        height: cell,
                        decoration: BoxDecoration(
                          color: _cellColor(context, _level(countsByDay[day] ?? 0)),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          reverse: true, // 최근 주(오른쪽)가 먼저 보이게.
          child: grid,
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text('적음', style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(width: AppSpacing.xs),
            for (var level = 0; level <= 4; level++)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 1.5),
                child: Container(
                  width: 11,
                  height: 11,
                  decoration: BoxDecoration(
                    color: _cellColor(context, level),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            const SizedBox(width: AppSpacing.xs),
            Text('많음', style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ],
    );
  }
}
