import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/financial_plan.dart';
import '../providers/financial_planning_provider.dart';
import '../services/financial_planning_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../utils/formatters.dart';

/// A multi-step wizard for long-term financial planning (retirement / home
/// purchase). Uses Flutter's Stepper — the one screen in this app with a
/// genuinely sequential, step-gated flow, unlike the scrolling-list style
/// used elsewhere.
class FinancialPlanningWizardScreen extends ConsumerStatefulWidget {
  const FinancialPlanningWizardScreen({super.key});

  @override
  ConsumerState<FinancialPlanningWizardScreen> createState() => _FinancialPlanningWizardScreenState();
}

class _FinancialPlanningWizardScreenState extends ConsumerState<FinancialPlanningWizardScreen> {
  int _currentStep = 0;
  bool _calculated = false;

  bool _retirementEnabled = false;
  bool _homePurchaseEnabled = false;

  final _currentAgeController = TextEditingController();
  final _retirementAgeController = TextEditingController();
  final _monthlyLivingCostController = TextEditingController();
  final _retirementSavingsController = TextEditingController(text: '0');

  DateTime? _homeTargetDate;
  final _homeTargetAmountController = TextEditingController();
  final _homeSavedController = TextEditingController(text: '0');

  final _returnRateController = TextEditingController(text: '0');

  @override
  void initState() {
    super.initState();
    final plan = ref.read(financialPlanProvider);
    _retirementEnabled = plan.retirementEnabled;
    _homePurchaseEnabled = plan.homePurchaseEnabled;
    if (plan.currentAge != null) _currentAgeController.text = plan.currentAge.toString();
    if (plan.retirementAge != null) _retirementAgeController.text = plan.retirementAge.toString();
    if (plan.monthlyLivingCostAfterRetirement != null) {
      _monthlyLivingCostController.text = plan.monthlyLivingCostAfterRetirement!.toInt().toString();
    }
    _retirementSavingsController.text = plan.retirementCurrentSavings.toInt().toString();
    _homeTargetDate = plan.homePurchaseTargetDate;
    if (plan.homePurchaseTargetAmount != null) {
      _homeTargetAmountController.text = plan.homePurchaseTargetAmount!.toInt().toString();
    }
    _homeSavedController.text = plan.homePurchaseCurrentSaved.toInt().toString();
    _returnRateController.text = plan.expectedAnnualReturnPercent.toString();
  }

  @override
  void dispose() {
    _currentAgeController.dispose();
    _retirementAgeController.dispose();
    _monthlyLivingCostController.dispose();
    _retirementSavingsController.dispose();
    _homeTargetAmountController.dispose();
    _homeSavedController.dispose();
    _returnRateController.dispose();
    super.dispose();
  }

  double? _parseDouble(String text) => double.tryParse(text.trim());
  int? _parseInt(String text) => int.tryParse(text.trim());

  Future<void> _calculate() async {
    // 마법사는 은퇴·주택 필드만 다루므로, 같은 FinancialPlan 레코드에 사는
    // 예산(monthlyBudget/categoryBudgets)은 기존 값을 그대로 이어받아야
    // 저장 시 사용자가 재무 탭에서 설정한 예산이 지워지지 않는다.
    final existing = ref.read(financialPlanProvider);
    final plan = FinancialPlan(
      updatedAt: DateTime.now(),
      expectedAnnualReturnPercent: _parseDouble(_returnRateController.text) ?? 0,
      retirementEnabled: _retirementEnabled,
      currentAge: _retirementEnabled ? _parseInt(_currentAgeController.text) : null,
      retirementAge: _retirementEnabled ? _parseInt(_retirementAgeController.text) : null,
      monthlyLivingCostAfterRetirement: _retirementEnabled ? _parseDouble(_monthlyLivingCostController.text) : null,
      retirementCurrentSavings: _parseDouble(_retirementSavingsController.text) ?? 0,
      homePurchaseEnabled: _homePurchaseEnabled,
      homePurchaseTargetDate: _homePurchaseEnabled ? _homeTargetDate : null,
      homePurchaseTargetAmount: _homePurchaseEnabled ? _parseDouble(_homeTargetAmountController.text) : null,
      homePurchaseCurrentSaved: _parseDouble(_homeSavedController.text) ?? 0,
      monthlyBudget: existing.monthlyBudget,
      categoryBudgets: Map.of(existing.categoryBudgets),
    );
    await ref.read(financialPlanProvider.notifier).savePlan(plan);
    setState(() => _calculated = true);
  }

  List<Step> _buildSteps() {
    final steps = <Step>[
      Step(
        title: const Text('목표 선택'),
        isActive: _currentStep >= 0,
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CheckboxListTile(
              title: const Text('은퇴 준비'),
              value: _retirementEnabled,
              onChanged: (v) => setState(() {
                _retirementEnabled = v ?? false;
                _calculated = false;
              }),
              contentPadding: EdgeInsets.zero,
            ),
            CheckboxListTile(
              title: const Text('주택 구입'),
              value: _homePurchaseEnabled,
              onChanged: (v) => setState(() {
                _homePurchaseEnabled = v ?? false;
                _calculated = false;
              }),
              contentPadding: EdgeInsets.zero,
            ),
          ],
        ),
      ),
    ];

    if (_retirementEnabled) {
      final monthlyLivingCost = _parseDouble(_monthlyLivingCostController.text);
      steps.add(Step(
        title: const Text('은퇴 준비'),
        isActive: _currentStep >= steps.length,
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _currentAgeController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: '현재 나이'),
              onChanged: (_) => setState(() => _calculated = false),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _retirementAgeController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: '목표 은퇴 나이'),
              onChanged: (_) => setState(() => _calculated = false),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _monthlyLivingCostController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: '은퇴 후 월 생활비'),
              onChanged: (_) => setState(() => _calculated = false),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _retirementSavingsController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: '이미 모아둔 은퇴자금 (선택)'),
              onChanged: (_) => setState(() => _calculated = false),
            ),
            if (monthlyLivingCost != null && monthlyLivingCost > 0) ...[
              const SizedBox(height: 8),
              Text(
                '필요 은퇴자금(월 생활비 × 12 × 25 공식): '
                '${formatWon(FinancialPlanningService.requiredRetirementFund(monthlyLivingCost))}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ],
        ),
      ));
    }

    if (_homePurchaseEnabled) {
      steps.add(Step(
        title: const Text('주택 구입'),
        isActive: _currentStep >= steps.length,
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('목표 시점'),
              subtitle: Text(_homeTargetDate != null ? _homeTargetDate!.toString().split(' ').first : '설정 안 됨'),
              trailing: const Icon(Icons.calendar_today),
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: DateTime.now().add(const Duration(days: 365)),
                  firstDate: DateTime.now(),
                  lastDate: DateTime.now().add(const Duration(days: 365 * 40)),
                );
                if (picked != null) {
                  setState(() {
                    _homeTargetDate = picked;
                    _calculated = false;
                  });
                }
              },
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _homeTargetAmountController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: '목표 금액'),
              onChanged: (_) => setState(() => _calculated = false),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _homeSavedController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: '이미 마련된 금액 (선택)'),
              onChanged: (_) => setState(() => _calculated = false),
            ),
          ],
        ),
      ));
    }

    steps.add(Step(
      title: const Text('예상 수익률'),
      isActive: _currentStep >= steps.length,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _returnRateController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: '연 예상 수익률 (%)'),
            onChanged: (_) => setState(() => _calculated = false),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            '직접 입력한 가정치로 계산에만 사용돼요. 특정 투자 상품을 추천하지 않아요.',
            style: TextStyle(fontSize: 12, color: context.appColors.textMuted),
          ),
        ],
      ),
    ));

    steps.add(Step(
      title: const Text('결과'),
      isActive: _currentStep >= steps.length,
      content: _calculated
          ? _buildResults()
          : const Text('이전 단계를 채우고 "계산하기"를 눌러주세요.'),
    ));

    return steps;
  }

  Widget _buildResults() {
    final recommendations = ref.watch(planRecommendationsProvider);
    if (recommendations.isEmpty) {
      return const Text('선택한 목표가 없어요. 첫 단계에서 하나 이상 선택해주세요.');
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: recommendations
          .map((rec) => Card(
                margin: const EdgeInsets.symmetric(vertical: 6),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(rec.goalTitle, style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 6),
                      Text('목표 금액: ${formatWon(rec.requiredTargetAmount)}'),
                      Text('필요 월 저축액: ${formatWon(rec.requiredMonthlySaving)}'),
                      Text('최근 평균 월 저축액: ${formatWon(rec.currentAverageMonthlySaving)}'),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(
                            rec.isOnTrack ? Icons.check_circle : Icons.warning_amber,
                            color: rec.isOnTrack ? context.appColors.success : context.appColors.warning,
                            size: AppIconSize.md,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              rec.isOnTrack
                                  ? '현재 페이스로 충분해요'
                                  : '월 ${formatWon(rec.requiredMonthlySaving - rec.currentAverageMonthlySaving)} 더 모아야 해요',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerRight,
                        child: FilledButton(
                          onPressed: () async {
                            await ref.read(financialPlanProvider.notifier).createGoalFrom(rec);
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('"${rec.goalTitle}" 목표가 생성되었어요.')),
                            );
                          },
                          child: const Text('재무 목표로 만들기'),
                        ),
                      ),
                    ],
                  ),
                ),
              ))
          .toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final steps = _buildSteps();
    final isLastStep = _currentStep == steps.length - 1;

    return Scaffold(
      appBar: AppBar(title: const Text('장기 재무계획')),
      body: Stepper(
        currentStep: _currentStep,
        steps: steps,
        onStepContinue: () async {
          if (isLastStep) {
            await _calculate();
          } else {
            setState(() => _currentStep += 1);
          }
        },
        onStepCancel: _currentStep == 0 ? null : () => setState(() => _currentStep -= 1),
        controlsBuilder: (context, details) {
          return Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              children: [
                FilledButton(
                  onPressed: details.onStepContinue,
                  child: Text(isLastStep ? '계산하기' : '다음'),
                ),
                if (_currentStep > 0) ...[
                  const SizedBox(width: 8),
                  TextButton(onPressed: details.onStepCancel, child: const Text('이전')),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}
