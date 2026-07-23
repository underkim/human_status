import 'package:flutter/material.dart';

/// 총 예산 입력 다이얼로그. 컨트롤러를 State가 소유·정리한다.
/// 반환: null=취소 / 0=예산 삭제 / 양수=설정.
class BudgetAmountDialog extends StatefulWidget {
  final double? initial;

  const BudgetAmountDialog({super.key, required this.initial});

  @override
  State<BudgetAmountDialog> createState() => _BudgetAmountDialogState();
}

class _BudgetAmountDialogState extends State<BudgetAmountDialog> {
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
