import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:human_status/models/financial_plan.dart';
import 'package:human_status/screens/financial_planning_wizard_screen.dart';

import 'helpers/test_app.dart';

void main() {
  testWidgets('마법사에서 계산하기를 눌러도 재무 탭에서 설정한 예산은 보존된다', (tester) async {
    setScreenSize(tester, const Size(800, 2000));
    final storage = await createTestStorage();
    // 사용자가 재무 탭에서 이미 예산을 설정해 두었고, 은퇴 준비 목표도 이미
    // 유효한 값으로 활성화되어 있는 상태 (은퇴 준비 스텝이 포함된 4단계 마법사).
    await storage.saveFinancialPlan(
      FinancialPlan(
        updatedAt: DateTime(2026, 7, 1),
        monthlyBudget: 1500000,
        categoryBudgets: {'식비': 400000, '교통': 100000},
        retirementEnabled: true,
        currentAge: 30,
        retirementAge: 60,
        monthlyLivingCostAfterRetirement: 2000000,
      ),
    );

    await pumpApp(tester, storage, const FinancialPlanningWizardScreen());

    // 활성화된 목표(은퇴 준비)를 그대로 두고 모든 스텝을 지나 계산까지 진행:
    // [목표 선택] → 다음 → [은퇴 준비] → 다음 → [예상 수익률] → 다음 →
    // [결과] → 계산하기.
    // 세로 Stepper는 모든 스텝의 컨트롤을 트리에 두지만 현재 스텝 것만
    // 화면에 보이므로 hitTestable로 실제 눌리는 버튼만 고른다.
    await tester.tap(find.widgetWithText(FilledButton, '다음').hitTestable());
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '다음').hitTestable());
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '다음').hitTestable());
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '계산하기').hitTestable());
    await tester.pumpAndSettle();

    // 마법사 저장이 예산 필드를 덮어쓰지 않는다.
    final plan = storage.getFinancialPlan();
    expect(plan.monthlyBudget, 1500000);
    expect(plan.categoryBudgets, {'식비': 400000, '교통': 100000});
  });

  testWidgets('목표를 하나도 선택하지 않으면 다음 버튼이 비활성화된다', (tester) async {
    setScreenSize(tester, const Size(800, 2000));
    final storage = await createTestStorage();

    await pumpApp(tester, storage, const FinancialPlanningWizardScreen());

    // 목표 선택 단계에서 아무것도 고르지 않은 초기 상태: 다음으로 못 넘어간다.
    final nextButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '다음').hitTestable(),
    );
    expect(nextButton.onPressed, isNull);

    // Stepper는 스텝 개수가 바뀌는 리빌드를 지원하지 않으므로(체크박스로
    // 목표를 켜면 스텝이 하나 늘어남), 같은 트리에서 토글하는 대신 저장된
    // 계획을 은퇴 준비가 켜진 상태로 바꾸고 트리를 새로 마운트해 확인한다.
    await storage.saveFinancialPlan(
      FinancialPlan(updatedAt: DateTime(2026, 7, 1), retirementEnabled: true),
    );
    await tester.pumpWidget(const SizedBox());
    await pumpApp(tester, storage, const FinancialPlanningWizardScreen());

    final enabledNextButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '다음').hitTestable(),
    );
    expect(enabledNextButton.onPressed, isNotNull);
  });
}
