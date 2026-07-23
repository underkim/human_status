import 'package:flutter/material.dart';

import '../../services/financial_planning_service.dart';
import '../../utils/formatters.dart';

/// 마법사의 "은퇴 준비" 단계 — 나이/은퇴 나이/월 생활비/기존 저축액을 입력한다.
class RetirementStep extends StatelessWidget {
  final TextEditingController currentAgeController;
  final TextEditingController retirementAgeController;
  final TextEditingController monthlyLivingCostController;
  final TextEditingController retirementSavingsController;
  final double? monthlyLivingCost;
  final bool isValid;
  final VoidCallback onFieldChanged;

  const RetirementStep({
    super.key,
    required this.currentAgeController,
    required this.retirementAgeController,
    required this.monthlyLivingCostController,
    required this.retirementSavingsController,
    required this.monthlyLivingCost,
    required this.isValid,
    required this.onFieldChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: currentAgeController,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: '현재 나이'),
          onChanged: (_) => onFieldChanged(),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: retirementAgeController,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: '목표 은퇴 나이'),
          onChanged: (_) => onFieldChanged(),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: monthlyLivingCostController,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: '은퇴 후 월 생활비'),
          onChanged: (_) => onFieldChanged(),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: retirementSavingsController,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: '이미 모아둔 은퇴자금 (선택)'),
          onChanged: (_) => onFieldChanged(),
        ),
        if (monthlyLivingCost != null && monthlyLivingCost! > 0) ...[
          const SizedBox(height: 8),
          Text(
            '필요 은퇴자금(월 생활비 × 12 × 25 공식): '
            '${formatWon(FinancialPlanningService.requiredRetirementFund(monthlyLivingCost!))}',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ],
        if (!isValid) ...[
          const SizedBox(height: 8),
          Text(
            '나이(1~119), 현재 나이보다 큰 목표 은퇴 나이, 0보다 큰 월 생활비를 모두 입력해야 다음으로 넘어갈 수 있어요.',
            style: TextStyle(
              color: Theme.of(context).colorScheme.error,
              fontSize: 12,
            ),
          ),
        ],
      ],
    );
  }
}
