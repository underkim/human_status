import 'package:flutter/material.dart';

import '../models/transaction.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import '../utils/formatters.dart';

/// Shared row for a single transaction — used by both the 거래내역 list and
/// the 뱅크샐러드 가져오기 preview list, which previously each hand-rolled a
/// near-identical icon+category+amount tile.
class TransactionTile extends StatelessWidget {
  final Transaction transaction;
  final bool dense;
  final Widget? trailing;

  const TransactionTile({
    super.key,
    required this.transaction,
    this.dense = false,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final isExpense = transaction.type == TransactionType.expense;
    final dateLabel = transaction.date.toString().split(' ').first;
    final amountText = '${isExpense ? '-' : '+'}${formatWon(transaction.amount)}';

    return Card(
      margin: EdgeInsets.symmetric(vertical: dense ? 3 : AppSpacing.xs),
      child: ListTile(
        dense: dense,
        leading: Icon(
          isExpense ? Icons.arrow_downward : Icons.arrow_upward,
          color: isExpense ? colors.error : colors.success,
        ),
        title: Text(
          dense ? '${transaction.category} · $dateLabel' : transaction.category,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: transaction.memo.isNotEmpty
            ? Text(transaction.memo, maxLines: 1, overflow: TextOverflow.ellipsis)
            : (dense ? null : Text(dateLabel)),
        trailing: trailing != null
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(amountText, style: AppTypography.dataSmall(color: isExpense ? colors.error : colors.success)),
                  trailing!,
                ],
              )
            : Text(amountText, style: AppTypography.dataMedium(color: isExpense ? colors.error : colors.success)),
      ),
    );
  }
}
