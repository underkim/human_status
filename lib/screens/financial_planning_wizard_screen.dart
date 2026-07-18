import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/financial_plan.dart';
import '../providers/financial_planning_provider.dart';
import '../services/financial_planning_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../utils/formatters.dart';
import '../widgets/page_content_bounds.dart';

/// Identifies what a built [Step] actually asks for, in the same order
/// [_FinancialPlanningWizardScreenState._buildSteps] assembles them —
/// lets step-continue gating validate only the fields relevant to the
/// step the user is actually on, since retirement/home steps are only
/// present when their goal is enabled and shift position accordingly.
enum _WizardStepKind { goalSelect, retirement, home, returnRate, result }

/// A multi-step wizard for long-term financial planning (retirement / home
/// purchase). Uses Flutter's Stepper — the one screen in this app with a
/// genuinely sequential, step-gated flow, unlike the scrolling-list style
/// used elsewhere.
class FinancialPlanningWizardScreen extends ConsumerStatefulWidget {
  const FinancialPlanningWizardScreen({super.key});

  @override
  ConsumerState<FinancialPlanningWizardScreen> createState() =>
      _FinancialPlanningWizardScreenState();
}

class _FinancialPlanningWizardScreenState
    extends ConsumerState<FinancialPlanningWizardScreen> {
  int _currentStep = 0;
  bool _calculated = false;
  bool _isSaving = false;
  Set<String> _creatingGoalTitles = {};

  bool _retirementEnabled = false;
  bool _homePurchaseEnabled = false;

  /// Populated as a side effect of [_buildSteps] — parallel to the steps
  /// list it just built, so step-continue gating below can tell which
  /// kind of step [_currentStep] currently points at.
  List<_WizardStepKind> _stepKinds = const [];

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
    if (plan.currentAge != null) {
      _currentAgeController.text = plan.currentAge.toString();
    }
    if (plan.retirementAge != null) {
      _retirementAgeController.text = plan.retirementAge.toString();
    }
    if (plan.monthlyLivingCostAfterRetirement != null) {
      _monthlyLivingCostController.text = plan.monthlyLivingCostAfterRetirement!
          .toInt()
          .toString();
    }
    _retirementSavingsController.text = plan.retirementCurrentSavings
        .toInt()
        .toString();
    _homeTargetDate = plan.homePurchaseTargetDate;
    if (plan.homePurchaseTargetAmount != null) {
      _homeTargetAmountController.text = plan.homePurchaseTargetAmount!
          .toInt()
          .toString();
    }
    _homeSavedController.text = plan.homePurchaseCurrentSaved
        .toInt()
        .toString();
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

  // `double.tryParse` accepts the literal strings "NaN"/"Infinity" and
  // "-Infinity", so a plain text field lets a user type those directly into
  // a money/age input. Rejecting non-finite results here (treating them the
  // same as "couldn't parse") stops that value from ever reaching the
  // calculation — where it would otherwise surface as a crash when
  // formatWon() tries to round() a NaN/Infinity amount.
  double? _parseDouble(String text) {
    final value = double.tryParse(text.trim());
    if (value == null || !value.isFinite) return null;
    return value;
  }

  int? _parseInt(String text) => int.tryParse(text.trim());

  bool _isRetirementStepValid() {
    final age = _parseInt(_currentAgeController.text);
    final retirementAge = _parseInt(_retirementAgeController.text);
    final livingCost = _parseDouble(_monthlyLivingCostController.text);
    return age != null &&
        age > 0 &&
        age < 120 &&
        retirementAge != null &&
        retirementAge > age &&
        retirementAge <= 120 &&
        livingCost != null &&
        livingCost > 0;
  }

  bool _isHomeStepValid() {
    final targetAmount = _parseDouble(_homeTargetAmountController.text);
    return _homeTargetDate != null && targetAmount != null && targetAmount > 0;
  }

  /// Whether the user may advance past step [index] (its position in the
  /// most recently built steps list). Only the retirement/home steps gate
  /// progress — the goal-selection, return-rate, and result steps have no
  /// required fields (the return-rate field always carries a valid default).
  bool _canContinueFrom(int index) {
    if (index < 0 || index >= _stepKinds.length) return true;
    switch (_stepKinds[index]) {
      case _WizardStepKind.retirement:
        return _isRetirementStepValid();
      case _WizardStepKind.home:
        return _isHomeStepValid();
      case _WizardStepKind.goalSelect:
        return _retirementEnabled || _homePurchaseEnabled;
      case _WizardStepKind.returnRate:
      case _WizardStepKind.result:
        return true;
    }
  }

  Future<void> _calculate() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);
    try {
      // 마법사는 은퇴·주택 필드만 다루므로, 같은 FinancialPlan 레코드에 사는
      // 예산(monthlyBudget/categoryBudgets)은 기존 값을 그대로 이어받아야
      // 저장 시 사용자가 재무 탭에서 설정한 예산이 지워지지 않는다.
      final existing = ref.read(financialPlanProvider);
      final plan = FinancialPlan(
        updatedAt: DateTime.now(),
        expectedAnnualReturnPercent:
            _parseDouble(_returnRateController.text) ?? 0,
        retirementEnabled: _retirementEnabled,
        currentAge: _retirementEnabled
            ? _parseInt(_currentAgeController.text)
            : null,
        retirementAge: _retirementEnabled
            ? _parseInt(_retirementAgeController.text)
            : null,
        monthlyLivingCostAfterRetirement: _retirementEnabled
            ? _parseDouble(_monthlyLivingCostController.text)
            : null,
        retirementCurrentSavings:
            _parseDouble(_retirementSavingsController.text) ?? 0,
        homePurchaseEnabled: _homePurchaseEnabled,
        homePurchaseTargetDate: _homePurchaseEnabled ? _homeTargetDate : null,
        homePurchaseTargetAmount: _homePurchaseEnabled
            ? _parseDouble(_homeTargetAmountController.text)
            : null,
        homePurchaseCurrentSaved: _parseDouble(_homeSavedController.text) ?? 0,
        monthlyBudget: existing.monthlyBudget,
        categoryBudgets: Map.of(existing.categoryBudgets),
      );
      await ref.read(financialPlanProvider.notifier).savePlan(plan);
      if (!mounted) return;
      setState(() => _calculated = true);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('계산 결과를 저장하지 못했어요. 잠시 후 다시 시도해주세요.')),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  List<Step> _buildSteps() {
    final kinds = <_WizardStepKind>[_WizardStepKind.goalSelect];
    final steps = <Step>[
      Step(
        title: const Text('목표 선택'),
        isActive: _currentStep >= 0,
        content: Column(
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
                value: _retirementEnabled,
                onChanged: (v) => setState(() {
                  _retirementEnabled = v ?? false;
                  _calculated = false;
                }),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Card(
              child: CheckboxListTile(
                secondary: const Icon(Icons.home_work_outlined),
                title: const Text('주택 구입'),
                subtitle: const Text('목표 시점과 마련할 금액을 기준으로 계산해요.'),
                value: _homePurchaseEnabled,
                onChanged: (v) => setState(() {
                  _homePurchaseEnabled = v ?? false;
                  _calculated = false;
                }),
              ),
            ),
          ],
        ),
      ),
    ];

    if (_retirementEnabled) {
      final monthlyLivingCost = _parseDouble(_monthlyLivingCostController.text);
      kinds.add(_WizardStepKind.retirement);
      steps.add(
        Step(
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
                decoration: const InputDecoration(
                  labelText: '이미 모아둔 은퇴자금 (선택)',
                ),
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
              if (!_isRetirementStepValid()) ...[
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
          ),
        ),
      );
    }

    if (_homePurchaseEnabled) {
      kinds.add(_WizardStepKind.home);
      steps.add(
        Step(
          title: const Text('주택 구입'),
          isActive: _currentStep >= steps.length,
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('목표 시점'),
                subtitle: Text(
                  _homeTargetDate != null
                      ? _homeTargetDate!.toString().split(' ').first
                      : '설정 안 됨',
                ),
                trailing: const Icon(Icons.calendar_today),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: DateTime.now().add(const Duration(days: 365)),
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(
                      const Duration(days: 365 * 40),
                    ),
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
              if (!_isHomeStepValid()) ...[
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
          ),
        ),
      );
    }

    kinds.add(_WizardStepKind.returnRate);
    steps.add(
      Step(
        title: const Text('예상 수익률'),
        isActive: _currentStep >= steps.length,
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _returnRateController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(labelText: '연 예상 수익률 (%)'),
              onChanged: (_) => setState(() => _calculated = false),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              '직접 입력한 가정치로 계산에만 사용돼요. 특정 투자 상품을 추천하지 않아요.',
              style: TextStyle(
                fontSize: 12,
                color: context.appColors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );

    kinds.add(_WizardStepKind.result);
    steps.add(
      Step(
        title: const Text('결과'),
        isActive: _currentStep >= steps.length,
        content: _calculated
            ? _buildResults()
            : const Text('이전 단계를 채우고 "계산하기"를 눌러주세요.'),
      ),
    );

    _stepKinds = kinds;
    return steps;
  }

  Widget _buildResults() {
    final recommendations = ref.watch(planRecommendationsProvider);
    if (recommendations.isEmpty) {
      final message = (_retirementEnabled || _homePurchaseEnabled)
          ? '입력한 값으로는 계산할 수 없어요. 이전 단계로 돌아가 필수 항목을 확인해주세요.'
          : '선택한 목표가 없어요. 첫 단계에서 하나 이상 선택해주세요.';
      return Text(message);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: recommendations
          .map(
            (rec) => Card(
              margin: const EdgeInsets.symmetric(vertical: 6),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      rec.goalTitle,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 6),
                    Text('목표 금액: ${formatWon(rec.requiredTargetAmount)}'),
                    Text('필요 월 저축액: ${formatWon(rec.requiredMonthlySaving)}'),
                    Text(
                      '최근 평균 월 저축액: ${formatWon(rec.currentAverageMonthlySaving)}',
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(
                          rec.isOnTrack
                              ? Icons.check_circle
                              : Icons.warning_amber,
                          color: rec.isOnTrack
                              ? context.appColors.success
                              : context.appColors.warning,
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
                        onPressed: _creatingGoalTitles.contains(rec.goalTitle)
                            ? null
                            : () async {
                                setState(
                                  () => _creatingGoalTitles = {
                                    ..._creatingGoalTitles,
                                    rec.goalTitle,
                                  },
                                );
                                try {
                                  await ref
                                      .read(financialPlanProvider.notifier)
                                      .createGoalFrom(rec);
                                  if (!mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        '"${rec.goalTitle}" 목표가 생성되었어요.',
                                      ),
                                    ),
                                  );
                                } catch (_) {
                                  if (!mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        '목표를 생성하지 못했어요. 잠시 후 다시 시도해주세요.',
                                      ),
                                    ),
                                  );
                                } finally {
                                  if (mounted) {
                                    setState(
                                      () => _creatingGoalTitles = {
                                        ..._creatingGoalTitles,
                                      }..remove(rec.goalTitle),
                                    );
                                  }
                                }
                              },
                        child: const Text('재무 목표로 만들기'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          )
          .toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final steps = _buildSteps();
    // Defensive: nothing in the current UI flow can change the step count
    // while _currentStep points anywhere but 0 (the goal checkboxes that
    // drive step count are only reachable from/valid on step 0), but
    // clamping here means a future change to that invariant degrades to
    // showing the last step instead of crashing the Stepper on an
    // out-of-range currentStep.
    if (_currentStep >= steps.length) _currentStep = steps.length - 1;
    if (_currentStep < 0) _currentStep = 0;
    final isLastStep = _currentStep == steps.length - 1;
    final canContinue = _canContinueFrom(_currentStep);

    return Scaffold(
      appBar: AppBar(title: const Text('장기 재무계획')),
      body: PageContentBounds(
        maxWidth: PageContentBounds.narrow,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Card(
              margin: const EdgeInsets.all(AppSpacing.lg),
              child: Stepper(
                // Stepper asserts that currentStep stays within steps.length
                // across a single element's lifetime, but toggling either
                // goal checkbox changes steps.length while currentStep can
                // stay put (e.g. on the shared return-rate/result steps).
                // Keying by the goal flags forces Flutter to tear down and
                // recreate the Stepper element whenever the step count can
                // change, instead of updating one that already progressed.
                key: ValueKey('$_retirementEnabled-$_homePurchaseEnabled'),
                currentStep: _currentStep,
                steps: steps,
                onStepContinue: () async {
                  if (isLastStep) {
                    await _calculate();
                  } else {
                    setState(() => _currentStep += 1);
                  }
                },
                onStepCancel: _currentStep == 0
                    ? null
                    : () => setState(() => _currentStep -= 1),
                controlsBuilder: (context, details) {
                  // Wrap (not Row) so large text-scale/accessibility
                  // settings that widen the button labels move "이전" to a
                  // second line instead of overflowing the card horizontally.
                  return Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        FilledButton(
                          onPressed: _isSaving
                              ? null
                              : (canContinue ? details.onStepContinue : null),
                          child: _isSaving
                              ? const SizedBox(
                                  height: 16,
                                  width: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : Text(isLastStep ? '계산하기' : '다음'),
                        ),
                        if (_currentStep > 0)
                          TextButton(
                            onPressed: _isSaving ? null : details.onStepCancel,
                            child: const Text('이전'),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}
