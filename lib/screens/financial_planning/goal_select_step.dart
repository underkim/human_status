import 'package:flutter/material.dart';

import '../../theme/app_spacing.dart';

/// 마법사 1단계 — 은퇴/주택 구입 목표를 체크박스로 켜고 끈다.
class GoalSelectStep extends StatelessWidget {
  final bool retirementEnabled;
  final bool homePurchaseEnabled;
  final ValueChanged<bool> onRetirementChanged;
  final ValueChanged<bool> onHomePurchaseChanged;

  const GoalSelectStep({
    super.key,
    required this.retirementEnabled,
    required this.homePurchaseEnabled,
    required this.onRetirementChanged,
    required this.onHomePurchaseChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '계획하고 싶은 목표를 선택하세요. 두 목표를 함께 계산할 수도 있어요.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: AppSpacing.md),
        Card(
          child: CheckboxListTile(
            secondary: const Icon(Icons.beach_access_outlined),
            title: const Text('은퇴 준비'),
            subtitle: const Text('은퇴 시점과 필요한 생활비를 기준으로 계산해요.'),
            value: retirementEnabled,
            onChanged: (v) => onRetirementChanged(v ?? false),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Card(
          child: CheckboxListTile(
            secondary: const Icon(Icons.home_work_outlined),
            title: const Text('주택 구입'),
            subtitle: const Text('목표 시점과 마련할 금액을 기준으로 계산해요.'),
            value: homePurchaseEnabled,
            onChanged: (v) => onHomePurchaseChanged(v ?? false),
          ),
        ),
      ],
    );
  }
}
