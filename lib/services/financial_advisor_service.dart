import '../models/goal.dart';
import '../models/transaction.dart';
import '../models/user_profile.dart';
import 'claude_financial_advice_source.dart';
import 'finance_service.dart';
import 'financial_advice_source.dart';
import 'storage_service.dart';

export 'financial_advice_source.dart';

class FinancialAdvisorService {
  final StorageService storage;
  final FinancialAdviceSource source;

  static const refreshInterval = Duration(hours: 24);

  FinancialAdvisorService({
    required this.storage,
    FinancialAdviceSource? source,
  }) : source = source ?? LocalRuleFinancialAdviceSource();

  bool shouldRefresh(UserProfile profile) {
    final last = profile.lastAdviceRefresh;
    if (last == null) return true;
    return DateTime.now().difference(last) >= refreshInterval;
  }

  static Map<String, double> _expenseByCategory(List<Transaction> transactions, String monthKey) {
    final result = <String, double>{};
    for (final t in transactions) {
      if (t.type != TransactionType.expense) continue;
      if (monthKeyOf(t.date) != monthKey) continue;
      result[t.category] = (result[t.category] ?? 0) + t.amount;
    }
    return result;
  }

  /// Builds the summarized inputs for advice generation from current storage
  /// state: this month vs last month's spending by category, active
  /// financial-goal pacing, and net-worth trend between the two most recent
  /// asset snapshots.
  FinancialAdviceContext buildContext() {
    final now = DateTime.now();
    final transactions = storage.getTransactions();
    final currentMonthKey = monthKeyOf(now);
    final previousMonthKey = monthKeyOf(DateTime(now.year, now.month - 1));

    final goalProgress = storage
        .getGoals()
        .where((g) => g.status == GoalStatus.active && g.targetAmount != null && g.targetDate != null)
        .map((g) {
      final totalDurationDays = g.targetDate!.difference(g.createdAt).inDays;
      final elapsedDays = now.difference(g.createdAt).inDays;
      final expectedProgress = totalDurationDays > 0 ? (elapsedDays / totalDurationDays).clamp(0.0, 1.0) : null;
      final actualProgress = g.targetAmount! > 0 ? (g.currentAmount / g.targetAmount!).clamp(0.0, 1.0) : 0.0;
      return GoalProgressSummary(
        title: g.title,
        actualProgress: actualProgress,
        expectedProgress: expectedProgress,
      );
    }).toList();

    final snapshots = [...storage.getAssetSnapshots()]..sort((a, b) => a.importedAt.compareTo(b.importedAt));
    double? netWorthChange;
    double? netWorthChangePercent;
    if (snapshots.length >= 2) {
      final previous = snapshots[snapshots.length - 2];
      final latest = snapshots.last;
      netWorthChange = latest.netWorth - previous.netWorth;
      if (previous.netWorth != 0) {
        netWorthChangePercent = netWorthChange / previous.netWorth.abs() * 100;
      }
    }

    return FinancialAdviceContext(
      currentMonthExpenseByCategory: _expenseByCategory(transactions, currentMonthKey),
      previousMonthExpenseByCategory: _expenseByCategory(transactions, previousMonthKey),
      goalProgress: goalProgress,
      netWorthChange: netWorthChange,
      netWorthChangePercent: netWorthChangePercent,
    );
  }

  /// Regenerates advice if the refresh interval has elapsed. Tries Claude
  /// first if an API key is configured, falling back to the local rule
  /// engine on any failure — same pattern as
  /// QuestRecommendationService.refreshIfNeeded. Returns the existing cached
  /// advice untouched if a refresh wasn't due, or if both sources fail.
  Future<List<AdviceItem>> refreshIfNeeded() async {
    final profile = storage.getProfile();
    if (!shouldRefresh(profile)) {
      return profile.cachedAdvice.map(AdviceItem.fromJson).toList();
    }

    final context = buildContext();
    List<AdviceItem> advice;
    try {
      advice = await _activeSource().generateAdvice(context);
    } catch (_) {
      try {
        advice = await LocalRuleFinancialAdviceSource().generateAdvice(context);
      } catch (_) {
        return profile.cachedAdvice.map(AdviceItem.fromJson).toList();
      }
    }

    profile.lastAdviceRefresh = DateTime.now();
    profile.cachedAdvice = advice.map((a) => a.toJson()).toList();
    await storage.saveProfile(profile);
    return advice;
  }

  FinancialAdviceSource _activeSource() {
    if (source is! LocalRuleFinancialAdviceSource) return source;
    final apiKey = storage.claudeApiKey;
    if (apiKey == null || apiKey.trim().isEmpty) return source;
    return ClaudeFinancialAdviceSource(apiKey: apiKey);
  }
}
