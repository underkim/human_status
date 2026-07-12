import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../models/transaction.dart';
import '../providers/finance_provider.dart';
import '../providers/goal_provider.dart';
import '../services/finance_service.dart';
import 'transaction_import_screen.dart';

class FinanceListView extends ConsumerWidget {
  const FinanceListView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final monthKey = monthKeyOf(DateTime.now());
    final summary = ref.watch(monthlySummaryProvider(monthKey));
    final transactions = [...ref.watch(transactionsProvider)]..sort((a, b) => b.date.compareTo(a.date));
    final financialGoals = ref.watch(activeGoalsProvider).where((g) => g.targetAmount != null).toList();
    final progress = ref.watch(goalProgressMapProvider);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('이번 달', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _SummaryStat(label: '수입', value: summary.income, color: Colors.green),
                    _SummaryStat(label: '지출', value: summary.expense, color: Colors.red),
                    _SummaryStat(label: '순저축', value: summary.net, color: Theme.of(context).colorScheme.primary),
                  ],
                ),
              ],
            ),
          ),
        ),
        if (financialGoals.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('재무 목표', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          ...financialGoals.map((g) => Card(
                margin: const EdgeInsets.symmetric(vertical: 4),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(g.title, style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: LinearProgressIndicator(value: progress[g.id] ?? 0, minHeight: 8),
                      ),
                      const SizedBox(height: 4),
                      Text('${g.currentAmount.toInt()} / ${g.targetAmount!.toInt()}'),
                    ],
                  ),
                ),
              )),
        ],
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('거래 내역', style: Theme.of(context).textTheme.titleLarge),
            Row(
              children: [
                Text('${transactions.length}건'),
                TextButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const TransactionImportScreen()),
                  ),
                  icon: const Icon(Icons.upload_file, size: 18),
                  label: const Text('CSV 가져오기'),
                ),
              ],
            ),
          ],
        ),
        if (transactions.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text('아직 기록된 거래가 없어요.'),
          )
        else
          ...transactions.map((t) => _TransactionTile(transaction: t)),
      ],
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
        Text(
          value.toInt().toString(),
          style: Theme.of(context).textTheme.titleMedium?.copyWith(color: color, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }
}

class _TransactionTile extends ConsumerWidget {
  final Transaction transaction;

  const _TransactionTile({required this.transaction});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isExpense = transaction.type == TransactionType.expense;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        leading: Icon(
          isExpense ? Icons.arrow_downward : Icons.arrow_upward,
          color: isExpense ? Colors.red : Colors.green,
        ),
        title: Text(transaction.category),
        subtitle: Text(
          transaction.memo.isNotEmpty ? transaction.memo : transaction.date.toString().split(' ').first,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('${isExpense ? '-' : '+'}${transaction.amount.toInt()}'),
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 20),
              onPressed: () => ref.read(transactionsProvider.notifier).deleteTransaction(transaction.id),
            ),
          ],
        ),
      ),
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
              const SizedBox(height: 12),
              TextField(controller: categoryController, decoration: const InputDecoration(labelText: '카테고리')),
              const SizedBox(height: 8),
              TextField(controller: memoController, decoration: const InputDecoration(labelText: '메모 (선택)')),
              const SizedBox(height: 8),
              TextField(
                controller: amountController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: '금액'),
              ),
              const SizedBox(height: 8),
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
                const SizedBox(height: 8),
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
