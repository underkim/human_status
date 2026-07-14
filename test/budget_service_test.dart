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
}
