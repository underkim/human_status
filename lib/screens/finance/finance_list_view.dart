import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../models/transaction.dart';
import '../../providers/finance_provider.dart';
import '../../providers/goal_provider.dart';
import '../../services/finance_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../utils/formatters.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/goal_progress_card.dart';
import '../../widgets/transaction_tile.dart';
import '../banksalad_import_screen.dart';
import 'budget_card.dart';
import 'category_breakdown_card.dart';
import 'finance_coaching_card.dart';
import 'monthly_expense_chart_card.dart';

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
        const CoachingCard(),
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
                    SummaryStat(
                      label: '수입',
                      value: summary.income,
                      color: colors.success,
                    ),
                    SummaryStat(
                      label: '지출',
                      value: summary.expense,
                      color: colors.error,
                    ),
                    SummaryStat(
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
        BudgetCard(
          spentThisMonth: summary.expense,
          spentByCategory: byCategory,
          categoryAverages: FinanceService.averageMonthlyExpenseByCategory(
            transactions,
          ),
        ),
        if (monthlyExpenses.values.any((v) => v > 0)) ...[
          const SizedBox(height: AppSpacing.lg),
          MonthlyExpenseChartCard(monthlyExpenses: monthlyExpenses),
        ],
        if (byCategory.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.lg),
          CategoryBreakdownCard(
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
