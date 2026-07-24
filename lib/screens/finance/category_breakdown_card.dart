import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import '../../utils/formatters.dart';

/// 이번 달 지출을 카테고리별 가로 막대로 — 크기 비교이므로 카테고리마다 색을
/// 다르게 주지 않고 단일 색 + 내림차순 정렬 + 직접 라벨로 표현한다.
/// 상위 5개만 보여주고 나머지는 '기타'로 접는다. 행을 탭하면 거래 내역이
/// 그 카테고리로 필터링된다('기타'는 실제 카테고리가 아니라 탭 불가).
class CategoryBreakdownCard extends StatelessWidget {
  final Map<String, double> byCategory; // 금액 내림차순
  final String? selectedCategory;
  final ValueChanged<String> onCategoryTap;

  const CategoryBreakdownCard({
    super.key,
    required this.byCategory,
    required this.selectedCategory,
    required this.onCategoryTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final accent = Theme.of(context).colorScheme.primary;

    final entries = byCategory.entries.toList();
    final top = entries.take(5).toList();
    final restTotal = entries.skip(5).fold(0.0, (a, e) => a + e.value);
    final rows = [...top, if (restTotal > 0) MapEntry('기타', restTotal)];
    final maxValue = rows.map((e) => e.value).reduce((a, b) => a > b ? a : b);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '이번 달 카테고리별 지출',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text(
              '항목을 탭하면 해당 거래만 볼 수 있어요',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: colors.textMuted),
            ),
            const SizedBox(height: AppSpacing.md),
            ...rows.map((e) {
              final isTappable = e.key != '기타';
              final isSelected = e.key == selectedCategory;
              return InkWell(
                onTap: isTappable ? () => onCategoryTap(e.key) : null,
                borderRadius: BorderRadius.circular(AppRadius.sm),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    vertical: AppSpacing.xs,
                    horizontal: AppSpacing.xs,
                  ),
                  decoration: isSelected
                      ? BoxDecoration(
                          color: accent.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                        )
                      : null,
                  child: Row(
                    children: [
                      SizedBox(
                        width: 76,
                        child: Text(
                          e.key,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: isSelected ? null : colors.textMuted,
                                fontWeight: isSelected ? FontWeight.w700 : null,
                              ),
                        ),
                      ),
                      Expanded(
                        child: Container(
                          height: 8,
                          decoration: BoxDecoration(
                            color: colors.surfaceAlt,
                            borderRadius: BorderRadius.circular(AppRadius.full),
                          ),
                          child: FractionallySizedBox(
                            alignment: Alignment.centerLeft,
                            widthFactor: (e.value / maxValue).clamp(0.02, 1.0),
                            child: Container(
                              decoration: BoxDecoration(
                                color: e.key == '기타'
                                    ? colors.outlineStrong
                                    : accent,
                                borderRadius: BorderRadius.circular(
                                  AppRadius.full,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      SizedBox(
                        width: 92,
                        child: Text(
                          formatWon(e.value),
                          textAlign: TextAlign.right,
                          style: AppTypography.dataSmall(),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

class SummaryStat extends StatelessWidget {
  final String label;
  final double value;
  final Color color;

  const SummaryStat({
    super.key,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 2),
        Text(
          formatWon(value),
          style: AppTypography.dataMedium(
            color: color,
            weight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}
