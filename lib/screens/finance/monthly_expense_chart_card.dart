import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import '../../utils/formatters.dart';

/// 최근 6개월 지출 추이 막대 차트 — 단일 시리즈이므로 범례 없이 카드 제목이
/// 이름을 대신하고, 모든 달이 같은 색(순위·최신 여부로 색을 바꾸지 않음).
class MonthlyExpenseChartCard extends StatelessWidget {
  final Map<String, double> monthlyExpenses; // 과거→현재 순

  const MonthlyExpenseChartCard({super.key, required this.monthlyExpenses});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final accent = Theme.of(context).colorScheme.primary;

    final entries = monthlyExpenses.entries.toList();
    final maxValue = entries
        .map((e) => e.value)
        .reduce((a, b) => a > b ? a : b);
    final maxY = maxValue * 1.15;

    String monthLabel(String key) => '${int.parse(key.split('-')[1])}월';
    String fullLabel(String key) {
      final parts = key.split('-');
      return '${parts[0]}년 ${int.parse(parts[1])}월';
    }

    // 막대 그래프는 시각적으로만 값을 전달하므로, 보조기술 사용자가 같은
    // 정보(기간별 지출과 최고 지출 달)를 문장으로 얻을 수 있게 대체
    // 텍스트를 만든다. 차트 자체는 ExcludeSemantics로 중복 낭독을 막는다.
    final peak = entries.reduce((a, b) => a.value >= b.value ? a : b);
    final monthlyList = entries
        .map((e) => '${fullLabel(e.key)} ${formatWon(e.value)}')
        .join(', ');
    final chartSummary =
        '최근 ${entries.length}개월 지출: $monthlyList. '
        '가장 많이 쓴 달은 ${fullLabel(peak.key)}, ${formatWon(peak.value)}.';

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.sm,
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.sm,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: AppSpacing.sm),
              child: Text(
                '최근 6개월 지출',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Semantics(
              label: chartSummary,
              child: ExcludeSemantics(
                child: SizedBox(
                  height: 160,
                  child: BarChart(
                    BarChartData(
                      maxY: maxY,
                      alignment: BarChartAlignment.spaceAround,
                      gridData: FlGridData(
                        show: true,
                        drawVerticalLine: false,
                        horizontalInterval: maxY / 2,
                        getDrawingHorizontalLine: (v) =>
                            FlLine(color: colors.outline, strokeWidth: 1),
                      ),
                      borderData: FlBorderData(show: false),
                      titlesData: FlTitlesData(
                        topTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        rightTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 48,
                            interval: maxY / 2,
                            getTitlesWidget: (value, meta) => Padding(
                              padding: const EdgeInsets.only(right: 4),
                              child: Text(
                                formatWonCompact(value),
                                style: AppTypography.dataSmall(
                                  color: colors.textMuted,
                                ),
                                textAlign: TextAlign.right,
                              ),
                            ),
                          ),
                        ),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 24,
                            getTitlesWidget: (value, meta) {
                              final index = value.toInt();
                              if (index < 0 || index >= entries.length) {
                                return const SizedBox.shrink();
                              }
                              return Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text(
                                  monthLabel(entries[index].key),
                                  style: AppTypography.dataSmall(
                                    color: colors.textMuted,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                      barTouchData: BarTouchData(
                        touchTooltipData: BarTouchTooltipData(
                          getTooltipItem: (group, groupIndex, rod, rodIndex) =>
                              BarTooltipItem(
                                '${fullLabel(entries[group.x].key)}\n${formatWon(rod.toY)}',
                                TextStyle(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onInverseSurface,
                                  fontSize: 12,
                                ),
                              ),
                        ),
                      ),
                      barGroups: [
                        for (var i = 0; i < entries.length; i++)
                          BarChartGroupData(
                            x: i,
                            barRods: [
                              BarChartRodData(
                                toY: entries[i].value,
                                color: accent,
                                width: 16,
                                borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(4),
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
