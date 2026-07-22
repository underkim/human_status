import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../models/transaction.dart';
import '../providers/finance_provider.dart';
import '../providers/financial_advisor_provider.dart';
import '../providers/financial_planning_provider.dart';
import '../providers/goal_provider.dart';
import '../services/budget_service.dart';
import '../services/finance_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import '../utils/formatters.dart';
import '../widgets/empty_state.dart';
import '../widgets/goal_progress_card.dart';
import '../widgets/loading_state.dart';
import '../widgets/transaction_tile.dart';
import 'banksalad_import_screen.dart';

String _adviceIcon(String category) => switch (category) {
  'spending' => '💸',
  'goal' => '🎯',
  'networth' => '📈',
  _ => '💡',
};

class FinanceListView extends ConsumerStatefulWidget {
  const FinanceListView({super.key});

  @override
  ConsumerState<FinanceListView> createState() => _FinanceListViewState();
}

class _FinanceListViewState extends ConsumerState<FinanceListView> {
  /// 카테고리 막대를 탭하면 거래 내역이 그 카테고리만 보이도록 좁혀진다.
  String? _categoryFilter;

  /// 삭제가 진행 중인 거래 id 집합 — 확인 다이얼로그 응답과 실제 삭제
  /// 사이에 같은 행을 다시 눌러도 삭제가 두 번 들어가지 않도록 막는다.
  final Set<String> _pendingDeletes = {};

  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    // transactionSearchQueryProvider는 autoDispose라서 이 화면(그리고
    // searchedTransactionsProvider)을 아무도 watch하지 않게 되는 즉시 스스로
    // 폐기되고, 다시 들어오면 초기값('')부터 새로 시작한다 — 여기서 직접
    // clear()를 호출하지 않는다. 이 State 자신이 그 provider의 구독자이므로,
    // unmount 도중 상태를 갱신하면 이미 defunct된 자신의 Element를
    // rebuild하려는 어서션 실패가 난다.
    super.dispose();
  }

  /// 검색창의 지우기 버튼과 "검색 조건에 맞는 거래가 없어요" EmptyState의
  /// CTA가 함께 쓰는 경로 — controller와 provider를 항상 같이 정리한다.
  void _clearSearchText() {
    _searchController.clear();
    ref.read(transactionSearchQueryProvider.notifier).clear();
  }

  void _clearSearchAndCategoryFilter() {
    _searchController.clear();
    ref.read(transactionSearchQueryProvider.notifier).clear();
    setState(() => _categoryFilter = null);
  }

  Future<void> _confirmDeleteTransaction(
    BuildContext context,
    WidgetRef ref,
    String id,
    String category,
  ) async {
    // 확인창이 뜨기도 전에 같은 행을 빠르게 두 번 눌러도 확인창이 하나만
    // 뜨도록, 다이얼로그를 열기 직전에 바로 pending 집합에 넣는다 — 이
    // await 이전에 동기적으로 실행되므로 두 번째 탭은 여기서 곧장 막힌다.
    if (_pendingDeletes.contains(id)) return;
    setState(() => _pendingDeletes.add(id));
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('거래 삭제'),
          content: Text('"$category" 거래 기록을 삭제할까요? 되돌릴 수 없어요.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('삭제'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      try {
        await ref.read(transactionsProvider.notifier).deleteTransaction(id);
      } catch (_) {
        // 실패 시 롤백된 데이터가 그대로 보이고, 원인은 노출하지 않는다.
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('거래를 삭제하지 못했어요. 잠시 후 다시 시도해주세요.')),
          );
        }
      }
    } finally {
      // 취소·성공·실패 어느 경로든 pending 상태를 반드시 해제한다.
      if (mounted) setState(() => _pendingDeletes.remove(id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final monthKey = monthKeyOf(DateTime.now());
    final summary = ref.watch(monthlySummaryProvider(monthKey));
    // 요약/차트는 검색 입력과 무관하게 항상 전체 거래를 기준으로 계산한다.
    final transactions = [...ref.watch(transactionsProvider)]
      ..sort((a, b) => b.date.compareTo(a.date));
    final byCategory = FinanceService.expenseByCategory(transactions, monthKey);
    final monthlyExpenses = FinanceService.monthlyExpenses(transactions);
    final financialGoals = ref
        .watch(activeGoalsProvider)
        .where((g) => g.targetAmount != null)
        .toList();
    final progress = ref.watch(goalProgressMapProvider);
    final colors = context.appColors;
    final searchQuery = ref.watch(transactionSearchQueryProvider);
    final hasSearchQuery = searchQuery.trim().isNotEmpty;
    // 목록에는 검색 결과를 정렬한 뒤 카테고리 필터를 AND로 합성해 보여준다.
    final searchedTransactions = [...ref.watch(searchedTransactionsProvider)]
      ..sort((a, b) => b.date.compareTo(a.date));
    final filteredTransactions = _categoryFilter == null
        ? searchedTransactions
        : searchedTransactions
              .where((t) => t.category == _categoryFilter)
              .toList();

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        const _CoachingCard(),
        const SizedBox(height: AppSpacing.lg),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('이번 달', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: AppSpacing.md),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _SummaryStat(
                      label: '수입',
                      value: summary.income,
                      color: colors.success,
                    ),
                    _SummaryStat(
                      label: '지출',
                      value: summary.expense,
                      color: colors.error,
                    ),
                    _SummaryStat(
                      label: '순저축',
                      value: summary.net,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        _BudgetCard(
          spentThisMonth: summary.expense,
          spentByCategory: byCategory,
          categoryAverages: FinanceService.averageMonthlyExpenseByCategory(
            transactions,
          ),
        ),
        if (monthlyExpenses.values.any((v) => v > 0)) ...[
          const SizedBox(height: AppSpacing.lg),
          _MonthlyExpenseChartCard(monthlyExpenses: monthlyExpenses),
        ],
        if (byCategory.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.lg),
          _CategoryBreakdownCard(
            byCategory: byCategory,
            selectedCategory: _categoryFilter,
            onCategoryTap: (category) => setState(() {
              _categoryFilter = _categoryFilter == category ? null : category;
            }),
          ),
        ],
        if (financialGoals.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.lg),
          Text('재무 목표', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: AppSpacing.sm),
          ...financialGoals.map(
            (g) => GoalProgressCard(
              title: g.title,
              progress: progress[g.id] ?? 0,
              trailingInfo:
                  '${formatWon(g.currentAmount)} / ${formatWon(g.targetAmount!)}',
              targetDateLabel: g.targetDate != null
                  ? formatDday(g.targetDate!)
                  : null,
              completionHint: '금액이 목표에 도달하면 자동으로 완료돼요',
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.lg),
        // 좁은 화면에서는 액션 묶음이 제목 아래 줄로 내려가도록 Wrap을 쓴다 —
        // 고정 Row는 ~400dp 이하에서 가로로 넘친다.
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text('거래 내역', style: Theme.of(context).textTheme.titleLarge),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('${filteredTransactions.length}건'),
                IconButton(
                  icon: const Icon(Icons.add, size: AppIconSize.md),
                  tooltip: '거래 직접 추가',
                  onPressed: () => showAddTransactionDialog(context, ref),
                ),
                TextButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const BanksaladImportScreen(),
                    ),
                  ),
                  icon: const Icon(Icons.upload_file, size: AppIconSize.sm),
                  label: const Text('뱅크샐러드 파일 가져오기'),
                ),
              ],
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          child: TextField(
            controller: _searchController,
            onChanged: (value) => ref
                .read(transactionSearchQueryProvider.notifier)
                .setQuery(value),
            decoration: InputDecoration(
              hintText: '거래 검색',
              isDense: true,
              constraints: const BoxConstraints(
                minHeight: AppDimens.inputHeightStandard,
              ),
              prefixIcon: const Icon(Icons.search, size: AppIconSize.md),
              suffixIcon: hasSearchQuery
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: AppIconSize.md),
                      tooltip: '검색어 지우기',
                      onPressed: _clearSearchText,
                    )
                  : null,
            ),
          ),
        ),
        if (_categoryFilter != null)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xs),
            child: Align(
              alignment: Alignment.centerLeft,
              child: InputChip(
                label: Text('카테고리: $_categoryFilter'),
                onDeleted: () => setState(() => _categoryFilter = null),
                deleteButtonTooltipMessage: '필터 해제',
              ),
            ),
          ),
        if (transactions.isEmpty)
          const EmptyState(
            icon: Icons.receipt_long_outlined,
            message: '아직 기록된 거래가 없어요.',
          )
        else if (filteredTransactions.isEmpty && hasSearchQuery)
          EmptyState(
            icon: Icons.search_off,
            message: '검색 조건에 맞는 거래가 없어요.',
            ctaLabel: '검색 및 필터 초기화',
            onCta: _clearSearchAndCategoryFilter,
          )
        else if (filteredTransactions.isEmpty)
          EmptyState(
            icon: Icons.filter_alt_off_outlined,
            message: '"$_categoryFilter" 카테고리의 거래가 없어요.',
            ctaLabel: '필터 해제',
            onCta: () => setState(() => _categoryFilter = null),
          )
        else
          ..._groupedTransactionTiles(context, ref, filteredTransactions),
      ],
    );
  }

  /// 거래를 월 구분 헤더("2026년 7월")와 함께 나열한다 — 1년치 가져오기 후
  /// 수백 건이 한 덩어리로 이어지면 스크롤 중 시점을 잃기 쉽다.
  List<Widget> _groupedTransactionTiles(
    BuildContext context,
    WidgetRef ref,
    List<Transaction> transactions,
  ) {
    final colors = context.appColors;
    final widgets = <Widget>[];
    String? currentMonth;
    for (final t in transactions) {
      final mk = monthKeyOf(t.date);
      if (mk != currentMonth) {
        currentMonth = mk;
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(
              top: AppSpacing.md,
              bottom: AppSpacing.xs,
              left: 2,
            ),
            child: Text(
              '${t.date.year}년 ${t.date.month}월',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: colors.textMuted,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        );
      }
      final isDeleting = _pendingDeletes.contains(t.id);
      widgets.add(
        TransactionTile(
          transaction: t,
          trailing: IconButton(
            icon: const Icon(Icons.delete_outline, size: AppIconSize.md),
            onPressed: isDeleting
                ? null
                : () =>
                      _confirmDeleteTransaction(context, ref, t.id, t.category),
          ),
        ),
      );
    }
    return widgets;
  }
}

/// 이번 달 지출을 카테고리별 가로 막대로 — 크기 비교이므로 카테고리마다 색을
/// 다르게 주지 않고 단일 색 + 내림차순 정렬 + 직접 라벨로 표현한다.
/// 상위 5개만 보여주고 나머지는 '기타'로 접는다. 행을 탭하면 거래 내역이
/// 그 카테고리로 필터링된다('기타'는 실제 카테고리가 아니라 탭 불가).
class _CategoryBreakdownCard extends StatelessWidget {
  final Map<String, double> byCategory; // 금액 내림차순
  final String? selectedCategory;
  final ValueChanged<String> onCategoryTap;

  const _CategoryBreakdownCard({
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

/// 최근 6개월 지출 추이 막대 차트 — 단일 시리즈이므로 범례 없이 카드 제목이
/// 이름을 대신하고, 모든 달이 같은 색(순위·최신 여부로 색을 바꾸지 않음).
class _MonthlyExpenseChartCard extends StatelessWidget {
  final Map<String, double> monthlyExpenses; // 과거→현재 순

  const _MonthlyExpenseChartCard({required this.monthlyExpenses});

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
            SizedBox(
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
          ],
        ),
      ),
    );
  }
}

/// 이번 달 지출 예산 카드 — 미설정 / 여유 / 경고(90%+) / 초과 네 상태를
/// 색과 문구로 구분한다. 총 예산과 카테고리별 예산 모두 FinancialPlan에
/// 저장되어 백업에 포함.
class _BudgetCard extends ConsumerWidget {
  final double spentThisMonth;
  final Map<String, double> spentByCategory;

  /// 지난 몇 달 카테고리별 월 평균 지출 — 예산 추천의 근거.
  final Map<String, double> categoryAverages;

  const _BudgetCard({
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
      builder: (context) => _BudgetAmountDialog(initial: plan.monthlyBudget),
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
      builder: (context) => _CategoryBudgetDialog(
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

/// 총 예산 입력 다이얼로그. 컨트롤러를 State가 소유·정리한다.
/// 반환: null=취소 / 0=예산 삭제 / 양수=설정.
class _BudgetAmountDialog extends StatefulWidget {
  final double? initial;

  const _BudgetAmountDialog({required this.initial});

  @override
  State<_BudgetAmountDialog> createState() => _BudgetAmountDialogState();
}

class _BudgetAmountDialogState extends State<_BudgetAmountDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial != null ? widget.initial!.round().toString() : '',
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('이번 달 예산'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(
          labelText: '월 지출 한도(원)',
          hintText: '예: 1500000',
        ),
      ),
      actions: [
        if (widget.initial != null)
          TextButton(
            onPressed: () => Navigator.pop(context, 0.0),
            child: const Text('예산 삭제'),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('취소'),
        ),
        FilledButton(
          onPressed: () {
            final v = double.tryParse(
              _controller.text.replaceAll(RegExp(r'[^0-9]'), ''),
            );
            if (v != null && v > 0) Navigator.pop(context, v);
          },
          child: const Text('저장'),
        ),
      ],
    );
  }
}

/// 카테고리 예산 다이얼로그. [category]가 null이면 추가 모드(카테고리 입력),
/// 아니면 수정 모드. 반환: null=취소 / (cat,0)=삭제 / (cat,양수)=저장.
class _CategoryBudgetDialog extends StatefulWidget {
  final String? category;
  final double? initialAmount;

  const _CategoryBudgetDialog({
    required this.category,
    required this.initialAmount,
  });

  @override
  State<_CategoryBudgetDialog> createState() => _CategoryBudgetDialogState();
}

class _CategoryBudgetDialogState extends State<_CategoryBudgetDialog> {
  late final TextEditingController _categoryController = TextEditingController(
    text: widget.category ?? '',
  );
  late final TextEditingController _amountController = TextEditingController(
    text: widget.initialAmount != null
        ? widget.initialAmount!.round().toString()
        : '',
  );

  @override
  void dispose() {
    _categoryController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.category != null;
    return AlertDialog(
      title: Text(isEditing ? '${widget.category} 예산' : '카테고리 예산 추가'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _categoryController,
            enabled: !isEditing,
            autofocus: !isEditing,
            decoration: const InputDecoration(
              labelText: '카테고리',
              hintText: '예: 식비',
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            controller: _amountController,
            autofocus: isEditing,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: '월 지출 한도(원)',
              hintText: '예: 400000',
            ),
          ),
        ],
      ),
      actions: [
        if (isEditing)
          TextButton(
            onPressed: () => Navigator.pop(context, (widget.category!, 0.0)),
            child: const Text('삭제'),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('취소'),
        ),
        FilledButton(
          onPressed: () {
            final cat = _categoryController.text.trim();
            final v = double.tryParse(
              _amountController.text.replaceAll(RegExp(r'[^0-9]'), ''),
            );
            if (cat.isNotEmpty && v != null && v > 0) {
              Navigator.pop(context, (cat, v));
            }
          },
          child: const Text('저장'),
        ),
      ],
    );
  }
}

/// 재무 코칭 카드 — 데이터 없음 / 갱신 중 / 정상 세 상태를 명시적으로
/// 구분한다(이전엔 advice가 비어있으면 카드 자체가 조용히 사라졌음).
class _CoachingCard extends ConsumerStatefulWidget {
  const _CoachingCard();

  @override
  ConsumerState<_CoachingCard> createState() => _CoachingCardState();
}

class _CoachingCardState extends ConsumerState<_CoachingCard> {
  bool _isRefreshing = false;

  Future<void> _refresh() async {
    setState(() => _isRefreshing = true);
    await ref.read(financialAdviceProvider.notifier).refreshNow();
    if (mounted) setState(() => _isRefreshing = false);
  }

  @override
  Widget build(BuildContext context) {
    final advice = ref.watch(financialAdviceProvider);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('재무 코칭', style: Theme.of(context).textTheme.titleMedium),
                IconButton(
                  icon: const Icon(Icons.refresh, size: AppIconSize.md),
                  tooltip: '새로고침',
                  onPressed: _isRefreshing ? null : _refresh,
                ),
              ],
            ),
            Text(
              '지출 패턴·목표 진도·순자산 추이를 분석해 알려드려요',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: context.appColors.textMuted,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            if (_isRefreshing)
              const LoadingState(message: '코칭 내용을 분석하고 있어요...')
            else if (advice.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpacing.xs),
                child: Text('아직 코칭 내용이 없어요. 새로고침 버튼을 눌러보세요.'),
              )
            else
              ...advice.map(
                (a) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_adviceIcon(a.category)),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(child: Text(a.message)),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SummaryStat extends StatelessWidget {
  final String label;
  final double value;
  final Color color;

  const _SummaryStat({
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

Future<void> showAddTransactionDialog(
  BuildContext context,
  WidgetRef ref,
) async {
  final categoryController = TextEditingController();
  final memoController = TextEditingController();
  final amountController = TextEditingController();
  TransactionType type = TransactionType.expense;
  DateTime date = DateTime.now();
  String? linkedGoalId;
  bool isSaving = false;
  String? errorText;

  final financialGoals = ref
      .read(activeGoalsProvider)
      .where((g) => g.targetAmount != null)
      .toList();

  await showDialog<void>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) => AlertDialog(
        title: const Text('거래 추가'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SegmentedButton<TransactionType>(
                segments: const [
                  ButtonSegment(
                    value: TransactionType.expense,
                    label: Text('지출'),
                  ),
                  ButtonSegment(
                    value: TransactionType.income,
                    label: Text('수입'),
                  ),
                ],
                selected: {type},
                onSelectionChanged: (s) => setState(() => type = s.first),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: categoryController,
                autofocus: true,
                decoration: const InputDecoration(labelText: '카테고리'),
              ),
              const SizedBox(height: AppSpacing.sm),
              TextField(
                controller: memoController,
                decoration: const InputDecoration(labelText: '메모 (선택)'),
              ),
              const SizedBox(height: AppSpacing.sm),
              TextField(
                controller: amountController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: '금액'),
              ),
              const SizedBox(height: AppSpacing.sm),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('날짜'),
                subtitle: Text(date.toString().split(' ').first),
                trailing: const Icon(Icons.calendar_today),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: dialogContext,
                    initialDate: date,
                    firstDate: DateTime.now().subtract(
                      const Duration(days: 365),
                    ),
                    lastDate: DateTime.now(),
                  );
                  if (picked != null) setState(() => date = picked);
                },
              ),
              if (financialGoals.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.sm),
                DropdownButtonFormField<String?>(
                  initialValue: linkedGoalId,
                  decoration: const InputDecoration(
                    labelText: '저축 목표에 연결 (선택)',
                  ),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('연결 안 함'),
                    ),
                    ...financialGoals.map(
                      (g) => DropdownMenuItem<String?>(
                        value: g.id,
                        child: Text(g.title),
                      ),
                    ),
                  ],
                  onChanged: (v) => setState(() => linkedGoalId = v),
                ),
              ],
              if (errorText != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  errorText!,
                  style: TextStyle(
                    color: Theme.of(dialogContext).colorScheme.error,
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: isSaving ? null : () => Navigator.pop(dialogContext),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: isSaving
                ? null
                : () async {
                    final amount = double.tryParse(amountController.text);
                    if (amount == null ||
                        amount <= 0 ||
                        categoryController.text.trim().isEmpty) {
                      return;
                    }
                    final tx = Transaction(
                      id: const Uuid().v4(),
                      type: type,
                      category: categoryController.text.trim(),
                      memo: memoController.text.trim(),
                      amount: amount,
                      date: date,
                      linkedGoalId: linkedGoalId,
                      createdAt: DateTime.now(),
                    );
                    setState(() {
                      isSaving = true;
                      errorText = null;
                    });
                    try {
                      await ref
                          .read(transactionsProvider.notifier)
                          .addTransaction(tx);
                      if (dialogContext.mounted) Navigator.pop(dialogContext);
                    } catch (_) {
                      // 저장이 실패로 끝나기 전에 사용자가 바깥을 탭하거나 뒤로가기로
                      // 다이얼로그(이 StatefulBuilder)를 이미 닫았을 수 있다 — 그 경우
                      // setState를 부르면 dispose된 위젯에 예외가 난다.
                      if (!dialogContext.mounted) return;
                      // 실패 원인은 노출하지 않고 다이얼로그를 열어 둔 채 재시도를 유도한다.
                      setState(() {
                        isSaving = false;
                        errorText = '거래를 저장하지 못했어요. 잠시 후 다시 시도해주세요.';
                      });
                    }
                  },
            child: const Text('추가'),
          ),
        ],
      ),
    ),
  );
}
