import 'package:flutter/material.dart';

/// 마법사의 "주택 구입" 단계 — 목표 시점/목표 금액/기존 저축액을 입력한다.
class HomePurchaseStep extends StatelessWidget {
  final DateTime? homeTargetDate;
  final TextEditingController homeTargetAmountController;
  final TextEditingController homeSavedController;
  final bool isValid;
  final Future<void> Function(BuildContext context) onPickDate;
  final VoidCallback onFieldChanged;

  const HomePurchaseStep({
    super.key,
    required this.homeTargetDate,
    required this.homeTargetAmountController,
    required this.homeSavedController,
    required this.isValid,
    required this.onPickDate,
    required this.onFieldChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('목표 시점'),
          subtitle: Text(
            homeTargetDate != null
                ? homeTargetDate!.toString().split(' ').first
                : '설정 안 됨',
          ),
          trailing: const Icon(Icons.calendar_today),
          onTap: () => onPickDate(context),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: homeTargetAmountController,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: '목표 금액'),
          onChanged: (_) => onFieldChanged(),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: homeSavedController,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: '이미 마련된 금액 (선택)'),
          onChanged: (_) => onFieldChanged(),
        ),
        if (!isValid) ...[
          const SizedBox(height: 8),
          Text(
            '목표 시점과 0보다 큰 목표 금액을 모두 입력해야 다음으로 넘어갈 수 있어요.',
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
