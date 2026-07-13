import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../models/transaction.dart';
import '../providers/finance_provider.dart';
import '../providers/financial_advisor_provider.dart';
import '../providers/goal_provider.dart';
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

  Future<void> _confirmDeleteTransaction(BuildContext context, WidgetRef ref, String id, String category) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('거래 삭제'),
        content: Text('"$category" 거래 기록을 삭제할까요? 되돌릴 수 없어요.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('취소')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('삭제')),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(transactionsProvider.notifier).deleteTransaction(id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final monthKey = monthKeyOf(DateTime.now());
    final summary = ref.watch(monthlySummaryProvider(monthKey));
    final transactions = [...ref.watch(transactionsProvider)]..sort((a, b) => b.date.compareTo(a.date));
    final byCategory = FinanceService.expenseByCategory(transactions, monthKey);
    final monthlyExpenses = FinanceService.monthlyExpenses(transactions);
    final financialGoals = ref.watch(activeGoalsProvider).where((g) => g.targetAmount != null).toList();
    final progress = ref.watch(goalProgressMapProvider);
    final colors = context.appColors;
    final filteredTransactions = _categoryFilter == null
        ? transactions
        : transactions.where((t) => t.category == _categoryFilter).toList();

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
                    _SummaryStat(label: '수입', value: summary.income, color: colors.success),
                    _SummaryStat(label: '지출', value: summary.expense, color: colors.error),
                    _SummaryStat(label: '순저축', value: summary.net, color: Theme.of(context).colorScheme.primary),
                  ],
                ),
              ],
            ),
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
          ...financialGoals.map((g) => GoalProgressCard(
                title: g.title,
                progress: progress[g.id] ?? 0,
                trailingInfo: '${formatWon(g.currentAmount)} / ${formatWon(g.targetAmount!)}',
                targetDateLabel: g.targetDate != null ? formatDday(g.targetDate!) : null,
                completionHint: '금액이 목표에 도달하면 자동으로 완료돼요',
              )),
        ],
        const SizedBox(height: AppSpacing.lg),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('거래 내역', style: Theme.of(context).textTheme.titleLarge),
            Row(
              children: [
                Text('${filteredTransactions.length}건'),
                IconButton(
                  icon: const Icon(Icons.add, size: AppIconSize.md),
                  tooltip: '거래 직접 추가',
                  onPressed: () => showAddTransactionDialog(context, ref),
                ),
                TextButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const BanksaladImportScreen()),
                  ),
                  icon: const Icon(Icons.upload_file, size: AppIconSize.sm),
                  label: const Text('뱅크샐러드 파일 가져오기'),
                ),
              ],
            ),
          ],
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
  List<Widget> _groupedTransactionTiles(BuildContext context, WidgetRef ref, List<Transaction> transactions) {
    final colors = context.appColors;
    final widgets = <Widget>[];
    String? currentMonth;
    for (final t in transactions) {
      final mk = monthKeyOf(t.date);
      if (mk != currentMonth) {
        currentMonth = mk;
        widgets.add(Padding(
          padding: const EdgeInsets.only(top: AppSpacing.md, bottom: AppSpacing.xs, left: 2),
          child: Text(
            '${t.date.year}년 ${t.date.month}월',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: colors.textMuted,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ));
      }
      widgets.add(TransactionTile(
        transaction: t,
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline, size: AppIconSize.md),
          onPressed: () => _confirmDeleteTransaction(context, ref, t.id, t.category),
        ),
      ));
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
    final rows = [
      ...top,
      if (restTotal > 0) MapEntry('기타', restTotal),
    ];
    final maxValue = rows.map((e) => e.value).reduce((a, b) => a > b ? a : b);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('이번 달 카테고리별 지출', style: Theme.of(context).textTheme.titleMedium),
            Text(
              '항목을 탭하면 해당 거래만 볼 수 있어요',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colors.textMuted),
            ),
            const SizedBox(height: AppSpacing.md),
            ...rows.map((e) {
              final isTappable = e.key != '기타';
              final isSelected = e.key == selectedCategory;
              return InkWell(
                onTap: isTappable ? () => onCategoryTap(e.key) : null,
                borderRadius: BorderRadius.circular(AppRadius.sm),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs, horizontal: AppSpacing.xs),
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
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
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
                                color: e.key == '기타' ? colors.outlineStrong : accent,
                                borderRadius: BorderRadius.circular(AppRadius.full),
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
    final maxValue = entries.map((e) => e.value).reduce((a, b) => a > b ? a : b);
    final maxY = maxValue * 1.15;

    String monthLabel(String key) => '${int.parse(key.split('-')[1])}월';
    String fullLabel(String key) {
      final parts = key.split('-');
      return '${parts[0]}년 ${int.parse(parts[1])}월';
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.sm, AppSpacing.lg, AppSpacing.lg, AppSpacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: AppSpacing.sm),
              child: Text('최근 6개월 지출', style: Theme.of(context).textTheme.titleMedium),
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
                    getDrawingHorizontalLine: (v) => FlLine(color: colors.outline, strokeWidth: 1),
                  ),
                  borderData: FlBorderData(show: false),
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 48,
                        interval: maxY / 2,
                        getTitlesWidget: (value, meta) => Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: Text(
                            formatWonCompact(value),
                            style: AppTypography.dataSmall(color: colors.textMuted),
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
                          if (index < 0 || index >= entries.length) return const SizedBox.shrink();
                          return Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              monthLabel(entries[index].key),
                              style: AppTypography.dataSmall(color: colors.textMuted),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  barTouchData: BarTouchData(
                    touchTooltipData: BarTouchTooltipData(
                      getTooltipItem: (group, groupIndex, rod, rodIndex) => BarTooltipItem(
                        '${fullLabel(entries[group.x].key)}\n${formatWon(rod.toY)}',
                        TextStyle(color: Theme.of(context).colorScheme.onInverseSurface, fontSize: 12),
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
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
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
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: context.appColors.textMuted),
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
              ...advice.map((a) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_adviceIcon(a.category)),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(child: Text(a.message)),
                      ],
                    ),
                  )),
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

  const _SummaryStat({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 2),
        Text(formatWon(value), style: AppTypography.dataMedium(color: color, weight: FontWeight.bold)),
      ],
    );
  }
}

Future<void> showAddTransactionDialog(BuildContext context, WidgetRef ref) async {
  final categoryController = TextEditingController();
  final memoController = TextEditingController();
  final amountController = TextEditingController();
  TransactionType type = TransactionType.expense;
  DateTime date = DateTime.now();
  String? linkedGoalId;

  final financialGoals = ref.read(activeGoalsProvider).where((g) => g.targetAmount != null).toList();

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
                  ButtonSegment(value: TransactionType.expense, label: Text('지출')),
                  ButtonSegment(value: TransactionType.income, label: Text('수입')),
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
              TextField(controller: memoController, decoration: const InputDecoration(labelText: '메모 (선택)')),
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
                    firstDate: DateTime.now().subtract(const Duration(days: 365)),
                    lastDate: DateTime.now(),
                  );
                  if (picked != null) setState(() => date = picked);
                },
              ),
              if (financialGoals.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.sm),
                DropdownButtonFormField<String?>(
                  initialValue: linkedGoalId,
                  decoration: const InputDecoration(labelText: '저축 목표에 연결 (선택)'),
                  items: [
                    const DropdownMenuItem<String?>(value: null, child: Text('연결 안 함')),
                    ...financialGoals.map((g) => DropdownMenuItem<String?>(value: g.id, child: Text(g.title))),
                  ],
                  onChanged: (v) => setState(() => linkedGoalId = v),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('취소')),
          FilledButton(
            onPressed: () async {
              final amount = double.tryParse(amountController.text);
              if (amount == null || amount <= 0 || categoryController.text.trim().isEmpty) return;
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
              await ref.read(transactionsProvider.notifier).addTransaction(tx);
              if (dialogContext.mounted) Navigator.pop(dialogContext);
            },
            child: const Text('추가'),
          ),
        ],
      ),
    ),
  );
}
