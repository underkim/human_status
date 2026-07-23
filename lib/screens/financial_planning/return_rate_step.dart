import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';

/// 마법사의 "예상 수익률" 단계.
class ReturnRateStep extends StatelessWidget {
  final TextEditingController returnRateController;
  final VoidCallback onFieldChanged;

  const ReturnRateStep({
    super.key,
    required this.returnRateController,
    required this.onFieldChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: returnRateController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: '연 예상 수익률 (%)'),
          onChanged: (_) => onFieldChanged(),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          '직접 입력한 가정치로 계산에만 사용돼요. 특정 투자 상품을 추천하지 않아요.',
          style: TextStyle(fontSize: 12, color: context.appColors.textMuted),
        ),
      ],
    );
  }
}
