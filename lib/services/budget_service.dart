/// 월 지출 예산 상태 판정. 90% 이상이면 경고, 100% 초과면 초과.
enum BudgetStatus { none, ok, warning, exceeded }

class BudgetService {
  /// 이 비율 이상 쓰면 초과 전이라도 경고 상태로 보여준다.
  static const warningRatio = 0.9;

  static BudgetStatus status({required double? budget, required double spent}) {
    if (budget == null || budget <= 0) return BudgetStatus.none;
    if (spent > budget) return BudgetStatus.exceeded;
    if (spent >= budget * warningRatio) return BudgetStatus.warning;
    return BudgetStatus.ok;
  }

  /// 이번 기록으로 예산을 '지금 막' 넘어섰는지 — 이미 초과 상태에서 추가로
  /// 쓴 경우는 false라 초과 알림이 거래마다 반복되지 않는다.
  static bool justExceeded({
    required double? budget,
    required double spentBefore,
    required double spentAfter,
  }) {
    if (budget == null || budget <= 0) return false;
    return spentBefore <= budget && spentAfter > budget;
  }
}
