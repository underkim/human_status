import 'package:flutter_test/flutter_test.dart';
import 'package:human_status/services/budget_service.dart';

void main() {
  group('BudgetService.status', () {
    test('예산이 없거나 0 이하이면 none', () {
      expect(BudgetService.status(budget: null, spent: 100), BudgetStatus.none);
      expect(BudgetService.status(budget: 0, spent: 100), BudgetStatus.none);
      expect(BudgetService.status(budget: -1, spent: 100), BudgetStatus.none);
    });

    test('90% 미만이면 ok', () {
      expect(BudgetService.status(budget: 100000, spent: 0), BudgetStatus.ok);
      expect(BudgetService.status(budget: 100000, spent: 89999), BudgetStatus.ok);
    });

    test('90% 이상 100% 이하이면 warning', () {
      expect(BudgetService.status(budget: 100000, spent: 90000), BudgetStatus.warning);
      expect(BudgetService.status(budget: 100000, spent: 100000), BudgetStatus.warning);
    });

    test('예산을 넘으면 exceeded', () {
      expect(BudgetService.status(budget: 100000, spent: 100001), BudgetStatus.exceeded);
    });
  });

  group('BudgetService.justExceeded', () {
    test('예산 안 → 초과로 넘어가는 순간만 true', () {
      expect(
        BudgetService.justExceeded(budget: 100000, spentBefore: 95000, spentAfter: 105000),
        isTrue,
      );
    });

    test('이미 초과 상태에서의 추가 지출은 false', () {
      expect(
        BudgetService.justExceeded(budget: 100000, spentBefore: 105000, spentAfter: 110000),
        isFalse,
      );
    });

    test('예산 안에 머무르면 false, 예산 미설정이면 항상 false', () {
      expect(
        BudgetService.justExceeded(budget: 100000, spentBefore: 10000, spentAfter: 50000),
        isFalse,
      );
      expect(
        BudgetService.justExceeded(budget: null, spentBefore: 0, spentAfter: 999999),
        isFalse,
      );
    });
  });

  group('BudgetService.suggestCategoryBudgets', () {
    test('평균에 10% 여유를 두고 1만원 단위로 올림한다', () {
      final result = BudgetService.suggestCategoryBudgets(
        averages: {'식비': 400000, '교통': 55000},
        alreadyBudgeted: {},
      );
      // 400000*1.1=440000 → 440000, 55000*1.1=60500 → 70000(올림).
      expect(result, {'식비': 440000, '교통': 70000});
    });

    test('이미 예산이 있는 카테고리와 하한 미만은 제외한다', () {
      final result = BudgetService.suggestCategoryBudgets(
        averages: {'식비': 400000, '교통': 55000, '군것질': 5000},
        alreadyBudgeted: {'식비'},
      );
      // 식비=이미 있음, 군것질=1만원 미만 → 교통만 남는다.
      expect(result.keys, ['교통']);
    });

    test('추천할 게 없으면 빈 맵', () {
      expect(
        BudgetService.suggestCategoryBudgets(averages: {'군것질': 3000}, alreadyBudgeted: {}),
        isEmpty,
      );
    });
  });
}
