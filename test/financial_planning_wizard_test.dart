import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:human_status/models/financial_plan.dart';
import 'package:human_status/screens/financial_planning_wizard_screen.dart';

import 'helpers/test_app.dart';

void main() {
  testWidgets('마법사에서 계산하기를 눌러도 재무 탭에서 설정한 예산은 보존된다', (tester) async {
    setScreenSize(tester, const Size(800, 2000));
    final storage = await createTestStorage();
    // 사용자가 재무 탭에서 이미 예산을 설정해 둔 상태.
    await storage.saveFinancialPlan(FinancialPlan(
      updatedAt: DateTime(2026, 7, 1),
      monthlyBudget: 1500000,
      categoryBudgets: {'식비': 400000, '교통': 100000},
    ));

    await pumpApp(tester, storage, const FinancialPlanningWizardScreen());

    // 목표를 아무것도 고르지 않고 스텝을 넘어가 계산까지 진행:
    // [목표 선택] → 다음 → [예상 수익률] → 다음 → [결과] → 계산하기.
    // 세로 Stepper는 모든 스텝의 컨트롤을 트리에 두지만 현재 스텝 것만
    // 화면에 보이므로 hitTestable로 실제 눌리는 버튼만 고른다.
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
}
