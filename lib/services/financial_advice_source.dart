/// A single coaching comment surfaced on the finance tab.
class AdviceItem {
  final String category; // 'spending' | 'goal' | 'networth' | 'general'
  final String message;

  const AdviceItem({required this.category, required this.message});

  Map<String, dynamic> toJson() => {'category': category, 'message': message};

  factory AdviceItem.fromJson(Map<String, dynamic> json) => AdviceItem(
        category: json['category'] as String,
        message: json['message'] as String,
      );
}

/// A single active, dated financial goal's progress, prepared for coaching.
class GoalProgressSummary {
  final String title;
  final double actualProgress; // 0..1
  // Fraction of the goal's total duration (createdAt -> targetDate) elapsed.
  // Null when there's no meaningful duration to pace against.
  final double? expectedProgress;

  const GoalProgressSummary({
    required this.title,
    required this.actualProgress,
    this.expectedProgress,
  });
}

/// Summarized inputs for generating financial advice. Deliberately holds
/// only aggregated numbers (category totals, progress ratios) rather than
/// raw transactions, so a Claude-backed source never needs the user's full
/// transaction history to do its job.
class FinancialAdviceContext {
  final Map<String, double> currentMonthExpenseByCategory;
  final Map<String, double> previousMonthExpenseByCategory;
  final List<GoalProgressSummary> goalProgress;
  final double? netWorthChange;
  final double? netWorthChangePercent;

  const FinancialAdviceContext({
    required this.currentMonthExpenseByCategory,
    required this.previousMonthExpenseByCategory,
    required this.goalProgress,
    this.netWorthChange,
    this.netWorthChangePercent,
  });
}

/// Pluggable source of financial coaching comments. An AI-backed
/// implementation (see ClaudeFinancialAdviceSource) can be swapped in
/// without touching any calling code, mirroring QuestSuggestionSource.
abstract class FinancialAdviceSource {
  Future<List<AdviceItem>> generateAdvice(FinancialAdviceContext context);
}

/// Rule-based coaching that needs no network access. Deliberately limited to
/// general budgeting/saving commentary — never specific investment or
/// product buy/sell recommendations.
class LocalRuleFinancialAdviceSource implements FinancialAdviceSource {
  static const _spendingChangeThresholdPercent = 30.0;
  static const _goalPaceBehindMargin = 0.1;

  @override
  Future<List<AdviceItem>> generateAdvice(FinancialAdviceContext context) async {
    final items = <AdviceItem>[];

    context.currentMonthExpenseByCategory.forEach((category, current) {
      final previous = context.previousMonthExpenseByCategory[category] ?? 0;
      if (previous <= 0) return;
      final changePercent = (current - previous) / previous * 100;
      if (changePercent >= _spendingChangeThresholdPercent) {
        items.add(AdviceItem(
          category: 'spending',
          message: '$category 지출이 지난달보다 ${changePercent.round()}% 늘었어요.',
        ));
      } else if (changePercent <= -_spendingChangeThresholdPercent) {
        items.add(AdviceItem(
          category: 'spending',
          message: '$category 지출을 지난달보다 ${changePercent.abs().round()}% 줄였어요, 잘하고 있어요!',
        ));
      }
    });

    for (final goal in context.goalProgress) {
      final expected = goal.expectedProgress;
      if (expected == null) continue;
      if (goal.actualProgress + _goalPaceBehindMargin < expected) {
        items.add(AdviceItem(
          category: 'goal',
          message: '"${goal.title}" 목표 저축 속도가 예상보다 느려요. 페이스를 조금 올려보세요.',
        ));
      } else if (goal.actualProgress >= expected) {
        items.add(AdviceItem(
          category: 'goal',
          message: '"${goal.title}" 목표를 계획대로 잘 따라가고 있어요.',
        ));
      }
    }

    final changePercent = context.netWorthChangePercent;
    if (changePercent != null) {
      final direction = changePercent >= 0 ? '늘었어요' : '줄었어요';
      items.add(AdviceItem(
        category: 'networth',
        message: '순자산이 이전 스냅샷 대비 ${changePercent.abs().round()}% $direction.',
      ));
    }

    if (items.isEmpty) {
      items.add(const AdviceItem(
        category: 'general',
        message: '아직 특별한 변화가 없어요. 꾸준히 기록해보면 더 정확한 코멘트를 받을 수 있어요.',
      ));
    }

    return items;
  }
}
