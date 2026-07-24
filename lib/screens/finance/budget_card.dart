import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/financial_planning_provider.dart';
import '../../services/budget_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import '../../utils/formatters.dart';
import 'budget_amount_dialog.dart';
import 'category_budget_dialog.dart';

/// 이번 달 지출 예산 카드 — 미설정 / 여유 / 경고(90%+) / 초과 네 상태를
/// 색과 문구로 구분한다. 총 예산과 카테고리별 예산 모두 FinancialPlan에
/// 저장되어 백업에 포함.
class BudgetCard extends ConsumerWidget {
  final double spentThisMonth;
  final Map<String, double> spentByCategory;

  /// 지난 몇 달 카테고리별 월 평균 지출 — 예산 추천의 근거.
  final Map<String, double> categoryAverages;

  const BudgetCard({
    super.key,
    required this.spentThisMonth,
    required this.spentByCategory,
    required this.categoryAverages,
  });

  Future<void> _editBudget(BuildContext context, WidgetRef ref) async {
    final plan = ref.read(financialPlanProvider);
    // 다이얼로그를 StatefulWidget으로 분리해 컨트롤러가 자기 State의
    // dispose에서 정리되도록 한다(await 뒤 즉시 dispose하면 닫힘 애니메이션
    // 도중 "used after disposed" 오류가 난다).
    final result = await showDialog<double>(
      context: context,
      builder: (context) => BudgetAmountDialog(initial: plan.monthlyBudget),
    );
    if (result == null) return;

    plan.monthlyBudget = result == 0 ? null : result;
    plan.updatedAt = DateTime.now();
    await ref.read(financialPlanProvider.notifier).savePlan(plan);
  }

  /// [category]가 null이면 추가 모드(카테고리 입력 가능), 아니면 수정 모드.
  Future<void> _editCategoryBudget(
    BuildContext context,
    WidgetRef ref, {
    String? category,
  }) async {
    final plan = ref.read(financialPlanProvider);
    final result = await showDialog<(String, double)>(
      context: context,
      builder: (context) => CategoryBudgetDialog(
        category: category,
        initialAmount: category != null ? plan.categoryBudgets[category] : null,
      ),
    );
    if (result == null) return;

    final (cat, amount) = result;
    if (amount == 0) {
      plan.categoryBudgets.remove(cat);
    } else {
      plan.categoryBudgets[cat] = amount;
    }
    plan.updatedAt = DateTime.now();
    await ref.read(financialPlanProvider.notifier).savePlan(plan);
  }

  /// [suggestions]를 미리보기로 띄우고, 적용하면 예산이 없던 카테고리에 한 번에
  /// 채워 넣는다.
  Future<void> _applySuggestions(
    BuildContext context,
    WidgetRef ref,
    Map<String, double> suggestions,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('지출 기반 예산 추천'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('최근 3개월 평균 지출을 바탕으로 예산을 제안해요. 적용 후 언제든 수정할 수 있어요.'),
            const SizedBox(height: AppSpacing.md),
            for (final e in suggestions.entries)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(e.key),
                    Text(
                      formatWon(e.value),
                      style: AppTypography.dataSmall(weight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('적용'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final plan = ref.read(financialPlanProvider);
    plan.categoryBudgets.addAll(suggestions);
    plan.updatedAt = DateTime.now();
    await ref.read(financialPlanProvider.notifier).savePlan(plan);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('카테고리 예산 ${suggestions.length}개를 추가했어요.')),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plan = ref.watch(financialPlanProvider);
    final budget = plan.monthlyBudget;
    final categoryBudgets = plan.categoryBudgets;
    final status = BudgetService.status(budget: budget, spent: spentThisMonth);
    final colors = context.appColors;

    final suggestions = BudgetService.suggestCategoryBudgets(
      averages: categoryAverages,
      alreadyBudgeted: categoryBudgets.keys.toSet(),
    );

    final addCategoryButton = TextButton.icon(
      onPressed: () => _editCategoryBudget(context, ref),
      icon: const Icon(Icons.add, size: AppIconSize.sm),
      label: const Text('카테고리 예산 추가'),
    );

    final suggestButton = suggestions.isEmpty
        ? null
        : TextButton.icon(
            onPressed: () => _applySuggestions(context, ref, suggestions),
            icon: const Icon(Icons.auto_awesome_outlined, size: AppIconSize.sm),
            label: const Text('지출로 예산 추천'),
          );

    if (status == BudgetStatus.none && categoryBudgets.isEmpty) {
      return Card(
        child: Column(
          children: [
            ListTile(
              leading: const Icon(Icons.savings_outlined),
              title: const Text('이번 달 예산'),
              subtitle: const Text('월 지출 한도를 정하면 남은 예산과 초과 여부를 보여드려요.'),
              trailing: TextButton(
                onPressed: () => _editBudget(context, ref),
                child: const Text('설정'),
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(
                  left: AppSpacing.sm,
                  bottom: AppSpacing.xs,
                ),
                child: Wrap(
                  spacing: AppSpacing.xs,
                  children: [addCategoryButton, ?suggestButton],
                ),
              ),
            ),
          ],
        ),
      );
    }

    // 급한 것부터 — 예산 대비 사용률이 높은 카테고리가 위로.
    final categoryEntries = categoryBudgets.entries.toList()
      ..sort(
        (a, b) => ((spentByCategory[b.key] ?? 0) / b.value).compareTo(
          (spentByCategory[a.key] ?? 0) / a.value,
        ),
      );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('이번 달 예산', style: Theme.of(context).textTheme.titleMedium),
                if (budget != null)
                  IconButton(
                    icon: const Icon(Icons.edit_outlined, size: AppIconSize.md),
                    tooltip: '예산 수정',
                    onPressed: () => _editBudget(context, ref),
                  )
                else
                  TextButton(
                    onPressed: () => _editBudget(context, ref),
                    child: const Text('총 예산 설정'),
                  ),
              ],
            ),
            if (budget != null)
              ..._totalBudgetSection(context, budget, status, colors),
            if (categoryEntries.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              for (final e in categoryEntries)
                _CategoryBudgetRow(
                  category: e.key,
                  budget: e.value,
                  spent: spentByCategory[e.key] ?? 0,
                  onTap: () =>
                      _editCategoryBudget(context, ref, category: e.key),
                ),
            ],
            Wrap(
              spacing: AppSpacing.xs,
              children: [addCategoryButton, ?suggestButton],
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _totalBudgetSection(
    BuildContext context,
    double budget,
    BudgetStatus status,
    AppColors colors,
  ) {
    final ratio = (spentThisMonth / budget).clamp(0.0, 1.0);
    final percent = (spentThisMonth / budget * 100).round();
    final barColor = switch (status) {
      BudgetStatus.exceeded => colors.error,
      BudgetStatus.warning => colors.warning,
      _ => Theme.of(context).colorScheme.primary,
    };
    final statusText = switch (status) {
      BudgetStatus.exceeded =>
        '예산을 ${formatWon(spentThisMonth - budget)} 초과했어요',
      BudgetStatus.warning =>
        '남은 예산 ${formatWon(budget - spentThisMonth)} — 거의 다 썼어요',
      _ => '남은 예산 ${formatWon(budget - spentThisMonth)}',
    };

    return [
      ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: LinearProgressIndicator(
          value: ratio,
          minHeight: 8,
          color: barColor,
        ),
      ),
      const SizedBox(height: AppSpacing.xs),
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            '${formatWon(spentThisMonth)} / ${formatWon(budget)}',
            style: AppTypography.dataSmall(),
          ),
          Text(
            '$percent%',
            style: AppTypography.dataSmall(weight: FontWeight.w700),
          ),
        ],
      ),
      const SizedBox(height: AppSpacing.xs),
      Text(
        statusText,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: status == BudgetStatus.ok ? colors.textMuted : barColor,
        ),
      ),
    ];
  }
}

/// 카테고리 하나의 예산 행 — 탭하면 수정/삭제 다이얼로그.
class _CategoryBudgetRow extends StatelessWidget {
  final String category;
  final double budget;
  final double spent;
  final VoidCallback onTap;

  const _CategoryBudgetRow({
    required this.category,
    required this.budget,
    required this.spent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final status = BudgetService.status(budget: budget, spent: spent);
    final barColor = switch (status) {
      BudgetStatus.exceeded => colors.error,
      BudgetStatus.warning => colors.warning,
      _ => Theme.of(context).colorScheme.primary,
    };

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    category,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
                Text(
                  '${formatWonCompact(spent)} / ${formatWonCompact(budget)}',
                  style: AppTypography.dataSmall(
                    color: status == BudgetStatus.ok
                        ? colors.textMuted
                        : barColor,
                    weight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 3),
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              child: LinearProgressIndicator(
                value: (spent / budget).clamp(0.0, 1.0),
                minHeight: 5,
                color: barColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
