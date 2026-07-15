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

  /// 추천 카테고리 예산을 만들 때 무시할 월 평균 지출 하한 — 이보다 작으면
  /// 굳이 예산 항목으로 관리할 가치가 없다.
  static const suggestionFloor = 10000.0;

  /// 카테고리별 월 평균 지출([averages])로부터 예산 추천안을 만든다.
  /// 이미 예산이 있는 카테고리([alreadyBudgeted])와 [suggestionFloor] 미만은
  /// 제외하고, 평균에 약간의 여유를 둔 뒤 1만원 단위로 올림한다 — 평균에
  /// 딱 맞추면 첫 달부터 초과가 뜨기 쉽다.
  static Map<String, double> suggestCategoryBudgets({
    required Map<String, double> averages,
    required Set<String> alreadyBudgeted,
    double headroom = 1.1,
  }) {
    final result = <String, double>{};
    for (final e in averages.entries) {
      if (alreadyBudgeted.contains(e.key) || e.value < suggestionFloor) continue;
      // 정수 원 단위로 먼저 반올림해 부동소수 오차(예: 400000*1.1=440000.0000006)를
      // 없앤 뒤 1만원 단위로 올림한다.
      final withHeadroom = (e.value * headroom).round();
      result[e.key] = ((withHeadroom + 9999) ~/ 10000) * 10000.0;
    }
    return result;
  }
}
