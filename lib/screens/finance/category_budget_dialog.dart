import 'package:flutter/material.dart';

import '../../theme/app_spacing.dart';

/// 카테고리 예산 다이얼로그. [category]가 null이면 추가 모드(카테고리 입력),
/// 아니면 수정 모드. 반환: null=취소 / (cat,0)=삭제 / (cat,양수)=저장.
class CategoryBudgetDialog extends StatefulWidget {
  final String? category;
  final double? initialAmount;

  const CategoryBudgetDialog({
    super.key,
    required this.category,
    required this.initialAmount,
  });

  @override
  State<CategoryBudgetDialog> createState() => _CategoryBudgetDialogState();
}

class _CategoryBudgetDialogState extends State<CategoryBudgetDialog> {
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
