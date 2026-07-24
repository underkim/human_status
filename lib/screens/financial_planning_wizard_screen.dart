import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/financial_plan.dart';
import '../providers/financial_planning_provider.dart';
import '../theme/app_spacing.dart';
import '../widgets/page_content_bounds.dart';
import 'financial_planning/goal_select_step.dart';
import 'financial_planning/home_purchase_step.dart';
import 'financial_planning/result_step.dart';
import 'financial_planning/retirement_step.dart';
import 'financial_planning/return_rate_step.dart';

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
        content: GoalSelectStep(
          retirementEnabled: _retirementEnabled,
          homePurchaseEnabled: _homePurchaseEnabled,
          onRetirementChanged: (v) => setState(() {
            _retirementEnabled = v;
            _calculated = false;
          }),
          onHomePurchaseChanged: (v) => setState(() {
            _homePurchaseEnabled = v;
            _calculated = false;
          }),
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
          content: RetirementStep(
            currentAgeController: _currentAgeController,
            retirementAgeController: _retirementAgeController,
            monthlyLivingCostController: _monthlyLivingCostController,
            retirementSavingsController: _retirementSavingsController,
            monthlyLivingCost: monthlyLivingCost,
            isValid: _isRetirementStepValid(),
            onFieldChanged: () => setState(() => _calculated = false),
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
          content: HomePurchaseStep(
            homeTargetDate: _homeTargetDate,
            homeTargetAmountController: _homeTargetAmountController,
            homeSavedController: _homeSavedController,
            isValid: _isHomeStepValid(),
            onFieldChanged: () => setState(() => _calculated = false),
            onPickDate: (context) async {
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
        ),
      );
    }

    kinds.add(_WizardStepKind.returnRate);
    steps.add(
      Step(
        title: const Text('예상 수익률'),
        isActive: _currentStep >= steps.length,
        content: ReturnRateStep(
          returnRateController: _returnRateController,
          onFieldChanged: () => setState(() => _calculated = false),
        ),
      ),
    );

    kinds.add(_WizardStepKind.result);
    steps.add(
      Step(
        title: const Text('결과'),
        isActive: _currentStep >= steps.length,
        content: _calculated
            ? ResultStep(
                retirementEnabled: _retirementEnabled,
                homePurchaseEnabled: _homePurchaseEnabled,
              )
            : const Text('이전 단계를 채우고 "계산하기"를 눌러주세요.'),
      ),
    );

    _stepKinds = kinds;
    return steps;
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
